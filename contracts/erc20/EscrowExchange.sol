// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/access/Ownable.sol";

import "../interfaces/IEscrowable.sol";
import "../interfaces/IExchangable.sol";

contract EscrowExchange is IEscrowable, IExchangable, Ownable {
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

    mapping(address => uint256) private _balances;

    constructor(
        address erc20,
        uint256 price_,
        uint8 feeBasisPoints_
    ) Ownable(msg.sender) {
        require(erc20 != address(0), "Invalid token");
        _price = price_;
        _feeBasisPoints = feeBasisPoints_;
        lastBurnTimestamp = block.timestamp;
        _TOKEN = ERC20(erc20);
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

    function transfer(address to, uint256 amount) public override {
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

    function buy() external payable override returns (bool) {
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
            _balances[address(this)] >= tokensAfterFee + _accumulatedFee,
            "The number of requested tokens exceeds liquidity pool"
        );
        _balances[address(this)] -= tokensAfterFee;
        _balances[msg.sender] += tokensAfterFee;

        emit Buy(msg.sender, tokensAfterFee, value, fee);
        return true;
    }

    function sell(uint256 value) external override returns (bool) {
        return _sell(value);
    }

    function _sell(uint256 value) internal returns (bool) {
        require(
            _balances[msg.sender] >= value,
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

        _balances[msg.sender] -= value;
        _balances[address(this)] += value;
        payable(msg.sender).transfer(ethToSend);

        emit Sell(msg.sender, soldTokens, ethToSend, fee);
        return true;
    }

    function addLiquidity(
        uint256 tokenSupply
    ) external payable override onlyOwner {
        require(tokenSupply > 0, "The inital supply must be a positive number");
        uint256 value = msg.value;
        require(value > 0, "The ether reserve must be a positive number");

        _TOKEN.transferFrom(msg.sender, address(this), tokenSupply);
        _balances[address(this)] += tokenSupply;
    }

    function liquidity() external view override returns (uint256, uint256) {
        return (_balances[address(this)], address(this).balance);
    }

    function price() external view override returns (uint256) {
        return _price;
    }

    function setPrice(
        uint256 newPrice
    ) external override onlyOwner returns (bool) {
        require(newPrice > 0, "Price must be positive");
        _price = newPrice;
        return true;
    }

    function feeBasisPoints() external view override returns (uint8) {
        return _feeBasisPoints;
    }

    function setFeeBasisPoints(
        uint8 feeBps
    ) external override onlyOwner returns (bool) {
        _feeBasisPoints = feeBps;
        return true;
    }

    function accumulatedFee() external view override returns (uint256) {
        return _accumulatedFee;
    }

    function resetLiquidity(
        address to
    ) external override onlyOwner returns (bool) {
        require(to != address(0), "Invalid recepient address");
        _balances[to] += _balances[address(this)];
        _balances[address(this)] = 0;
        payable(to).transfer(payable(address(this)).balance);
        return true;
    }

    function weeklyBurnFee() external override returns (bool) {
        require(
            block.timestamp >= lastBurnTimestamp + BURN_INTERVAL,
            "Burn not available yet"
        );
        lastBurnTimestamp = block.timestamp;
        require(
            _balances[address(this)] >= _accumulatedFee,
            "Not enough liquidity to burn fee"
        );
        _balances[address(this)] -= _accumulatedFee;
        _TOKEN.burn(address(this), _accumulatedFee);

        emit WeeklyBurn(msg.sender, _accumulatedFee, block.timestamp);
        _accumulatedFee = 0;

        return true;
    }
}
