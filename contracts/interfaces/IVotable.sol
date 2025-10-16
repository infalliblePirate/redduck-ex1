// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IVotable {
    event PriceSuggested(
        address indexed suggester,
        uint256 indexed votingNumber,
        uint256 price,
        uint256 weight
    );

    event VoteCasted(
        address indexed votes,
        uint256 indexed votingNumber,
        uint256 price,
        uint256 weight
    );

    event StartVoting(
        address indexed caller,
        uint256 votingNumber,
        uint256 timestamp
    );

    event EndVoting();

    function startVoting() external;

    function suggestNewPrice(uint256 price) external;

    function vote(uint256 price) external;

    function endVoting() external;

    function votingNumber() external view returns (uint256);

    function votingStartedTimeStamp() external view returns (uint256);

    function currentVotingNumber() external view returns (uint256);

    function pendingPriceVotes(
        uint256 votingNumber,
        uint256 price
    ) external view returns (uint256);
}
