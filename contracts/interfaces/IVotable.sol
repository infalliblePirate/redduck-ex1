// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IVotable
 * @notice Interface for a voting mechanism to determine token prices
 * @dev Implements a time-bound voting system where token holders can suggest and vote on price changes
 * @dev Voting power is proportional to token balance, and participants' tokens are locked during voting
 * @author Kateryna Pavlenko
 */
interface IVotable {
    /**
     * @notice Emitted when a new price is suggested by a token holder
     * @param suggester Address of the account suggesting the price
     * @param votingNumber Current voting round number
     * @param price Suggested price in wei per token
     * @param weight Voting weight of the suggester (their token balance)
     */
    event PriceSuggested(
        address indexed suggester,
        uint256 indexed votingNumber,
        uint256 price,
        uint256 weight
    );

    /**
     * @notice Emitted when a token holder votes for a suggested price
     * @param voter Address of the voting account
     * @param votingNumber Current voting round number
     * @param price Price being voted for
     * @param weight Voting weight of the voter (their token balance)
     */
    event VoteCasted(
        address indexed voter,
        uint256 indexed votingNumber,
        uint256 price,
        uint256 weight
    );

    /**
     * @notice Emitted when a new voting round starts
     * @param caller Address that initiated the voting round
     * @param votingNumber New voting round number
     * @param timestamp Block timestamp when voting started
     */
    event StartVoting(
        address indexed caller,
        uint256 votingNumber,
        uint256 timestamp
    );

    /**
     * @notice Emitted when a voting round ends
     * @param votingNumber Voting round number that ended
     * @param price Winning price (0 if no votes were cast)
     */
    event EndVoting(uint256 indexed votingNumber, uint256 price);

    event ResultChallenged(uint256, uint256, address);
    event VotingFinalized(uint256, uint256);

    /**
     * @notice Start a new voting round
     * @dev Only callable by owner. Cannot start if a voting round is already active
     * @dev Increments voting number and sets the voting start timestamp
     */
    function startVoting() external;

    /**
     * @notice Vote for an already suggested price
     * @dev Caller must hold at least VOTE_THRESHOLD_BPS of total supply
     * @dev Price must have been previously suggested in current round
     * @dev Locks caller's tokens until voting ends
     * @param price Price to vote for
     */
    function vote(uint256 price) external;

    /**
     * @notice Get the current voting round number
     * @dev Only callable by owner
     * @return currentNumber The current voting round number
     */
    function votingNumber() external view returns (uint256);

    /**
     * @notice Get the timestamp when the current voting round started
     * @dev Only callable by owner
     * @return startTime Timestamp when voting started (0 if no active voting)
     */
    function votingStartedTimeStamp() external view returns (uint256);

    /**
     * @notice Get the current voting round number
     * @dev Only callable by owner
     * @return currentNumber The current voting round number
     */
    function currentVotingNumber() external view returns (uint256);

    /**
     * @notice Get all suggested prices for a specific voting round
     * @param votingNumber_ Voting round number to query
     * @return prices Array of all suggested prices in that round
     */
    function getSuggestedPrices(
        uint256 votingNumber_
    ) external view returns (uint256[] memory);

    function challengeResult(uint256 claimedWinningPrice) external;

    function finalizeVoting() external;
}
