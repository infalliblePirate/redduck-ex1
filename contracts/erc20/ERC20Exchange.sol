// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "../erc20/ERC20.sol";

contract ERC20Exchange {

    ERC20 internal _token;

    uint256 internal _price;          // in wei
    uint8 internal _percetageFee;     /// NOT SET 
    uint256 internal _accumulatedFee; // in ERC20 tokens
    constructor(
        uint8 decimals,
        string memory name,
        string memory symbol,
        uint256 initialSupply,
        uint256 price
    ) {
        _token = new ERC20(decimals, name, symbol, initialSupply);
        _price = price * 1 ether;
        uint256 supply = initialSupply * 10 ** decimals;
        _token.mint(address(this), supply);
    }

}
