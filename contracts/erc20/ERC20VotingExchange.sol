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

    /// @notice Array of all suggested prices for each voting round
    uint256[] private _suggestedPrices;

    mapping(uint256 => address[]) private _votedAddresses;
    mapping(address => bool) private _hasVoted;

    struct VotingResult {
        uint256 claimedWinningPrice;
        address proposer;
        uint256 proposedAt;
        bool finalized;
    }

    VotingResult private _votingResult; // votingNumber -> result

    uint256 public constant CHALLENGE_PERIOD = 2 hours;

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

    modifier notVoted() {
        require(_hasVoted[msg.sender] == false, "User has aleady voted");
        _;
    }

    /**
     * @notice Buy tokens with ETH (restricted during voting participation)
     * @dev Overrides parent function to add voting participation check
     * @return success True if purchase was successful
     */
    function buy() external payable override returns (bool) {
        return _buy(msg.value);
    }

    /**
     * @notice Sell tokens for ETH (restricted during voting participation)
     * @dev Overrides parent function to add voting participation check
     * @param value Amount of tokens to sell
     * @return success True if sale was successful
     */
    function sell(uint256 value) external override returns (bool) {
        return _sell(value);
    }

    /**
     * @notice Transfer tokens to another address (restricted during voting participation)
     * @dev Prevents token transfers while user has active vote/suggestion
     * @param to Recipient address
     * @param value Amount of tokens to transfer
     * @return success True if transfer was successful
     */
    function transfer(address to, uint256 value) external returns (bool) {
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

        emit StartVoting(msg.sender, _votingStartedTimeStamp);
    }

    /// @inheritdoc IVotable
    function vote(uint256 price) external override notVoted votingActive {
        uint256 requiredSupplyToVote = (_TOKEN.totalSupply() *
            VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;

        uint256 requiredSupplyToSuggest = (_TOKEN.totalSupply() *
            PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;

        uint256 weight = _TOKEN.balanceOf(msg.sender);
        if (_votedAddresses[price].length == 0) {
            require(
                weight >= requiredSupplyToSuggest,
                "The account cannot suggest price"
            );
            emit PriceSuggested(msg.sender, price, weight);
        } else {
            require(weight >= requiredSupplyToVote, "The account cannot vote");
            emit VoteCasted(msg.sender, price, weight);
        }
        _hasVoted[msg.sender] = true;
        _votedAddresses[price].push(msg.sender);
    }

    function proposeResult(uint256 winningPrice) external {
        require(_votingStartedTimeStamp != 0, "No voting in progress");
        require(
            block.timestamp >= _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );

        _votingResult = VotingResult({
            claimedWinningPrice: winningPrice,
            proposer: msg.sender,
            proposedAt: block.timestamp,
            finalized: false
        });
    }

    function _computeVotesForPrice(
        uint256 price
    ) internal view returns (uint256 total) {
        address[] memory voters = _votedAddresses[price];

        for (uint256 i = 0; i < voters.length; i++) {
            address voter = voters[i];
            total += _TOKEN.balanceOf(voter);
        }

        return total;
    }

    function challengeResult(uint256 claimedWinningPrice) external override {
        VotingResult memory result = _votingResult;

        require(result.proposedAt != 0, "No result to challenge");
        require(!result.finalized, "Result already finalized");
        require(
            block.timestamp < result.proposedAt + CHALLENGE_PERIOD,
            "Challenge period ended"
        );

        uint256 correctWinningPrice = 0;
        uint256 highestVotes = 0;

        uint256[] storage prices = _suggestedPrices;

        for (uint256 i = 0; i < prices.length; i++) {
            uint256 price = prices[i];
            uint256 votes = _computeVotesForPrice(price);

            if (votes > highestVotes) {
                highestVotes = votes;
                correctWinningPrice = price;
            }
        }

        require(
            correctWinningPrice == claimedWinningPrice,
            "The claimed winner is wrong"
        );
        emit ResultChallenged(0, correctWinningPrice, msg.sender);
    }

    function finalizeVoting() external override {
        VotingResult memory result = _votingResult;
        require(result.proposedAt != 0, "No result proposed");
        require(!result.finalized, "Already finalized");
        require(
            block.timestamp >= result.proposedAt + CHALLENGE_PERIOD,
            "Challenge period not ended"
        );

        if (result.claimedWinningPrice > 0) {
            _setPrice(result.claimedWinningPrice);
        }

        emit VotingFinalized(0, result.claimedWinningPrice);
        emit EndVoting(0, result.claimedWinningPrice);

        _votingStartedTimeStamp = 0;
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
    function getSuggestedPrices()
        external
        view
        override
        returns (uint256[] memory)
    {
        return _suggestedPrices;
    }
}
