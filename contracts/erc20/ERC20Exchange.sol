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

    function setPrice(uint256 price_) external override returns (bool) {
        _price = price_;
        return true;
    }

    function buy() external payable override returns (bool) {
        uint256 tokens = (msg.value * 10 ** _token.decimals()) / _price;
        uint256 fee = (tokens * _feeBasisPoints) / FEE_DENOMINATOR;
        _accumulatedFee += fee;

        uint256 tokensAfterFee = tokens - fee;
        require(tokensAfterFee > 0, "No sufficient funds to buy token");
        require(
            _token.balanceOf(address(this)) >= tokensAfterFee,
            "The number of requested tokens exceeds liquidity pool"
        );
        _token.transfer(msg.sender, tokensAfterFee);

        emit Buy(msg.sender, tokensAfterFee, msg.value, fee);
        return true;
    }

    function sell(uint256 value) external override returns (bool) {}

    function liquidity() external view override returns (uint256, uint256) {
        return (
            payable(address(this)).balance,
            _token.balanceOf(address(this))
        );
    }

    function fee() external override onlyOwner returns (uint8) {}

    function setFee(uint8) external override onlyOwner returns (bool) {}

    function accumulatedFee()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _accumulatedFee;
    }
}
