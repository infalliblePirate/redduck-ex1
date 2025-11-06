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

    /// @notice Counter for voting rounds
    /// @dev Increments with each new voting session
    uint256 private _votingNumber;

    mapping(uint256 => Round) private _rounds;

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

    modifier oneVote() {
        require(
            _rounds[_votingNumber].votedAmount[msg.sender] == 0,
            "User already voted"
        );
        _;
    }

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
        Round storage prevRound = _rounds[_votingNumber];
        require(
            prevRound.startTimestamp == 0 || prevRound.isEnded,
            "Voting already active"
        );

        _votingNumber++;
        _rounds[_votingNumber].startTimestamp = block.timestamp;

        emit StartVoting(msg.sender, _votingNumber, block.timestamp);
    }

    function vote(
        uint256 price,
        uint256 tokensLocked
    ) external override oneVote votingActive {
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

        Round storage round = _rounds[_votingNumber];
        round.priceVotes[price] += tokensLocked;
        round.votedAmount[msg.sender] = tokensLocked;

        require(
            _TOKEN.transferFrom(msg.sender, address(this), tokensLocked),
            "Transfering failed"
        );

        emit VoteCasted(msg.sender, _votingNumber, price, tokensLocked);
    }

    function propose(uint256 winningPrice) external payable {
        Round storage round = _rounds[_votingNumber];

        require(round.startTimestamp != 0, "No voting in progress");
        require(
            block.timestamp >= round.startTimestamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );
        require(
            msg.value == ETH_TO_SUGGEST_WINNER,
            "Incorrect ETH amount to propose winner"
        );

        VotingResult storage result = _rounds[_votingNumber].votingResult;
        require(!round.isEnded, "Round already ended");
        require(
            result.isChallenged || result.proposer == address(0),
            "Previous proposing result pending"
        );

        round.stackedEth[msg.sender] += msg.value;

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
        Round storage round = _rounds[_votingNumber];
        VotingResult storage result = round.votingResult;

        require(
            block.timestamp < result.proposedAt + CHALLENGE_PERIOD,
            "Challenge period expired, call finalizeVoting()"
        );
        require(
            round.priceVotes[challengingPrice] >
                round.priceVotes[result.claimedWinningPrice],
            "Challenging failed"
        );
        require(!result.isChallenged, "The price was already challenged");

        uint256 slashedBalance = (round.stackedEth[result.proposer] *
            SLASHING_PERCENTAGE) / SLASHING_DENOMINATOR;

        round.stackedEth[result.proposer] -= slashedBalance;
        round.stackedEth[msg.sender] += slashedBalance;

        result.isChallenged = true;
    }

    function finalizeVoting() external override {
        VotingResult storage result = _rounds[_votingNumber].votingResult;
        require(result.proposedAt != 0, "No result proposed");
        require(!_rounds[_votingNumber].isEnded, "Already finalized");
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
        _rounds[_votingNumber].isEnded = true;

        payable(msg.sender).transfer(FINALIZE_REWARD);
    }

    function withdrawTokens(uint256 votingNumber_) external {
        Round storage round = _rounds[votingNumber_];
        require(round.isEnded, "The result is not yet finalized");

        uint256 balance = round.votedAmount[msg.sender];
        require(balance > 0, "Nothing to withdraw");
        round.votedAmount[msg.sender] = 0;

        require(_TOKEN.transfer(msg.sender, balance), "Transfering failed");
    }

    function withdrawEth(uint256 votingNumber_) external {
        Round storage round = _rounds[votingNumber_];
        require(round.isEnded, "The voting isn't finalized");

        uint256 balance = round.stackedEth[msg.sender];
        require(balance > 0, "Nothing to withdraw");

        round.stackedEth[msg.sender] = 0;

        payable(msg.sender).transfer(balance);
    }

    /// @inheritdoc IVotable
    function votingNumber() external view returns (uint256) {
        return _votingNumber;
    }

    /// @inheritdoc IVotable
    function votingStartedTimeStamp() external view override returns (uint256) {
        return _rounds[_votingNumber].startTimestamp;
    }

    /// @inheritdoc IVotable
    function votingResult(
        uint256 votingNumber_
    ) external view override returns (VotingResult memory) {
        return _rounds[votingNumber_].votingResult;
    }

    /// @inheritdoc IVotable
    function votesForPrice(
        uint256 votingNumber_,
        uint256 price
    ) external view returns (uint256) {
        return _rounds[votingNumber_].priceVotes[price];
    }

    /// @inheritdoc IVotable
    function lockedTokens(
        uint256 votingNumber_,
        address user
    ) external view returns (uint256) {
        return _rounds[votingNumber_].votedAmount[user];
    }

    /// @inheritdoc IVotable
    function stackedEth(
        uint256 votingNumber_,
        address user
    ) external view returns (uint256) {
        return _rounds[votingNumber_].stackedEth[user];
    }
}
