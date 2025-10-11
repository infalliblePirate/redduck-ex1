import { expect } from 'chai';
import { ERC20__factory } from '../typechain-types';

import hre from 'hardhat';
import { ERC20Setup } from './types';

describe('ERC20 test', () => {
    const expectedName = 'Penguin';
    const expectedSymbol = 'PNGN';
    const expectedDecimals = 6;
    const expectedSupply = hre.ethers.parseUnits("1000", expectedDecimals);
    const expectedApprovedBalance = hre.ethers.parseUnits("1", expectedDecimals);

    const setup = async (): Promise<ERC20Setup> => {
        const [deployer, user] = await hre.ethers.getSigners();
        const erc20 = await new ERC20__factory(deployer).deploy(
            expectedDecimals, expectedName, expectedSymbol);

        await erc20.setMinter(deployer);
        await erc20.mint(deployer, expectedSupply);

        return {
            deployer: deployer,
            user: user,
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
                .staticCall(user, expectedApprovedBalance)).to.be.revertedWith("The sender is a zero address");

            await expect(
                token.approve(hre.ethers.ZeroAddress, expectedApprovedBalance)
            ).to.be.revertedWith("The receipient is a zero address");
        });

        it('should return true, update allowance emit Approval event', async () => {
            const { deployer, user, token } = await setup();

            const result = await token.getFunction('approve')
                .staticCall(user, expectedApprovedBalance);
            expect(result).to.eq(true);

            await expect(token.approve(user, expectedApprovedBalance))
                .emit(token, 'Approval')
                .withArgs(deployer, user, expectedApprovedBalance);

            expect(await token.allowance(deployer, user)).to.eq(expectedApprovedBalance);
        });
    });

    describe('Transfer', () => {
        it('should revert', async () => {
            const { deployer, user, token } = await setup();
            const zeroSigner = await hre.ethers.getSigner(hre.ethers.ZeroAddress);

            await expect(token.connect(zeroSigner).getFunction('transfer')
                .staticCall(user, expectedApprovedBalance)).to.be.revertedWith("The sender is a zero address");

            await expect(
                token.transfer(hre.ethers.ZeroAddress, expectedApprovedBalance)
            ).to.be.revertedWith("The receipient is a zero address");

            await expect(token.connect(user).transfer(deployer, expectedApprovedBalance)
            ).to.be.revertedWith("The transferable value exceeds balance");
        });

        it('should return true, update user\'s balances and emit Transfer event', async () => {
            const { deployer, user, token } = await setup();

            expect(await token.getFunction('transfer')
                .staticCall(user, expectedApprovedBalance)).to.eq(true);

            await expect(token.transfer(user, expectedApprovedBalance)).emit(token, 'Transfer')
                .withArgs(deployer, user, expectedApprovedBalance);

            const senderBalance = await token.balanceOf(deployer);
            const receipientBalance = await token.balanceOf(user);

            expect(senderBalance).to.eq(expectedSupply - expectedApprovedBalance);
            expect(receipientBalance).to.eq(expectedApprovedBalance);
        });
    });

    describe('TransferFrom', () => {
        it('should revert', async () => {
            const { deployer, user, token } = await setup();
            await expect(token.transferFrom(deployer, user, expectedApprovedBalance))
                .to.be.rejectedWith('The transferable value exceeds allowance');
        });

        it('should return true, update user\'s balances, allowances and emit Transfer, Approval events', async () => {
            const { deployer, user, token } = await setup();
            await expect(token.approve(user, expectedApprovedBalance)).emit(token, 'Approval')
                .withArgs(deployer, user, expectedApprovedBalance);

            expect(await token.connect(user).getFunction('transferFrom')
                .staticCall(deployer, user, expectedApprovedBalance,)).to.eq(true);

            await expect(token.connect(user).transferFrom(deployer, user, expectedApprovedBalance))
                .emit(token, 'Approval')
                .withArgs(deployer, user, 0)
                .emit(token, 'Transfer')
                .withArgs(deployer, user, expectedApprovedBalance);

            expect(await token.allowance(deployer, user)).to.eq(0);
            expect(await token.balanceOf(deployer)).to.eq(expectedSupply - expectedApprovedBalance);
            expect(await token.balanceOf(user)).to.eq(expectedApprovedBalance);
        });
    });
});