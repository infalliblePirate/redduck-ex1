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
    uint256 public constant TIME_TO_VOTE = 3 days;

    uint32 public constant CHALLENGE_PERIOD = 1 days;

    /// @notice Minimum token ownership (in basis points) required to vote on a price
    /// @dev 5 basis points = 0.05% of total supply
    uint8 public constant VOTE_THRESHOLD_BPS = 5;

    /// @notice Denominator for basis point calculations
    /// @dev 10,000 basis points = 100%
    uint16 public constant BPS_DENOMINATOR = 10_000;

    uint256 public constant ETH_TO_SUGGEST_WINNER = 0.5 ether;

    uint8 private constant SLASHING_PERCENTAGE = 50;
    uint8 private constant SLASHING_DENOMINATOR = 100;

    uint256 public constant FINALIZE_REWARD = 0.01 ether;

    /// @notice Timestamp when the current voting round started
    /// @dev Set to 0 when no voting is active
    uint256 private _votingStartedTimeStamp;

    /// @notice Counter for voting rounds
    /// @dev Increments with each new voting session
    uint256 private _votingNumber;

    mapping(uint256 => mapping(uint256 => uint256)) _votesForPrice; // [votingNumber][price] => votes

    mapping(uint256 => mapping(address => uint256)) _lockedTokens; // user => lockedTokens
    mapping(uint256 => mapping(address => uint256)) _stackedEth; // user => stackedEth

    /// @notice Voting results for each voting round
    /// @dev votingNumber => VotingResult
    mapping(uint256 => VotingResult) private _votingResults;

    mapping(uint256 => mapping(address => bool)) private _hasVoted;

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

    modifier oneVote() {
        require(
            _hasVoted[_votingNumber][msg.sender] == false,
            "User already voted"
        );
        _;
        _hasVoted[_votingNumber][msg.sender] = true;
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

    function vote(
        uint256 price,
        uint256 tokensLocked
    ) external override votingActive oneVote {
        require(price > 0, "Price must be above 0");
        require(
            tokensLocked <= _TOKEN.balanceOf(msg.sender),
            "The locked tokens amount exceeds user balance"
        );

        uint256 requiredSupplyToVote = (_TOKEN.totalSupply() *
            VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;
        require(
            tokensLocked >= requiredSupplyToVote,
            "Not enough tokens to vote"
        );

        _votesForPrice[_votingNumber][price] += tokensLocked;

        _lockedTokens[_votingNumber][msg.sender] += tokensLocked;
        require(
            _TOKEN.transferFrom(msg.sender, address(this), tokensLocked),
            "Transfering failed"
        );

        emit VoteCasted(msg.sender, _votingNumber, price, tokensLocked);
    }

    function propose(uint256 winningPrice) external payable {
        require(_votingStartedTimeStamp != 0, "No voting in progress");
        require(
            block.timestamp >= _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );

        require(
            msg.value == ETH_TO_SUGGEST_WINNER,
            "Incorrect ETH amount to propose winner"
        );

        VotingResult storage result = _votingResults[_votingNumber];

        require(!result.finalized, "Already finalized");

        require(
            result.isChallenged || result.proposer == address(0),
            "Previous proposing result pending"
        );

        _stackedEth[_votingNumber][msg.sender] += msg.value;

        result.claimedWinningPrice = winningPrice;
        result.proposer = msg.sender;
        result.proposedAt = block.timestamp;
        result.isChallenged = false;

        emit ResultProposed(
            msg.sender,
            _votingNumber,
            winningPrice,
            block.timestamp
        );
    }

    function challenge(uint256 challengingPrice) external {
        VotingResult storage result = _votingResults[_votingNumber];
        require(
            block.timestamp < result.proposedAt + CHALLENGE_PERIOD,
            "Challenge period expired, call finalizeVoting()"
        );

        require(
            _votesForPrice[_votingNumber][challengingPrice] >
                _votesForPrice[_votingNumber][result.claimedWinningPrice],
            "Challenging failed"
        );

        require(!result.isChallenged, "The price was already challenged");

        uint256 slashedBalance = (_stackedEth[_votingNumber][result.proposer] *
            SLASHING_PERCENTAGE) / SLASHING_DENOMINATOR;

        _stackedEth[_votingNumber][result.proposer] -= slashedBalance;
        _stackedEth[_votingNumber][msg.sender] += slashedBalance;

        result.isChallenged = true;
    }

    function finalizeVoting() external override {
        VotingResult storage result = _votingResults[_votingNumber];
        require(result.proposedAt != 0, "No result proposed");
        require(!result.finalized, "Already finalized");
        require(
            block.timestamp >= result.proposedAt + CHALLENGE_PERIOD,
            "Challenge period not ended"
        );
        require(
            payable(address(this)).balance >= FINALIZE_REWARD,
            "Not enough liquidty to reward finalization"
        );

        if (result.claimedWinningPrice > 0) {
            _setPrice(result.claimedWinningPrice);
        }

        emit VotingFinalized(_votingNumber, result.claimedWinningPrice);
        result.finalized = true;

        _votingStartedTimeStamp = 0;
        payable(msg.sender).transfer(FINALIZE_REWARD);
    }

    function withdrawTokens(uint256 votingNumber_) external {
        VotingResult storage result = _votingResults[votingNumber_];
        require(result.finalized, "The result is not yet finalized");

        uint256 balance = _lockedTokens[votingNumber_][msg.sender];
        _lockedTokens[votingNumber_][msg.sender] = 0;

        require(_TOKEN.transfer(msg.sender, balance), "Transfering failed");
    }

    function withdrawEth(uint256 votingNumber_) external {
        VotingResult storage result = _votingResults[votingNumber_];
        require(result.finalized, "The voting isn't finalized");

        uint256 balance = _stackedEth[votingNumber_][msg.sender];
        _stackedEth[votingNumber_][msg.sender] = 0;

        payable(msg.sender).transfer(balance);
    }

    /// @inheritdoc IVotable
    function votingNumber() external view returns (uint256) {
        return _votingNumber;
    }

    /// @inheritdoc IVotable
    function votingStartedTimeStamp() external view override returns (uint256) {
        return _votingStartedTimeStamp;
    }

    /// @inheritdoc IVotable
    function votingResult(
        uint256 votingNumber_
    ) external view override returns (VotingResult memory) {
        return _votingResults[votingNumber_];
    }

    /// @inheritdoc IVotable
    function votesForPrice(
        uint256 votingNumber_,
        uint256 price
    ) external view returns (uint256) {
        return _votesForPrice[votingNumber_][price];
    }

    /// @inheritdoc IVotable
    function lockedTokens(
        uint256 votingNumber_,
        address user
    ) external view returns (uint256) {
        return _lockedTokens[votingNumber_][user];
    }

    /// @inheritdoc IVotable
    function stackedEth(
        uint256 votingNumber_,
        address user
    ) external view returns (uint256) {
        return _stackedEth[votingNumber_][user];
    }

    /// @inheritdoc IVotable
    function hasVoted(
        uint256 votingNumber_,
        address user
    ) external view returns (bool) {
        return _hasVoted[votingNumber_][user];
    }
}
