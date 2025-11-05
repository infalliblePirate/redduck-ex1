import { time } from '@nomicfoundation/hardhat-network-helpers';
import { loadFixture } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { Signer } from 'ethers';
import hre from 'hardhat';

import { ERC20VotingExchangeSetup } from './types';

import {
  ERC20__factory,
  ERC20VotingExchange__factory,
  ERC20VotingExchange,
} from '../../typechain-types';

describe('ERC20VotingExchange test', () => {
  const TIME_TO_VOTE = 1n * 24n * 60n * 60n; // 1 day
  const VOTE_THRESHOLD_BPS = 5n;
  const BPS_DENOMINATOR = 10000n;

  const FEE_DENOMINATOR: bigint = 10_000n;

  const name = 'Penguin';
  const symbol = 'PNGN';
  const decimals = 6n;

  const supply = hre.ethers.parseUnits('1000', decimals);
  const price = hre.ethers.parseEther('0.000001');
  const liquidityEth = hre.ethers.parseEther('10');
  const feeBp = 10n;

  const tradeEthAmount = hre.ethers.parseEther('0.000001');
  const newSuggestedPrice = hre.ethers.parseEther('0.000002');
  const tokensToVote = (supply * VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;

  // 1% to acount for the fee
  const bufferMultiplier = 101n;
  const bufferDenominator = 100n;

  const ethToVote =
    (tokensToVote * price * bufferMultiplier) /
    (10n ** decimals * bufferDenominator);

  const deploySetupFixture = async (): Promise<ERC20VotingExchangeSetup> => {
    const [deployer, voter1, voter2] = await hre.ethers.getSigners();

    const token = await new ERC20__factory(deployer).deploy(
      decimals,
      name,
      symbol,
    );

    const votingExchange = await new ERC20VotingExchange__factory(
      deployer,
    ).deploy(token, price, feeBp);

    await token.setMinter(votingExchange);
    await votingExchange.addLiquidity(supply, {
      value: liquidityEth,
    });

    return {
      deployer,
      voter1,
      voter2,
      votingExchange,
      token,
    };
  };

  const buyTokens = async (
    votingExchange: ERC20VotingExchange,
    user: Signer,
    amount: bigint,
  ): Promise<bigint> => {
    const tx = await votingExchange.connect(user).buy({ value: amount });
    const receipt = (await tx.wait())!;

    const eventTopic = votingExchange.interface.getEvent('Buy').topicHash;
    const buyLog = receipt.logs.find((log) => log.topics[0] === eventTopic)!;

    const parsed = votingExchange.interface.parseLog(buyLog)!;
    const tokensBought = parsed.args.tokensBought;

    const fee = (tokensBought * feeBp) / FEE_DENOMINATOR;
    const tokensBoughtAfterFee = tokensBought - fee;

    return tokensBoughtAfterFee;
  };

  describe('Restrictions during voting', () => {
    it('should emit appropriate events in buy/sell/transfer after user voted', async () => {
      const { votingExchange, deployer, voter1, token } =
        await loadFixture(deploySetupFixture);

      await votingExchange.connect(deployer).startVoting();
      await buyTokens(votingExchange, deployer, ethToVote);
      const balance = await token.balanceOf(deployer);

      await token.approve(votingExchange, balance);
      await votingExchange.connect(deployer).vote(newSuggestedPrice, balance);

      await expect(
        votingExchange.connect(deployer).buy({ value: tradeEthAmount }),
      ).to.emit(votingExchange, 'Buy');

      await expect(
        token
          .connect(deployer)
          .transfer(voter1, await token.balanceOf(deployer)),
      ).to.emit(token, 'Transfer');

      const tokensToVote = await buyTokens(votingExchange, voter1, ethToVote);
      await token.connect(voter1).approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(voter1)
        .vote(newSuggestedPrice, tokensToVote);

      const userTokens = await token.balanceOf(voter1);
      await token.connect(voter1).approve(votingExchange, userTokens);
      await expect(votingExchange.connect(voter1).sell(userTokens)).to.emit(
        votingExchange,
        'Sell',
      );
    });
  });

  describe('Start voting', () => {
    it('should start a new round and emit StartVoting', async () => {
      const { votingExchange, deployer } =
        await loadFixture(deploySetupFixture);

      await expect(votingExchange.connect(deployer).startVoting()).to.emit(
        votingExchange,
        'StartVoting',
      );

      expect(await votingExchange.currentVotingNumber()).to.eq(1);
      expect(await votingExchange.votingStartedTimeStamp(1)).to.be.closeTo(
        await time.latest(),
        1,
      );
    });

    it('should revert if non-owner starts voting or already pending', async () => {
      const { votingExchange, voter1 } = await loadFixture(deploySetupFixture);
      await expect(votingExchange.connect(voter1).startVoting()).to.be.reverted;
      await votingExchange.startVoting();
      await expect(votingExchange.startVoting()).to.be.revertedWith(
        "The previous voting hasn't ended",
      );
    });
  });

  describe('Vote', () => {
    it('should revert if no active voting', async () => {
      const { votingExchange, deployer } =
        await loadFixture(deploySetupFixture);

      await expect(
        votingExchange.connect(deployer).vote(newSuggestedPrice, tokensToVote),
      ).to.be.revertedWith('No active voting');
    });

    it('should revert if user balance below threshold', async () => {
      const { votingExchange, voter1, token } =
        await loadFixture(deploySetupFixture);
      await votingExchange.startVoting();

      await token.connect(voter1).approve(votingExchange, tokensToVote);
      await expect(
        votingExchange.connect(voter1).vote(newSuggestedPrice, tokensToVote),
      ).to.be.revertedWith('Not enough tokens on balance');
    });

    it('should allow valid vote and update pending votes', async () => {
      const { votingExchange, deployer, voter1, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, 2n * ethToVote);
      await buyTokens(votingExchange, voter1, ethToVote);

      await votingExchange.startVoting();
      const votingNumber = await votingExchange.currentVotingNumber();

      const deployerBalance = await token.balanceOf(deployer);
      await token.connect(deployer).approve(votingExchange, deployerBalance);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, deployerBalance);

      const before = await votingExchange.pendingPriceVotes(
        votingNumber,
        newSuggestedPrice,
      );

      const voterBalance = await token.balanceOf(voter1);
      await token.connect(voter1).approve(votingExchange, voterBalance);
      const tx = await votingExchange
        .connect(voter1)
        .vote(newSuggestedPrice, voterBalance);
      await expect(tx)
        .to.emit(votingExchange, 'VoteCasted')
        .withArgs(voter1, votingNumber, newSuggestedPrice, voterBalance);

      const after = await votingExchange.pendingPriceVotes(
        votingNumber,
        newSuggestedPrice,
      );
      expect(after - before).to.equal(voterBalance);
    });

    it('should revert if user votes twice', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);
      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      const balance = await token.balanceOf(deployer);
      await token.connect(deployer).approve(votingExchange, balance);
      await votingExchange.connect(deployer).vote(newSuggestedPrice, balance);
      await expect(
        votingExchange.connect(deployer).vote(newSuggestedPrice, balance),
      ).to.be.revertedWith('User already voted');
    });

    it('should revert if voting time expired', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);
      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await time.increase(TIME_TO_VOTE + 1n);
      const balance = await token.balanceOf(deployer);
      await expect(
        votingExchange.connect(deployer).vote(newSuggestedPrice, balance),
      ).to.be.revertedWith('No active voting');
    });

    it('should revert if voting with zero tokens', async () => {
      const { votingExchange, deployer } =
        await loadFixture(deploySetupFixture);
      await votingExchange.startVoting();
      await expect(
        votingExchange.connect(deployer).vote(newSuggestedPrice, 0n),
      ).to.be.revertedWith('Not enough tokens to vote');
    });
  });

  describe('End voting', () => {
    it('should revert if no active voting exists', async () => {
      const { votingExchange } = await loadFixture(deploySetupFixture);
      await expect(votingExchange.endVoting()).to.be.revertedWith(
        'No active voting',
      );
    });

    it('should revert if voting already ended', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await token.approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, tokensToVote);

      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      await expect(votingExchange.endVoting()).to.be.revertedWith(
        'Voting already ended',
      );
    });

    it('should revert if voting period has not expired', async () => {
      const { votingExchange } = await loadFixture(deploySetupFixture);

      await votingExchange.startVoting();
      await expect(votingExchange.endVoting()).to.be.revertedWith(
        'Voting period has not expired',
      );
    });

    it('should emit EndVoting event with 0 price if no votes were cast', async () => {
      const { votingExchange } = await loadFixture(deploySetupFixture);

      await votingExchange.startVoting();
      await time.increase(TIME_TO_VOTE + 1n);

      await expect(votingExchange.endVoting())
        .to.emit(votingExchange, 'EndVoting')
        .withArgs(1, 0);
    });

    it('should emit EndVoting event with winning price when votes exist', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await token.approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, tokensToVote);

      await time.increase(TIME_TO_VOTE + 1n);

      await expect(votingExchange.endVoting())
        .to.emit(votingExchange, 'EndVoting')
        .withArgs(1, newSuggestedPrice);
    });
  });

  describe('Withdraw tokens', () => {
    it("should revert if voting hasn't ended", async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await token.approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, tokensToVote);

      await expect(votingExchange.withdrawTokens(1)).to.be.revertedWith(
        "The voting hasn't ended",
      );
    });

    it('should revert if user has no tokens to withdraw', async () => {
      const { votingExchange, voter1 } = await loadFixture(deploySetupFixture);

      await votingExchange.startVoting();
      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      await expect(
        votingExchange.connect(voter1).withdrawTokens(1),
      ).to.be.revertedWith('No tokens to withdraw');
    });

    it('should allow user to withdraw after voting ends', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await token.approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, tokensToVote);

      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      const balanceBefore = await token.balanceOf(deployer);
      await expect(votingExchange.withdrawTokens(1))
        .to.emit(token, 'Transfer')
        .withArgs(votingExchange.target, deployer, tokensToVote);

      const balanceAfter = await token.balanceOf(deployer);
      expect(balanceAfter - balanceBefore).to.equal(tokensToVote);
    });

    it('should revert if user tries to withdraw twice', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await token.approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, tokensToVote);

      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      await votingExchange.withdrawTokens(1);

      await expect(votingExchange.withdrawTokens(1)).to.be.revertedWith(
        'No tokens to withdraw',
      );
    });
  });
});
