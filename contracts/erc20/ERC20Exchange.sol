// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IExchangable.sol";
import "../erc20/ERC20.sol";

contract ERC20Exchange is IExchangable, Ownable {
    ERC20 internal _token;

    uint256 internal _price;
    uint8 internal _feeBasisPoints;
    uint256 internal _accumulatedFee;
    uint16 private constant FEE_DENOMINATOR = 10_000;

    uint256 public lastBurnTimestamp;
    uint256 constant BURN_INTERVAL = 7 days;

    constructor(
        address erc20,
        uint256 price_,
        uint8 feeBasisPoints
    ) Ownable(msg.sender) {
        require(erc20 != address(0), "The token is a zero address");
        require(price_ > 0, "The price must be a positive number");
        require(
            feeBasisPoints >= 0 && feeBasisPoints < FEE_DENOMINATOR,
            "The fee is out of range"
        );
        _token = ERC20(erc20);
        _price = price_;
        _feeBasisPoints = feeBasisPoints;
        lastBurnTimestamp = block.timestamp;
    }

    function addLiquidity(
        uint256 tokenAmount
    ) external payable override onlyOwner {
        require(tokenAmount > 0, "The inital supply must be a positive number");
        uint256 value = msg.value;
        require(value > 0, "The ether reserve must be a positive number");

        uint256 supply = tokenAmount;
        _token.mint(address(this), supply);

        emit LiquidityChanged(msg.sender, value, tokenAmount);
    }

    function price() external view override returns (uint256) {
        return _price;
    }

    function token() external view returns (address) {
        return address(_token);
    }

    function setPrice(
        uint256 price_
    ) external override onlyOwner returns (bool) {
        _price = price_;
        return true;
    }

    function _setPrice(
        uint256 price_
    ) internal onlyOwner returns (bool) {
        _price = price_;
        return true;
    }

    function buy() external payable virtual override returns (bool) {
        return _buy(msg.value);
    }

    function _buy(uint256 value) internal returns (bool) {
        uint256 tokens = (value * 10 ** _token.decimals()) / _price;
        uint256 fee = (tokens * _feeBasisPoints) / FEE_DENOMINATOR;
        _accumulatedFee += fee;

        uint256 tokensAfterFee = tokens - fee;
        require(tokensAfterFee > 0, "No sufficient funds to buy token");
        require(
            _token.balanceOf(address(this)) >= tokensAfterFee + _accumulatedFee,
            "The number of requested tokens exceeds liquidity pool"
        );
        _token.transfer(msg.sender, tokensAfterFee);

        emit Buy(msg.sender, tokensAfterFee, value, fee);
        return true;
    }

    function sell(uint256 value) external virtual override returns (bool) {
        return _sell(value);
    }

    function _sell(uint256 value) internal returns (bool) {
        require(
            _token.balanceOf(msg.sender) >= value,
            "The account does not that many tokens"
        );
        uint256 fee = (value * _feeBasisPoints) / FEE_DENOMINATOR;
        uint256 soldTokens = value - fee;
        uint256 ethToSend = (soldTokens * _price) / (10 ** _token.decimals());
        _accumulatedFee += fee;
        require(
            ethToSend <= payable(address(this)).balance,
            "The exchange does not have enough eth liquidity"
        );
        _token.transferFrom(msg.sender, address(this), value);
        payable(msg.sender).transfer(ethToSend);

        emit Sell(msg.sender, soldTokens, ethToSend, fee);
        return true;
    }

    function liquidity() external view override returns (uint256, uint256) {
        return (
            payable(address(this)).balance,
            _token.balanceOf(address(this))
        );
    }

    function feeBasisPoints() external view override onlyOwner returns (uint8) {
        return _feeBasisPoints;
    }

    function setFeeBasisPoints(
        uint8 feeBP
    ) external override onlyOwner returns (bool) {
        _feeBasisPoints = feeBP;
        return true;
    }

    function accumulatedFee()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _accumulatedFee;
    }

    function resetLiquidity(
        address to
    ) external override onlyOwner returns (bool) {
        _token.transfer(to, _token.balanceOf(address(this)));
        payable(msg.sender).transfer(payable(address(this)).balance);
        return true;
    }

    function weeklyBurnFee() external override onlyOwner returns (bool) {
        require(
            block.timestamp >= lastBurnTimestamp + BURN_INTERVAL,
            "Burn not available yet"
        );
        lastBurnTimestamp = block.timestamp;
        _token.burn(address(this), _accumulatedFee);
        emit WeeklyBurn(msg.sender, _accumulatedFee, block.timestamp);
        _accumulatedFee = 0;
    }
}
