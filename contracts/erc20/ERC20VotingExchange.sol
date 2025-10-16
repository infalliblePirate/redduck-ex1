// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./ERC20Exchange.sol";
import "../interfaces/IVotable.sol";

contract ERC20VotingExchange is IVotable, ERC20Exchange {
    uint256 public constant TIME_TO_VOTE = 5 minutes;
    uint8 public constant PRICE_SUGGESTION_THRESHOLD_BPS = 10;
    uint8 public constant VOTE_THRESHOLD_BPS = 5;
    uint16 public constant BPS_DENOMINATOR = 10_000;

    uint256 private _votingStartedTimeStamp;
    uint256 private _votingNumber;

    mapping(uint256 => mapping(address => bool)) private _isBalanceLocked;
    mapping(uint256 => mapping(uint256 => uint256)) private _pendingPriceVotes;
    mapping(uint256 => uint256[]) private _suggestedPrices;

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

    modifier votingActive() {
        require(
            _votingStartedTimeStamp != 0 &&
                block.timestamp < _votingStartedTimeStamp + TIME_TO_VOTE,
            "No active voting"
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

    function vote(uint256 price) external override onlyNotVoted votingActive {
        uint256 requiredSupply = (_token.totalSupply() * VOTE_THRESHOLD_BPS) /
            BPS_DENOMINATOR;
        uint256 weight = _token.balanceOf(msg.sender);

        require(weight >= requiredSupply, "The account cannot vote");
        require(
            _pendingPriceVotes[_votingNumber][price] > 0,
            "Price has not been suggested"
        );

        _isBalanceLocked[_votingNumber][msg.sender] = true;
        _pendingPriceVotes[_votingNumber][price] += weight;

        emit VoteCasted(msg.sender, _votingNumber, price, weight);
    }

    function suggestNewPrice(
        uint256 price
    ) external override onlyNotVoted votingActive {
        uint256 requiredSupply = (_token.totalSupply() *
            PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;
        uint256 weight = _token.balanceOf(msg.sender);

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
            _token.balanceOf(msg.sender)
        );
    }

    function endVoting() external override {
        require(
            block.timestamp > _votingStartedTimeStamp + TIME_TO_VOTE,
            "Voting is still in progress"
        );
    }

    function votingNumber() external view override onlyOwner returns (uint256) {
        return _votingNumber;
    }

    function pendingPriceVotes(
        uint256 votingNumber_,
        uint256 price_
    ) external view override onlyOwner returns (uint256) {
        return _pendingPriceVotes[votingNumber_][price_];
    }

    function currentVotingNumber()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _votingNumber;
    }

    function votingStartedTimeStamp()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _votingStartedTimeStamp;
    }
}
