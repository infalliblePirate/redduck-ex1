// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IEscrowable.sol";
import "../interfaces/IExchangable.sol";

contract EscrowExchange is IEscrowable, IExchangable, Ownable {
    ERC20 private immutable _TOKEN;

    mapping(address => uint256) private _balances;

    constructor(address token_) Ownable(msg.sender) {
        require(token_ != address(0), "Invalid token");
        _TOKEN = ERC20(token_);
    }

    function deposit(uint256 amount) external override {
        require(amount > 0, "Zero amount");
        require(
            _TOKEN.transferFrom(msg.sender, address(this), amount),
            "Transfer failed"
        );

        _balances[msg.sender] += amount;
    }

    function withdraw(uint256 amount) external override {
        require(amount > 0, "Zero amount");
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        _balances[msg.sender] -= amount;

        require(_TOKEN.transfer(msg.sender, amount), "Transfer failed");
    }

    function transfer(address to, uint256 amount) external override {
        require(to != address(0), "Invalid recipient");
        require(_balances[msg.sender] >= amount, "Insufficient balance");

        _balances[msg.sender] -= amount;
        _balances[to] += amount;
    }

    function balanceOf(address user) external view override returns (uint256) {
        return _balances[user];
    }

    function token() external view override returns (ERC20) {
        return _TOKEN;
    }

    function buy() external payable override returns (bool) {}

    function sell(uint256 value) external override returns (bool) {}

    function addLiquidity(uint256 tokenSupply) external payable override {}

    function liquidity() external view override returns (uint256, uint256) {}

    function price() external view override returns (uint256) {}

    function setPrice(uint256 newPrice) external override returns (bool) {}

    function feeBasisPoints() external view override returns (uint8) {}

    function setFeeBasisPoints(uint8 feeBps) external override returns (bool) {}

    function accumulatedFee() external override returns (uint256) {}

    function resetLiquidity(address to) external override returns (bool) {}

    function weeklyBurnFee() external override returns (bool) {}
}
