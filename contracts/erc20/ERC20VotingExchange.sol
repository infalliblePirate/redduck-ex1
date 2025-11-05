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

    /// @notice Timestamp when the current voting round started
    /// @dev Set to 0 when no voting is active
    uint256 private _votingStartedTimeStamp;

    /// @notice Counter for voting rounds
    /// @dev Increments with each new voting session
    uint256 private _votingNumber;

    /// @notice Total voting weight for each price suggestion in each round
    /// @dev votingNumber => price => totalVotes
    mapping(uint256 => mapping(uint256 => uint256)) private _pendingPriceVotes;

    mapping(uint256 => mapping(address => uint256)) private _balances;

    uint256 internal _winningPrice;

    mapping(uint256 => bool) internal _isEnded;

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
            _votingStartedTimeStamp != 0 &&
                block.timestamp < _votingStartedTimeStamp + TIME_TO_VOTE,
            "No active voting"
        );
        _;
    }

    modifier oneVote() {
        require(
            _balances[_votingNumber][msg.sender] == 0,
            "User already voted"
        );
        _;
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
    function vote(
        uint256 price,
        uint256 tokens
    ) external override votingActive oneVote {
        uint256 requiredSupplyToVote = (_TOKEN.totalSupply() *
            VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;

        uint256 balance = _TOKEN.balanceOf(msg.sender);
        require(balance >= tokens, "Not enough tokens on balance");

        require(tokens >= requiredSupplyToVote, "Not enough tokens to vote");

        require(price > 0, "Price must be greater than 0");

        _pendingPriceVotes[_votingNumber][price] += tokens;
        _balances[_votingNumber][msg.sender] = tokens;
        _TOKEN.transferFrom(msg.sender, address(this), tokens);
        _updateWinner(price);

        emit VoteCasted(msg.sender, _votingNumber, price, tokens);
    }

    /// @inheritdoc IVotable
    function endVoting() external override {
        require(_votingStartedTimeStamp != 0, "No voting in progress");
        require(
            block.timestamp >= _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );

        uint256 winningPirce = _winningPrice;
        if (winningPirce > 0) _setPrice(winningPirce);

        _winningPrice = 0;
        _votingStartedTimeStamp = 0;
        _isEnded[_votingNumber] = true;

        emit EndVoting(_votingNumber, winningPirce);
    }

    function withdrawTokens(uint256 votingNumber_) external {
        require(_isEnded[votingNumber_], "The voting hasn't ended");
        
        uint256 balance = _balances[votingNumber_][msg.sender];
        require(balance > 0, "No tokens to withdraw");

        _balances[votingNumber_][msg.sender] = 0;
        require(_TOKEN.transfer(msg.sender, balance), "Transfering reverted");
    }

    /// @inheritdoc IVotable
    function pendingPriceVotes(
        uint256 votingNumber_,
        uint256 price_
    ) external view override returns (uint256) {
        return _pendingPriceVotes[votingNumber_][price_];
    }

    /// @inheritdoc IVotable
    function currentVotingNumber() external view override returns (uint256) {
        return _votingNumber;
    }

    /// @inheritdoc IVotable
    function votingStartedTimeStamp() external view override returns (uint256) {
        return _votingStartedTimeStamp;
    }
}
