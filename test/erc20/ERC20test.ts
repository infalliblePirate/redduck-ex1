import { expect } from 'chai';
import hre from 'hardhat';

import { ERC20Setup } from './types';

import { ERC20__factory } from '../../typechain-types';

describe('ERC20 test', () => {
  const expectedName = 'Penguin';
  const expectedSymbol = 'PNGN';
  const expectedDecimals = 6;
  const expectedSupply = hre.ethers.parseUnits('1000', expectedDecimals);
  const expectedApprovedBalance = hre.ethers.parseUnits('1', expectedDecimals);

  const setup = async (): Promise<ERC20Setup> => {
    const [deployer, user] = await hre.ethers.getSigners();
    const erc20 = await new ERC20__factory(deployer).deploy(
      expectedDecimals,
      expectedName,
      expectedSymbol,
    );

    await erc20.setMinter(deployer);
    await erc20.mint(deployer, expectedSupply);

    return {
      deployer: deployer,
      user: user,
      token: erc20,
    };
  };

  describe('Initialize', () => {
    it('should confirm initial state of program', async () => {
      const initialState = await setup();
      const token = initialState.token;

      const [name, symbol, decimals, totalSupply, deployerBalance] =
        await Promise.all([
          token.name(),
          token.symbol(),
          token.decimals(),
          token.totalSupply(),
          token.balanceOf(initialState.deployer),
        ]);

      expect(name).to.eq(expectedName);
      expect(symbol).to.eq(expectedSymbol);
      expect(decimals).to.eq(expectedDecimals);
      expect(totalSupply).to.eq(expectedSupply);
      expect(deployerBalance).to.eq(expectedSupply);
    });
  });

  describe('Approve', () => {
    it('should return true, update allowance emit Approval event', async () => {
      const { deployer, user, token } = await setup();

      const result = await token
        .getFunction('approve')
        .staticCall(user, expectedApprovedBalance);
      expect(result).to.eq(true);

      await expect(token.approve(user, expectedApprovedBalance))
        .emit(token, 'Approval')
        .withArgs(deployer, user, expectedApprovedBalance);

      expect(await token.allowance(deployer, user)).to.eq(
        expectedApprovedBalance,
      );
    });
  });

  describe('Transfer', () => {
    it('should revert', async () => {
      const { deployer, user, token } = await setup();

      await expect(
        token.connect(user).transfer(deployer, expectedApprovedBalance),
      ).to.be.revertedWith('The transferable value exceeds balance');
    });

    it("should return true, update user's balances and emit Transfer event", async () => {
      const { deployer, user, token } = await setup();

      expect(
        await token
          .getFunction('transfer')
          .staticCall(user, expectedApprovedBalance),
      ).to.eq(true);

      await expect(token.transfer(user, expectedApprovedBalance))
        .emit(token, 'Transfer')
        .withArgs(deployer, user, expectedApprovedBalance);

      const senderBalance = await token.balanceOf(deployer);
      const recipientBalance = await token.balanceOf(user);

      expect(senderBalance).to.eq(expectedSupply - expectedApprovedBalance);
      expect(recipientBalance).to.eq(expectedApprovedBalance);
    });
  });

  describe('TransferFrom', () => {
    it('should revert', async () => {
      const { deployer, user, token } = await setup();
      await expect(
        token.transferFrom(deployer, user, expectedApprovedBalance),
      ).to.be.rejectedWith('The transferable value exceeds allowance');
    });

    it("should return true, update user's balances, allowances and emit Transfer, Approval events", async () => {
      const { deployer, user, token } = await setup();
      await expect(token.approve(user, expectedApprovedBalance))
        .emit(token, 'Approval')
        .withArgs(deployer, user, expectedApprovedBalance);

      expect(
        await token
          .connect(user)
          .getFunction('transferFrom')
          .staticCall(deployer, user, expectedApprovedBalance),
      ).to.eq(true);

      await expect(
        token
          .connect(user)
          .transferFrom(deployer, user, expectedApprovedBalance),
      )
        .emit(token, 'Approval')
        .withArgs(deployer, user, 0)
        .emit(token, 'Transfer')
        .withArgs(deployer, user, expectedApprovedBalance);

      expect(await token.allowance(deployer, user)).to.eq(0);
      expect(await token.balanceOf(deployer)).to.eq(
        expectedSupply - expectedApprovedBalance,
      );
      expect(await token.balanceOf(user)).to.eq(expectedApprovedBalance);
    });
  });

  describe('Mint', () => {
    it('should revert', async () => {
      const { deployer, user, token } = await setup();

      await expect(
        token.mint(hre.ethers.ZeroAddress, expectedSupply),
      ).to.be.revertedWith('The recipient is a zero address');

      await expect(token.connect(user).mint(deployer, expectedSupply)).to.be
        .reverted;
      await expect(token.mint(deployer, 0)).to.be.revertedWith(
        'Mint amount must be greater than 0',
      );
    });
    it('should mint tokens, update supply, emit Transfer event', async () => {
      const { user, token } = await setup();

      const userBalanceBefore = await token.balanceOf(user);
      const supplyBefore = await token.totalSupply();

      await expect(token.mint(user, expectedSupply))
        .to.emit(token, 'Transfer')
        .withArgs(hre.ethers.ZeroAddress, user, expectedSupply);

      const userBalanceAfter = await token.balanceOf(user);
      const supplyAfter = await token.totalSupply();

      expect(userBalanceAfter - userBalanceBefore).to.eq(expectedSupply);
      expect(supplyAfter - supplyBefore).to.eq(expectedSupply);
    });
  });

  describe('Burn', () => {
    it('should revert', async () => {
      const { token } = await setup();

      await expect(token.burn(0)).to.be.revertedWith(
        'Burn amount must be greater than 0',
      );

      const exceededSupply = expectedSupply * 2n;
      await expect(token.burn(exceededSupply)).to.be.revertedWith(
        'The burn amount exceeds balance',
      );
    });

    it('should burn tokens, update supply, emit Transfer event', async () => {
      const { deployer, token } = await setup();

      const deployerBalanceBefore = await token.balanceOf(deployer);
      const supplyBefore = await token.totalSupply();

      await expect(token.burn(expectedSupply))
        .to.emit(token, 'Transfer')
        .withArgs(deployer, hre.ethers.ZeroAddress, expectedSupply);

      const deployerBalanceAfter = await token.balanceOf(deployer);
      const supplyAfter = await token.totalSupply();

      expect(deployerBalanceBefore - deployerBalanceAfter).to.eq(
        expectedSupply,
      );
      expect(supplyBefore - supplyAfter).to.eq(expectedSupply);
    });
  });
});
