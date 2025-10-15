// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

import "./ERC20Exchange.sol";
import "../interfaces/IVotable.sol";

contract ERC20VotingExchange is IVotable, ERC20Exchange {
    uint256 immutable TIME_TO_VOTE = 5 minutes;
    uint8 immutable PRICE_SUGGESTION_THRESHOLD_BPS = 10;
    uint8 immutable VOTE_THRESHOLD_BPS = 5;
    uint16 immutable BPS_DENOMINATOR = 10000;

    bool _isVotingActive = false;
    uint256 _votingStartedTimeStamp;
    uint256 _votingNumber = 0;

    mapping(uint256 => mapping(address => bool)) _isBalanceLocked;
    mapping(uint256 => uint256) _pendingPriceVotes;

    constructor(
        address erc20,
        uint256 price_,
        uint8 feeBasisPoints
    ) ERC20Exchange(erc20, price_, feeBasisPoints) {}

    modifier onlyNotVoted() {
        require(
            !_isBalanceLocked[_votingNumber][msg.sender],
            "The account has voted, cannot buy, sell or transfer"
        );
        _;
    }

    function buy() external payable override onlyNotVoted returns (bool) {
        return _buy(msg.value);
    }

    function sell(uint256 value) external override onlyNotVoted returns (bool) {
        return _sell(value);
    }

    function transfer(
        address to,
        uint256 value
    ) external onlyNotVoted returns (bool) {
        return _token.transfer(to, value);
    }

    function startVoting() external override onlyOwner{
        require(_isVotingActive == false, "Another voting is pending");
        _isVotingActive = true;
        _votingStartedTimeStamp = block.timestamp;

        unchecked {
            _votingNumber++;
        }

        emit StartVoting(msg.sender, _votingNumber, _votingStartedTimeStamp);
    }

    function vote(uint256 price) external override {
        require(_isVotingActive, "No active voting");

        require(
            block.timestamp < _votingStartedTimeStamp + TIME_TO_VOTE,
            "Cannot vote as the time has already passed"
        );

        uint256 requiredSupply = (_token.totalSupply() * VOTE_THRESHOLD_BPS) /
            BPS_DENOMINATOR;

        require(
            requiredSupply >= _token.balanceOf(msg.sender),
            "The account cannot vote"
        );
        require(_pendingPriceVotes[price] > 0, "Price has not been suggested");

        _isBalanceLocked[_votingNumber][msg.sender] = true;

        _pendingPriceVotes[price] += _token.balanceOf(msg.sender);
    }

    function suggestNewPrice(uint256 price) external override {
        require(
            block.timestamp < _votingStartedTimeStamp + TIME_TO_VOTE,
            "Cannot suggest the price as the time has already passed"
        );

        uint256 requiredSupply = (_token.totalSupply() *
            PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;

        require(
            requiredSupply >= _token.balanceOf(msg.sender),
            "The account cannot suggest price"
        );
        require(
            _pendingPriceVotes[price] == 0,
            "Price has already been suggested"
        );

        _pendingPriceVotes[price] = _token.balanceOf(msg.sender);
        _isBalanceLocked[_votingNumber][msg.sender] = true;
    }

    function endVoting() external override {
        require(
            block.timestamp > _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );
        _isVotingActive = false;
    }

    function votingNumber() external view onlyOwner override returns(uint256) {
        return _votingNumber;
    }

    function isVotingActive() external view returns (bool) {
        return _isVotingActive;
    }

    function votingStartedTimeStamp() external view override onlyOwner returns (uint256) {
        return _votingStartedTimeStamp;
    }
}
