// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20Exchange.sol";
import "./EscrowExchange.sol";
import "../interfaces/IVotable.sol";

/**
 * @title ERC20VotingExchange
 * @author Kateryna Pavlenko
 */

contract ERC20VotingExchange is IVotable, EscrowExchange {
    /// @notice Duration of each voting round
    uint256 public constant TIME_TO_VOTE = 5 minutes;

    /// @notice Minimum token ownership (in basis points) required to suggest a new price
    /// @dev 10 basis points = 0.1% of total supply
    uint8 public constant PRICE_SUGGESTION_THRESHOLD_BPS = 10;

    /// @notice Minimum token ownership (in basis points) required to vote on a price
    /// @dev 5 basis points = 0.05% of total supply
    uint8 public constant VOTE_THRESHOLD_BPS = 5;

    /// @notice Denominator for basis point calculations
    /// @dev 10,000 basis points = 100%
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Timestamp when the current voting round started
    /// @dev Set to 0 when no voting is active
    uint256 private _votingStartedTimeStamp;

    /// @notice Counter for voting rounds
    /// @dev Increments with each new voting session
    uint256 private _votingNumber;

    /// @notice Total voting weight for each price suggestion in each round
    /// @dev votingNumber => price => totalVotes
    mapping(uint256 => mapping(uint256 => uint256)) private _pendingPriceVotes;

    /// @notice Array of all suggested prices for each voting round
    /// @dev votingNumber => array of suggested prices
    mapping(uint256 => uint256[]) private _suggestedPrices;

    mapping(uint256 => mapping(address => uint256)) private _stackedTokens; // user -> balance
    mapping(uint256 => mapping(address => uint256)) private _votedForPrice; // user -> price
    mapping(uint256 => mapping(uint256 => bool)) private _priceExists;

    uint256 internal _winningPrice;

    /**
     * @notice Creates a new voting-enabled exchange
     * @param erc20 Address of the erc20 contract
     * @param price_ Initial price per token in wei
     * @param feeBasisPoints Trading fee in basis points
     */
    constructor(
        address erc20,
        uint256 price_,
        uint8 feeBasisPoints
    ) EscrowExchange(erc20, price_, feeBasisPoints) {}

    /**
     * @notice Ensures a voting round is currently active
     * @dev Checks that voting has started and hasn't exceeded TIME_TO_VOTE duration
     */
    modifier votingActive() {
        require(
            _votingStartedTimeStamp != 0 &&
                block.timestamp < _votingStartedTimeStamp + TIME_TO_VOTE,
            "No active voting"
        );
        _;
    }

    function _updateVoteWeight(address user) internal {
        uint256 votedPrice = _votedForPrice[_votingNumber][user];
        if (votedPrice == 0) return;

        uint256 currentBalance = balanceOf(user);
        uint256 previousStacked = _stackedTokens[_votingNumber][user];

        if (currentBalance > previousStacked) {
            _pendingPriceVotes[_votingNumber][votedPrice] +=
                currentBalance - previousStacked;
        } else if (currentBalance < previousStacked) {
            uint256 dec = previousStacked - currentBalance;
            uint256 total = _pendingPriceVotes[_votingNumber][votedPrice];
            _pendingPriceVotes[_votingNumber][votedPrice] = dec >= total
                ? 0
                : total - dec;
        }

        _stackedTokens[_votingNumber][user] = currentBalance;
    }

    /**
     * @notice Buy tokens with ETH (restricted during voting participation)
     * @dev Overrides parent function to add voting participation check
     * @return success True if purchase was successful
     */
    function buy() external payable override returns (bool) {
        bool ok = _buy(msg.value);
        if (ok) {
            _updateVoteWeight(msg.sender);
        }
        _updateWinner(_votedForPrice[_votingNumber][msg.sender]);
        return ok;
    }

    /**
     * @notice Sell tokens for ETH (restricted during voting participation)
     * @dev Overrides parent function to add voting participation check
     * @param value Amount of tokens to sell
     * @return success True if sale was successful
     */
    function sell(uint256 value) external override returns (bool) {
        bool ok = _sell(value);
        if (ok) {
            _updateVoteWeight(msg.sender);
        }
        _updateWinner(_votedForPrice[_votingNumber][msg.sender]);
        return ok;
    }

    /**
     * @notice Transfer tokens to another address (restricted during voting participation)
     * @dev Prevents token transfers while user has active vote/suggestion
     * @param to Recipient address
     * @param value Amount of tokens to transfer
     * @return success True if transfer was successful
     */
    function transfer(address to, uint256 value) external returns (bool) {
        bool ok = transferFrom(msg.sender, to, value);
        if (ok) {
            _updateVoteWeight(msg.sender);
            _updateVoteWeight(to);
        }
        _updateWinner(_votedForPrice[_votingNumber][to]);
        return ok;
    }

    /// @inheritdoc IVotable
    function startVoting() external override onlyOwner {
        require(
            _votingStartedTimeStamp == 0 ||
                block.timestamp >= _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting already active"
        );

        _votingStartedTimeStamp = block.timestamp;
        unchecked {
            _votingNumber++;
        }

        emit StartVoting(msg.sender, _votingNumber, _votingStartedTimeStamp);
    }

    function _updateWinner(uint256 price) internal {
        if (
            _pendingPriceVotes[_votingNumber][price] >
            _pendingPriceVotes[_votingNumber][_winningPrice]
        ) {
            _winningPrice = price;
        }
    }

    /// @inheritdoc IVotable
    function vote(uint256 price) external override votingActive {
        uint256 requiredSupplyToVote = (_TOKEN.totalSupply() *
            VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;

        uint256 requiredSupplyToSuggest = (_TOKEN.totalSupply() *
            PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;

        uint256 currentBalance = balanceOf(msg.sender);

        require(
            _votedForPrice[_votingNumber][msg.sender] == 0,
            "Already voted"
        );

        bool isPriceNew = !_priceExists[_votingNumber][price];

        if (isPriceNew) {
            require(
                currentBalance >= requiredSupplyToSuggest,
                "The account cannot suggest price"
            );
            _suggestedPrices[_votingNumber].push(price);
            _priceExists[_votingNumber][price] = true;
            emit PriceSuggested(
                msg.sender,
                _votingNumber,
                price,
                currentBalance
            );
        } else {
            require(
                currentBalance >= requiredSupplyToVote,
                "The account cannot vote"
            );
            emit VoteCasted(msg.sender, _votingNumber, price, currentBalance);
        }

        _pendingPriceVotes[_votingNumber][price] += currentBalance;
        _stackedTokens[_votingNumber][msg.sender] = currentBalance;
        _votedForPrice[_votingNumber][msg.sender] = price;
        _updateWinner(price);
    }

    /// @inheritdoc IVotable
    function endVoting() external override {
        require(_votingStartedTimeStamp != 0, "No voting in progress");
        require(
            block.timestamp >= _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );

        emit EndVoting(_votingNumber, _winningPrice);
        _setPrice(_winningPrice);
        _winningPrice = 0;
        _votingStartedTimeStamp = 0;
    }

    /// @inheritdoc IVotable
    function votingNumber() external view override onlyOwner returns (uint256) {
        return _votingNumber;
    }

    /// @inheritdoc IVotable
    function pendingPriceVotes(
        uint256 votingNumber_,
        uint256 price_
    ) external view override onlyOwner returns (uint256) {
        return _pendingPriceVotes[votingNumber_][price_];
    }

    /// @inheritdoc IVotable
    function currentVotingNumber()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _votingNumber;
    }

    /// @inheritdoc IVotable
    function votingStartedTimeStamp()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _votingStartedTimeStamp;
    }

    /// @inheritdoc IVotable
    function getSuggestedPrices(
        uint256 votingNumber_
    ) external view override returns (uint256[] memory) {
        return _suggestedPrices[votingNumber_];
    }
}
