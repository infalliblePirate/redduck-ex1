// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "./ERC20Exchange.sol";
import "../interfaces/IVotable.sol";

/**
 * @title ERC20VotingExchange
 * @author Kateryna Pavlenko
 */

contract ERC20VotingExchange is IVotable, ERC20Exchange {
    /// @notice Duration of each voting round
    uint256 public constant TIME_TO_VOTE = 1 days;

    /// @notice Minimum token ownership (in basis points) required to vote on a price
    /// @dev 5 basis points = 0.05% of total supply
    uint8 public constant VOTE_THRESHOLD_BPS = 5;

    /// @notice Denominator for basis point calculations
    /// @dev 10,000 basis points = 100%
    uint16 public constant BPS_DENOMINATOR = 10_000;

    /// @notice Counter for voting rounds
    /// @dev Increments with each new voting session
    uint256 private _votingNumber;

    mapping(uint256 => Round) private _rounds;

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
    ) ERC20Exchange(erc20, price_, feeBasisPoints) {}

    /**
     * @notice Ensures a voting round is currently active
     * @dev Checks that voting has started and hasn't exceeded TIME_TO_VOTE duration
     */
    modifier votingActive() {
        require(
            _rounds[_votingNumber].startTimestamp != 0 &&
                block.timestamp <
                    _rounds[_votingNumber].startTimestamp + TIME_TO_VOTE,
            "No active voting"
        );
        _;
    }

    /// @inheritdoc IVotable
    function startVoting() external override onlyOwner {
        require(
            _votingNumber == 0 || _rounds[_votingNumber].isEnded,
            "The previous voting hasn't ended"
        );
        uint256 newRound = ++_votingNumber;

        _rounds[newRound].startTimestamp = block.timestamp;
        _rounds[newRound].priceList = new SortedPriceList();

        emit StartVoting(msg.sender, newRound, block.timestamp);
    }

    function _updateWinner(uint256 price, uint256 votes) internal {
        _rounds[_votingNumber].priceList.upsert(price, votes);
    }

    /// @inheritdoc IVotable
    function vote(
        uint256 price,
        uint256 tokens
    ) external override votingActive {
        uint256 requiredSupplyToVote = (_TOKEN.totalSupply() *
            VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;

        uint256 balance = _TOKEN.balanceOf(msg.sender);
        require(balance >= tokens, "Not enough tokens on balance");

        require(tokens >= requiredSupplyToVote, "Not enough tokens to vote");

        require(price > 0, "Price must be greater than 0");

        _rounds[_votingNumber].votedAmount[msg.sender][price] += tokens;
        _updateWinner(
            price,
            _rounds[_votingNumber].priceList.getVotes(price) + tokens
        );

        require(
            _TOKEN.transferFrom(msg.sender, address(this), tokens),
            "Transfering reverted"
        );

        emit VoteCasted(msg.sender, _votingNumber, price, tokens);
    }

    /// @inheritdoc IVotable
    function endVoting() external override {
        Round storage round = _rounds[_votingNumber];

        require(round.startTimestamp != 0, "No active voting");
        require(!round.isEnded, "Voting already ended");
        require(
            block.timestamp >= round.startTimestamp + TIME_TO_VOTE,
            "Voting period has not expired"
        );

        round.isEnded = true;
        uint256 winningPirce = round.priceList.getTopPrice();
        if (winningPirce > 0) _setPrice(winningPirce);

        emit EndVoting(_votingNumber, winningPirce);
    }

    function withdrawTokens(uint256 votingNumber_, uint256 price) external {
        uint256 lockedTokens = _rounds[votingNumber_].votedAmount[msg.sender][
            price
        ];
        require(lockedTokens > 0, "No tokens to withdraw");

        _rounds[votingNumber_].votedAmount[msg.sender][price] = 0;
        require(
            _TOKEN.transfer(msg.sender, lockedTokens),
            "Transfering reverted"
        );

        if (!_rounds[votingNumber_].isEnded) {
            _updateWinner(
                price,
                _rounds[votingNumber_].priceList.getVotes(price) - lockedTokens
            );
        }
    }

    /// @inheritdoc IVotable
    function pendingPriceVotes(
        uint256 votingNumber_,
        uint256 price_
    ) external view override returns (uint256) {
        return _rounds[votingNumber_].priceList.getVotes(price_);
    }

    /// @inheritdoc IVotable
    function currentVotingNumber() external view override returns (uint256) {
        return _votingNumber;
    }

    /// @inheritdoc IVotable
    function votingStartedTimeStamp(
        uint256 votingNumber
    ) external view override returns (uint256) {
        return _rounds[votingNumber].startTimestamp;
    }
}
