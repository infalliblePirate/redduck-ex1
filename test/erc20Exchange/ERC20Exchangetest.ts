import { expect } from "chai";
import hre from "hardhat";
import { ERC20Exchange__factory } from "../../typechain-types";
import { ERC20__factory } from "../../typechain-types";
import { ERC20ExchangeSetup } from "./types";

describe('ERC20Exchange test', () => {
    const name = 'Penguin';
    const symbol = 'PNGN';
    const decimals = 6;
    const expectedSupply = hre.ethers.parseUnits("1000", decimals);
    const expectedPrice = hre.ethers.parseEther("0.000001");
    const expectedAddedLiquidity = hre.ethers.parseEther("1");

    const setup = async (): Promise<ERC20ExchangeSetup> => {
        const [deployer, user] = await hre.ethers.getSigners();

        const token = await new ERC20__factory(deployer)
            .deploy(decimals, name, symbol);

        const exchange = await new ERC20Exchange__factory(deployer).deploy(
            token, expectedPrice);

        await token.setMinter(exchange);
        await exchange.addLiquidity(expectedSupply, { value: expectedAddedLiquidity });

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
});