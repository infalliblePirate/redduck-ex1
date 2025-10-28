// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../erc20/ERC20.sol";

// todo: add events
interface IEscrowable {
    function deposit(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    function balanceOf(address user) external view returns (uint256);

    function token() external view returns (ERC20);
}
