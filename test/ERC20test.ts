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

    describe('Approve', () => {
        it('should revert upon approving zero addresses', async () => {
            const { user, token } = await setup();
            const zeroSigner = await hre.ethers.getSigner(hre.ethers.ZeroAddress);

            await expect(token.connect(zeroSigner).getFunction('approve')
                .staticCall(user, hre.ethers.parseEther("0.000001"))).to.be.revertedWith("The sender is a zero address");

            await expect(
                token.approve(hre.ethers.ZeroAddress, hre.ethers.parseEther("0.000001"))
            ).to.be.revertedWith("The receipient is a zero address");
        })

        it('should return true and update allowance', async () => {
            const { deployer, user, token } = await setup();
            const amount = hre.ethers.parseEther("0.000001");

            const result = await token.getFunction('approve')
                .staticCall(user, amount);
            expect(result).to.eq(true);

            const tx = await token.approve(user, amount);
            await tx.wait();

            expect(await token.allowance(deployer, user)).to.eq(amount);
        });
    });


});