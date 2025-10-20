// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20Exchange.sol";
import "../interfaces/IVotable.sol";

/**
 * @title ERC20VotingExchange
 * @notice Extended ERC20Tradable contract with ability to vote for a price change
 * @author Kateryna Pavlenko 
 */

contract ERC20VotingExchange is IVotable, ERC20Exchange {
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

    /// @notice Tracks whether an address has participated in a specific voting round
    /// @dev votingNumber => address => hasVoted
    /// @dev Prevents double voting and locks tokens during active voting
    mapping(uint256 => mapping(address => bool)) private _isBalanceLocked;

    /// @notice Total voting weight for each price suggestion in each round
    /// @dev votingNumber => price => totalVotes
    mapping(uint256 => mapping(uint256 => uint256)) private _pendingPriceVotes;

    /// @notice Array of all suggested prices for each voting round
    /// @dev votingNumber => array of suggested prices
    mapping(uint256 => uint256[]) private _suggestedPrices;

    /**
     * @notice Creates a new voting-enabled exchange
     * @param erc20 Address of the ERC20 token contract
     * @param price_ Initial price per token in wei
     * @param feeBasisPoints Trading fee in basis points
     */
    constructor(
        address erc20,
        uint256 price_,
        uint8 feeBasisPoints
    ) ERC20Exchange(erc20, price_, feeBasisPoints) {}

    /**
     * @notice Restricts function access to accounts that haven't voted in current round
     * @dev Prevents buying, selling, or transferring when user is participating in active voting
     */
    modifier onlyNotVoted() {
        require(
            !_isBalanceLocked[_votingNumber][msg.sender],
            "The account has voted, cannot buy, sell or transfer"
        );
        _;
    }

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

    /**
     * @notice Buy tokens with ETH (restricted during voting participation)
     * @dev Overrides parent function to add voting participation check
     * @return success True if purchase was successful
     */
    function buy() external payable override onlyNotVoted returns (bool) {
        return _buy(msg.value);
    }

    /**
     * @notice Sell tokens for ETH (restricted during voting participation)
     * @dev Overrides parent function to add voting participation check
     * @param value Amount of tokens to sell
     * @return success True if sale was successful
     */
    function sell(uint256 value) external override onlyNotVoted returns (bool) {
        return _sell(value);
    }

    /**
     * @notice Transfer tokens to another address (restricted during voting participation)
     * @dev Prevents token transfers while user has active vote/suggestion
     * @param to Recipient address
     * @param value Amount of tokens to transfer
     * @return success True if transfer was successful
     */
    function transfer(
        address to,
        uint256 value
    ) external onlyNotVoted returns (bool) {
        return _TOKEN.transfer(to, value);
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

    /// @inheritdoc IVotable
    function vote(uint256 price) external override onlyNotVoted votingActive {
        uint256 requiredSupply = (_TOKEN.totalSupply() * VOTE_THRESHOLD_BPS) /
            BPS_DENOMINATOR;
        uint256 weight = _TOKEN.balanceOf(msg.sender);

        require(weight >= requiredSupply, "The account cannot vote");
        require(
            _pendingPriceVotes[_votingNumber][price] > 0,
            "Price has not been suggested"
        );

        _isBalanceLocked[_votingNumber][msg.sender] = true;
        _pendingPriceVotes[_votingNumber][price] += weight;

        emit VoteCasted(msg.sender, _votingNumber, price, weight);
    }

    /// @inheritdoc IVotable
    function suggestNewPrice(
        uint256 price
    ) external override onlyNotVoted votingActive {
        uint256 requiredSupply = (_TOKEN.totalSupply() *
            PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;
        uint256 weight = _TOKEN.balanceOf(msg.sender);

        require(weight >= requiredSupply, "The account cannot suggest price");
        require(
            _pendingPriceVotes[_votingNumber][price] == 0,
            "Price has already been suggested"
        );

        _pendingPriceVotes[_votingNumber][price] += weight;
        _suggestedPrices[_votingNumber].push(price);
        _isBalanceLocked[_votingNumber][msg.sender] = true;

        emit PriceSuggested(
            msg.sender,
            _votingNumber,
            price,
            _TOKEN.balanceOf(msg.sender)
        );
    }

    /// @inheritdoc IVotable
    function endVoting() external override {
        require(_votingStartedTimeStamp != 0, "No voting in progress");
        require(
            block.timestamp >= _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );

        uint256 winningPrice = 0;
        uint256 highestVotes = 0;

        uint256[] storage prices = _suggestedPrices[_votingNumber];
        for (uint256 i = 0; i < prices.length; i++) {
            uint256 price = prices[i];
            uint256 votes = _pendingPriceVotes[_votingNumber][price];
            if (votes > highestVotes) {
                highestVotes = votes;
                winningPrice = price;
            }
        }

        if (winningPrice > 0) {
            _setPrice(winningPrice);
        }

        _votingStartedTimeStamp = 0;

        emit EndVoting(_votingNumber, winningPrice);
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