// SPDX-License-Identifier: MIT

pragma solidity ^0.8.9;

interface IExchangable {
    event Buy(
        address indexed buyer,
        uint256 tokensBought,
        uint256 spentEth,
        uint256 feeInTokens
    );

    event Sell(
        address indexed seller,
        uint256 tokensSold,
        uint256 sentEth,
        uint256 feeInTokens
    );

    event LiquidityChanged(
        address indexed initiator,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    event WeeklyBurn(
        address indexed sender,
        uint256 burnAmount,
        uint256 timestamp
    );

    function buy() external payable returns (bool);

    function sell(uint256 value) external returns (bool);

    function addLiquidity(uint256 tokenSupply) external payable;

    function liquidity() external view returns (uint256, uint256);

    function price() external view returns (uint256);

    function setPrice(uint256) external returns (bool);

    function feeBasisPoints() external view returns (uint8);

    function setFeeBasisPoints(uint8) external returns (bool);

    function accumulatedFee() external returns (uint256);

    function resetLiquidity(address to) external returns (bool);

    function weeklyBurnFee() external returns (bool);
}
