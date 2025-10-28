// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../erc20/ERC20.sol";

/**
 * @title IEscrowable
 * @notice Interface defining an escrow system for ERC20 tokens.
 * @dev Used by exchanges to allow users to deposit, withdraw, and transfer escrowed tokens.
 */
interface IEscrowable {
    /**
     * @notice Emitted when a user deposits tokens into escrow.
     * @param user The address of the depositor.
     * @param amount The amount of tokens deposited.
     */
    event Deposited(address indexed user, uint256 amount);

    /**
     * @notice Emitted when a user withdraws tokens from escrow.
     * @param user The address of the withdrawer.
     * @param amount The amount of tokens withdrawn.
     */
    event Withdrawn(address indexed user, uint256 amount);

    /**
     * @notice Emitted when escrowed tokens are transferred between users.
     * @param from The sender of the escrowed tokens.
     * @param to The recipient of the escrowed tokens.
     * @param amount The amount of tokens transferred.
     */
    event EscrowTransfer(
        address indexed from,
        address indexed to,
        uint256 amount
    );

    /**
     * @notice Deposits tokens into the contract’s escrow balance.
     * @param amount Amount of tokens to deposit.
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Withdraws tokens from escrow to the user's wallet.
     * @param amount Amount of tokens to withdraw.
     */
    function withdraw(uint256 amount) external;

    /**
     * @notice Transfers escrowed tokens from one user to another.
     * @param from Address of the sender.
     * @param to Address of the recipient.
     * @param amount Amount of tokens to transfer.
     * @return success Returns true on success.
     */
    function transferFrom(
        address from,
        address to,
        uint256 amount
    ) external returns (bool);

    /**
     * @notice Returns the escrowed token balance of a user.
     * @param user The address to check.
     * @return balance The amount of tokens held in escrow.
     */
    function balanceOf(address user) external view returns (uint256 balance);

    /**
     * @notice Returns the ERC20 token associated with this escrow.
     * @return token The ERC20 token contract.
     */
    function token() external view returns (ERC20 token);
}
