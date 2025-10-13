// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IExchangable.sol";
import "../erc20/ERC20.sol";

contract ERC20Exchange is IExchangable, Ownable {
    ERC20 internal _token;

    uint256 internal _price;
    uint8 internal _percetageFee;
    uint256 internal _accumulatedFee;
    uint16 private constant FEE_DENOMINATOR = 10_000;

    constructor(
        address erc20,
        uint256 price_,
        uint8 percentageFee
    ) Ownable(msg.sender) {
        require(erc20 != address(0), "The token is a zero address");
        require(price_ > 0, "The price must be a positive number");
        require(
            percentageFee >= 0 && percentageFee < FEE_DENOMINATOR,
            "The fee is out of range"
        );
        _token = ERC20(erc20);
        _price = price_;
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
    }

    function sell(uint256 value) external override returns (bool) {}

    function liquidity() external view override returns (uint256, uint256) {
        return (payable(address(this)).balance, _token.balanceOf(address(this)));
    }

    function fee() external override returns (uint8) {}

    function setFee(uint8) external override returns (bool) {}
}
