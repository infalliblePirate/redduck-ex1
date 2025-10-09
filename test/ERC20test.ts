import { expect } from 'chai';
import { ERC20__factory } from '../typechain-types';

import hre from 'hardhat';
import { ERC20Setup } from './types';

describe('ERC20 test', () => {
    const expectedName = 'Penguin';
    const expectedSymbol = 'PNGN';
    const expectedDecimals = 6;
    const expectedSupply = hre.ethers.parseUnits("1000", expectedDecimals)

    const setup = async (): Promise<ERC20Setup> => {
        const [deployer, user] = await hre.ethers.getSigners();
        const erc20 = await new ERC20__factory(deployer).deploy(
            expectedDecimals, expectedName, expectedSymbol);

        await erc20.setMinter(deployer);
        await erc20.mint(deployer, expectedSupply);

        return {
            deployer: deployer.address,
            user: user.address,
            token: erc20,
        }
    };

    describe('Initialize', () => {
        it('should confirm initial state of program', async () => {
            const initialState = await setup();
            const token = initialState.token;

            const [name, symbol, decimals, totalSupply, deployerBalance] = await Promise.all([
                token.name(),
                token.symbol(),
                token.decimals(),
                token.totalSupply(),
                token.balanceOf(initialState.deployer)
            ]);

            expect(name).to.eq(expectedName);
            expect(symbol).to.eq(expectedSymbol);
            expect(decimals).to.eq(expectedDecimals);
            expect(totalSupply).to.eq(expectedSupply);
            expect(deployerBalance).to.eq(expectedSupply);
        });
    });

});