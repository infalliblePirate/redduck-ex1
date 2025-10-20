// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

/**
 * @title IExchangable
 * @notice Interface for an exchange that uses ETH-to-ERC20 token swaps
 * @dev Implements basic exchange functionality with configurable fees and liquidity management
 * @author Kateryna Pavlenko
 */
interface IExchangable {
    /**
     * @notice Emitted when a user buys tokens with ETH
     * @param buyer Address of the token buyer
     * @param tokensBought Amount of tokens purchased (after fees)
     * @param spentEth Amount of ETH spent on the purchase
     * @param feeInTokens Fee charged in tokens
     */
    event Buy(
        address indexed buyer,
        uint256 tokensBought,
        uint256 spentEth,
        uint256 feeInTokens
    );

    /**
     * @notice Emitted when a user sells tokens for ETH
     * @param seller Address of the token seller
     * @param tokensSold Amount of tokens sold (after fees)
     * @param sentEth Amount of ETH received from the sale
     * @param feeInTokens Fee charged in tokens
     */
    event Sell(
        address indexed seller,
        uint256 tokensSold,
        uint256 sentEth,
        uint256 feeInTokens
    );

    /**
     * @notice Emitted when liquidity is added to the exchange
     * @param initiator Address that initiated the liquidity addition
     * @param ethAmount Amount of ETH added to the pool
     * @param tokenAmount Amount of tokens added to the pool
     */
    event LiquidityChanged(
        address indexed initiator,
        uint256 ethAmount,
        uint256 tokenAmount
    );

    /**
     * @notice Emitted when accumulated fees are burned
     * @param sender Address that triggered the burn
     * @param burnAmount Amount of tokens burned
     * @param timestamp Block timestamp when the burn occurred
     */
    event WeeklyBurn(
        address indexed sender,
        uint256 burnAmount,
        uint256 timestamp
    );

    /**
     * @notice Buy tokens with ETH at the current exchange price
     * @dev Calculates tokens based on msg.value and current price, deducts fees
     * @return success True if the purchase was successful
     */
    function buy() external payable returns (bool);

    /**
     * @notice Sell tokens for ETH at the current exchange price
     * @dev Requires prior token approval. Transfers tokens from sender and sends ETH back
     * @param value Amount of tokens to sell
     * @return success True if the sale was successful
     */
    function sell(uint256 value) external returns (bool);

    /**
     * @notice Add liquidity to the exchange pool
     * @dev Only callable by owner. Mints tokens and accepts ETH to create initial liquidity
     * @param tokenSupply Amount of tokens to mint and add to the pool
     */
    function addLiquidity(uint256 tokenSupply) external payable;

    /**
     * @notice Get current liquidity reserves
     * @return ethReserve Amount of ETH in the pool
     * @return tokenReserve Amount of tokens in the pool
     */
    function liquidity() external view returns (uint256, uint256);

    /**
     * @notice Get the current token price in wei per token
     * @return currentPrice Price of one token in wei (considering decimals)
     */
    function price() external view returns (uint256);

    /**
     * @notice Set a new token price
     * @dev Only callable by owner
     * @param newPrice New price in wei per token
     * @return success True if the price was updated successfully
     */
    function setPrice(uint256 newPrice) external returns (bool);

    /**
     * @notice Get the current fee in basis points (1 basis point = 0.01%)
     * @dev Only callable by owner
     * @return feeBps Fee charged on trades in basis points (e.g., 100 = 1%)
     */
    function feeBasisPoints() external view returns (uint8);

    /**
     * @notice Set a new trading fee
     * @dev Only callable by owner. Fee must be less than 10,000 basis points (100%)
     * @param feeBps New fee in basis points
     * @return success True if the fee was updated successfully
     */
    function setFeeBasisPoints(uint8 feeBps) external returns (bool);

    /**
     * @notice Get the total accumulated fees
     * @dev Only callable by owner
     * @return totalFees Total fees collected and not yet burned
     */
    function accumulatedFee() external returns (uint256);

    /**
     * @notice Withdraw all liquidity from the exchange
     * @dev Only callable by owner. Transfers all tokens and ETH to specified address
     * @param to Address to receive the withdrawn liquidity
     * @return success True if the withdrawal was successful
     */
    function resetLiquidity(address to) external returns (bool);

    /**
     * @notice Burn accumulated fees
     * @dev Only callable by owner. Can only be called once per week
     * @return success True if the burn was successful
     */
    function weeklyBurnFee() external returns (bool);
}
