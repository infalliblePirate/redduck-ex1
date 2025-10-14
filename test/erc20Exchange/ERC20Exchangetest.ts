import { expect } from "chai";
import hre from "hardhat";
import { ERC20Exchange__factory } from "../../typechain-types";
import { ERC20__factory } from "../../typechain-types";
import { ERC20ExchangeSetup } from "./types";

describe('ERC20Exchange test', () => {
    const FEE_DENOMINATOR: bigint = 10_000n;

    const name = 'Penguin';
    const symbol = 'PNGN';
    const decimals = 6;

    const expectedSupply = hre.ethers.parseUnits("1000", decimals);
    const expectedPrice = hre.ethers.parseEther("0.000001");
    const expectedAddedLiquidityEth = hre.ethers.parseEther("1");
    const expectedFeeBasisPoints: bigint = 10n;
    
    const tradeAmount = hre.ethers.parseEther("0.000001");
    const insufficientEthAmount = hre.ethers.parseUnits("0.1", decimals);
    const excessiveTradeEthAmount = expectedSupply * expectedPrice + 1n;

    const setup = async (): Promise<ERC20ExchangeSetup> => {
        const [deployer, user] = await hre.ethers.getSigners();

        const token = await new ERC20__factory(deployer)
            .deploy(decimals, name, symbol);

        const exchange = await new ERC20Exchange__factory(deployer).deploy(
            token, expectedPrice, expectedFeeBasisPoints);

        await token.setMinter(exchange);
        await exchange.addLiquidity(expectedSupply, { value: expectedAddedLiquidityEth });

        return {
            deployer,
            user,
            exchange,
            token
        };
    };

    describe('Initialize', () => {
        it('should confirm inital state of program', async () => {
            const { exchange, token } = await setup();
            expect(await exchange.price()).to.eq(expectedPrice);
            expect(await exchange.token()).to.eq(token);
        });
    });

    describe('Add liquidity', () => {
        it('should revert', async () => {
            const { user, exchange } = await setup();

            await expect(exchange.connect(user).addLiquidity(0, { value: expectedAddedLiquidityEth }))
                .to.be.reverted;

            await expect(exchange.addLiquidity(0, { value: expectedAddedLiquidityEth }))
                .to.be.revertedWith("The inital supply must be a positive number");

            await expect(exchange.addLiquidity(expectedSupply, { value: 0 }))
                .to.be.revertedWith("The ether reserve must be a positive number");
        });

        it('should update liquidity, balances, emit LiquidityChanged', async () => {
            const { deployer, exchange } = await setup();

            const deployerEthBefore = await hre.ethers.provider.getBalance(deployer);
            const [exchangeLiquidityEthBefore, exchangeLiquidityTokenBefore] = await exchange.liquidity();

            const tx = await exchange.addLiquidity(expectedSupply, { value: expectedAddedLiquidityEth });
            await expect(tx)
                .to.emit(exchange, 'LiquidityChanged')
                .withArgs(deployer, expectedAddedLiquidityEth, expectedSupply);

            const receipt = (await tx.wait())!;
            const gasCost = receipt.gasUsed * tx.gasPrice;

            const deployerEthAfter = await hre.ethers.provider.getBalance(deployer);
            const [exchangeLiquidityEthAfter, exchangeLiquidityTokenAfter] = await exchange.liquidity();

            expect(deployerEthBefore - deployerEthAfter)
                .to.be.closeTo(expectedAddedLiquidityEth + gasCost, 1e12);
            expect(exchangeLiquidityEthAfter - exchangeLiquidityEthBefore)
                .to.eq(expectedAddedLiquidityEth);

            expect(exchangeLiquidityTokenAfter - exchangeLiquidityTokenBefore)
                .to.eq(expectedSupply);
        });
    });

    describe('Buy', () => {
        it('should update liquidity, user\'s eth and token balance, return true, emit Buy event', async () => {
            const { user, exchange, token } = await setup();

            const userEthBefore = await hre.ethers.provider.getBalance(user);
            const [exchangeEthBefore, exchangeTokenBefore] = await exchange.liquidity();
            const userTokensBefore = await token.balanceOf(user);

            expect(await exchange.getFunction('buy').staticCall({value: expectedPrice}))
                .to.eq(true);

            const tx = await exchange.connect(user).buy({ value: expectedPrice });
            const receipt = (await tx.wait())!;

            const gasUsed = receipt.gasUsed;
            const gasPrice = tx.gasPrice;
            const gasCost = gasUsed * gasPrice;

            const userEthAfter = await hre.ethers.provider.getBalance(user);
            const [exchangeEthAfter, exchangeTokenAfter] = await exchange.liquidity();
            const userTokenAfter = await token.balanceOf(user);

            expect(userEthBefore - expectedPrice).to.be.closeTo(userEthAfter + gasCost, 12n);
            expect(exchangeEthAfter - expectedPrice).to.eq(exchangeEthBefore);

            const tokens = tradeAmount * 10n ** await token.decimals() / expectedPrice;
            const fee = tokens * expectedFeeBasisPoints / FEE_DENOMINATOR;
            const tokensAfterFee = tokens - fee;

            expect(userTokenAfter).to.eq(userTokensBefore + tokensAfterFee);
            expect(await exchange.accumulatedFee()).to.eq(fee);
            expect(exchangeTokenBefore - exchangeTokenAfter).to.eq(tokensAfterFee);

            await expect(tx).to.emit(exchange, 'Buy')
                .withArgs(user, tokensAfterFee, tradeAmount, fee);
        });
        it('should revert', async () => {
            const { user, exchange } = await setup();
            await expect(exchange.connect(user).buy({ value: insufficientEthAmount }))
                .to.be.revertedWith("No sufficient funds to buy token");

            await expect(exchange.connect(user).buy({ value: excessiveTradeEthAmount }))
                .to.be.revertedWith("The number of requested tokens exceeds liquidity pool");
        });
    });
});