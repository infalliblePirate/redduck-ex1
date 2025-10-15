// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IVotable {
    event StartVoting(address caller, uint256 votingNumber, uint256 timestamp);

    event EndVoting();

    function startVoting() external;

    function suggestNewPrice(uint256 price) external;

    function vote(uint256 price) external;

    function endVoting() external;

    function votingNumber() external view returns (uint256);

    function votingStartedTimeStamp() external view returns (uint256);
}
