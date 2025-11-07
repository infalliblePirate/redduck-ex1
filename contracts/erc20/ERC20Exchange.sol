// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IExchangable.sol";
import "../erc20/ERC20.sol";

/**
 * @title ERC20Exchange
 * @notice Decentralized exchange for swapping ETH and ERC20 tokens
 * @author Kateryna Pavlenko
 */
contract ERC20Exchange is IExchangable, Ownable {
    /// @notice The ERC20 token being traded on this exchange
    /// @dev Immutable after deployment for security
    ERC20 internal immutable _TOKEN;

    /// @notice Current price of one token in wei (considering token decimals)
    uint256 internal _price;

    /// @notice Trading fee in basis points (1 bp = 0.01%)
    uint8 internal _feeBasisPoints;

    /// @notice Total fees collected but not yet burned
    /// @dev Fees are accumulated in tokens, not ETH
    uint256 internal _accumulatedFee;

    /// @notice Denominator for basis point calculations
    /// @dev 10,000 basis points = 100%
    uint16 private constant FEE_DENOMINATOR = 10_000;

    /// @notice Timestamp of the last fee burn
    /// @dev Used to enforce the 7-day burn interval
    uint256 public lastBurnTimestamp;

    /// @notice Minimum time between fee burns
    uint256 constant BURN_INTERVAL = 7 days;

    /**
     * @notice Creates a new exchange for a specific ERC20 token
     * @param erc20 Address of the ERC20 token contract
     * @param price_ Initial price per token in wei
     * @param feeBasisPoints_ Trading fee in basis points (e.g., 100 = 1%)
     */
    constructor(
        address erc20,
        uint256 price_,
        uint8 feeBasisPoints_
    ) Ownable(msg.sender) {
        require(erc20 != address(0), "The token is a zero address");
        require(price_ > 0, "The price must be a positive number");
        require(
            feeBasisPoints_ >= 0 && feeBasisPoints_ < FEE_DENOMINATOR,
            "The fee is out of range"
        );
        _TOKEN = ERC20(erc20);
        _price = price_;
        _feeBasisPoints = feeBasisPoints_;
        lastBurnTimestamp = block.timestamp;
    }

    /// @inheritdoc IExchangable
    function addLiquidity(
        uint256 tokenAmount
    ) external payable override onlyOwner {
        require(tokenAmount > 0, "The inital supply must be a positive number");
        uint256 value = msg.value;
        require(value > 0, "The ether reserve must be a positive number");

        uint256 supply = tokenAmount;
        _TOKEN.mint(address(this), supply);

        emit LiquidityChanged(msg.sender, value, tokenAmount);
    }

    /// @inheritdoc IExchangable
    function price() external view override returns (uint256) {
        return _price;
    }

    /**
     * @notice Returns the address of the token being traded
     * @return tokenAddress Address of the ERC20 token contract
     */
    function token() external view returns (address) {
        return address(_TOKEN);
    }

    /// @inheritdoc IExchangable
    function setPrice(
        uint256 price_
    ) external override onlyOwner returns (bool) {
        _price = price_;
        return true;
    }

    /**
     * @notice Internal function to update the token price
     * @dev Can be called by owner or derived contracts (e.g., voting mechanism)
     * @param price_ New price per token in wei
     * @return success Always returns true
     */
    function _setPrice(uint256 price_) internal onlyOwner returns (bool) {
        _price = price_;
        return true;
    }

    /// @inheritdoc IExchangable
    function buy() external payable virtual override returns (bool) {
        return _buy(msg.value);
    }

    /**
     * @notice Internal function to process token purchases
     * @dev Calculates tokens to mint, deducts fees, and transfers to buyer
     * @param value Amount of ETH sent for the purchase
     * @return success True if purchase was successful
     */
    function _buy(uint256 value) internal returns (bool) {
        uint256 tokens = (value * 10 ** _TOKEN.decimals()) / _price;
        uint256 fee = (tokens * _feeBasisPoints) / FEE_DENOMINATOR;
        _accumulatedFee += fee;

        uint256 tokensAfterFee = tokens - fee;
        require(tokensAfterFee > 0, "No sufficient funds to buy token");
        require(
            _TOKEN.balanceOf(address(this)) >= tokensAfterFee + _accumulatedFee,
            "The number of requested tokens exceeds liquidity pool"
        );
        require(
            _TOKEN.transfer(msg.sender, tokensAfterFee),
            "Transfering failed"
        );

        emit Buy(msg.sender, tokensAfterFee, value, fee);
        return true;
    }

    /// @inheritdoc IExchangable
    function sell(uint256 value) external virtual override returns (bool) {
        return _sell(value);
    }

    /**
     * @notice Internal function to process token sales
     * @dev Calculates ETH to send, deducts fees, and transfers to seller
     * @dev Requires prior token approval from seller
     * @param value Amount of tokens to sell
     * @return success True if sale was successful
     */
    function _sell(uint256 value) internal returns (bool) {
        require(
            _TOKEN.balanceOf(msg.sender) >= value,
            "The account does not that many tokens"
        );
        uint256 fee = (value * _feeBasisPoints) / FEE_DENOMINATOR;
        uint256 soldTokens = value - fee;
        uint256 ethToSend = (soldTokens * _price) / (10 ** _TOKEN.decimals());
        _accumulatedFee += fee;
        require(
            ethToSend <= payable(address(this)).balance,
            "The exchange does not have enough eth liquidity"
        );
        require(
            _TOKEN.transferFrom(msg.sender, address(this), value),
            "Transfering failed"
        );
        payable(msg.sender).transfer(ethToSend);

        emit Sell(msg.sender, soldTokens, ethToSend, fee);
        return true;
    }

    /// @inheritdoc IExchangable
    function liquidity() external view override returns (uint256, uint256) {
        return (
            payable(address(this)).balance,
            _TOKEN.balanceOf(address(this))
        );
    }

    /// @inheritdoc IExchangable
    function feeBasisPoints() external view override onlyOwner returns (uint8) {
        return _feeBasisPoints;
    }

    /// @inheritdoc IExchangable
    function setFeeBasisPoints(
        uint8 feeBP
    ) external override onlyOwner returns (bool) {
        _feeBasisPoints = feeBP;
        return true;
    }

    /// @inheritdoc IExchangable
    function accumulatedFee()
        external
        view
        override
        onlyOwner
        returns (uint256)
    {
        return _accumulatedFee;
    }

    /// @inheritdoc IExchangable
    function resetLiquidity(
        address to
    ) external override onlyOwner returns (bool) {
        require(
            _TOKEN.transfer(to, _TOKEN.balanceOf(address(this))),
            "Transfering failed"
        );
        payable(to).transfer(payable(address(this)).balance);
        return true;
    }

    /// @inheritdoc IExchangable
    function weeklyBurnFee() external override onlyOwner returns (bool) {
        require(
            block.timestamp >= lastBurnTimestamp + BURN_INTERVAL,
            "Burn not available yet"
        );
        lastBurnTimestamp = block.timestamp;
        uint256 fee = _accumulatedFee;
        _accumulatedFee = 0;
        _TOKEN.burn(address(this), fee);
        emit WeeklyBurn(msg.sender, fee, block.timestamp);
        return true;
    }
}
