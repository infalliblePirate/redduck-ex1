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
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, balance, 0, 0);

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
        .vote(newSuggestedPrice, tokensToVote, 0, 0);

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
        votingExchange
          .connect(deployer)
          .vote(newSuggestedPrice, tokensToVote, 0, 0),
      ).to.be.revertedWith('No active voting');
    });

    it('should revert if user balance below threshold', async () => {
      const { votingExchange, voter1, token } =
        await loadFixture(deploySetupFixture);
      await votingExchange.startVoting();

      await token.connect(voter1).approve(votingExchange, tokensToVote);
      await expect(
        votingExchange
          .connect(voter1)
          .vote(newSuggestedPrice, tokensToVote, 0, 0),
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
        .vote(newSuggestedPrice, deployerBalance, 0, 0);

      const before = await votingExchange.pendingPriceVotes(
        votingNumber,
        newSuggestedPrice,
      );

      const voterBalance = await token.balanceOf(voter1);
      await token.connect(voter1).approve(votingExchange, voterBalance);
      const tx = await votingExchange
        .connect(voter1)
        .vote(newSuggestedPrice, voterBalance, 0, 0);
      await expect(tx)
        .to.emit(votingExchange, 'VoteCasted')
        .withArgs(voter1, votingNumber, newSuggestedPrice, voterBalance);

      const after = await votingExchange.pendingPriceVotes(
        votingNumber,
        newSuggestedPrice,
      );
      expect(after - before).to.equal(voterBalance);
    });

    it('should allow user to vote multiple times for same price', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);
      await buyTokens(votingExchange, deployer, 2n * ethToVote);
      await votingExchange.startVoting();

      const balance = await token.balanceOf(deployer);
      const halfBalance = balance / 2n;

      await token.connect(deployer).approve(votingExchange, balance);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, halfBalance, 0, 0);

      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, halfBalance, 0, 0);
    });

    it('should revert if voting time expired', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);
      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await time.increase(TIME_TO_VOTE + 1n);
      const balance = await token.balanceOf(deployer);
      await expect(
        votingExchange.connect(deployer).vote(newSuggestedPrice, balance, 0, 0),
      ).to.be.revertedWith('No active voting');
    });

    it('should revert if voting with zero tokens', async () => {
      const { votingExchange, deployer } =
        await loadFixture(deploySetupFixture);
      await votingExchange.startVoting();
      await expect(
        votingExchange.connect(deployer).vote(newSuggestedPrice, 0n, 0, 0),
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
        .vote(newSuggestedPrice, tokensToVote, 0, 0);

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
        .vote(newSuggestedPrice, tokensToVote, 0, 0);

      await time.increase(TIME_TO_VOTE + 1n);

      await expect(votingExchange.endVoting())
        .to.emit(votingExchange, 'EndVoting')
        .withArgs(1, newSuggestedPrice);
    });
  });

  describe('Withdraw tokens', () => {
    it('should allow user to withdraw during active voting', async () => {
      const { votingExchange, deployer, token } =
        await loadFixture(deploySetupFixture);

      await buyTokens(votingExchange, deployer, ethToVote);
      await votingExchange.startVoting();

      await token.approve(votingExchange, tokensToVote);
      await votingExchange
        .connect(deployer)
        .vote(newSuggestedPrice, tokensToVote, 0, 0);

      const balanceBefore = await token.balanceOf(deployer);
      await expect(votingExchange.withdrawTokens(1, newSuggestedPrice, 0, 0))
        .to.emit(token, 'Transfer')
        .withArgs(votingExchange.target, deployer, tokensToVote);

      const balanceAfter = await token.balanceOf(deployer);
      expect(balanceAfter - balanceBefore).to.equal(tokensToVote);
    });

    it('should revert if user has no tokens to withdraw', async () => {
      const { votingExchange, voter1 } = await loadFixture(deploySetupFixture);

      await votingExchange.startVoting();
      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      await expect(
        votingExchange
          .connect(voter1)
          .withdrawTokens(1, newSuggestedPrice, 0, 0),
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
        .vote(newSuggestedPrice, tokensToVote, 0, 0);

      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      const balanceBefore = await token.balanceOf(deployer);
      await expect(votingExchange.withdrawTokens(1, newSuggestedPrice, 0, 0))
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
        .vote(newSuggestedPrice, tokensToVote, 0, 0);

      await time.increase(TIME_TO_VOTE + 1n);
      await votingExchange.endVoting();

      await votingExchange.withdrawTokens(1, newSuggestedPrice, 0, 0);

      await expect(
        votingExchange.withdrawTokens(1, newSuggestedPrice, 0, 0),
      ).to.be.revertedWith('No tokens to withdraw');
    });
  });

  describe('Stress tests with outdated hints', () => {
    it('should handle ascending traversal when hints require walking up the list', async () => {
      const { votingExchange, token } = await loadFixture(deploySetupFixture);

      const signers = await hre.ethers.getSigners();
      const users = signers.slice(0, 12);

      const lowVoteUsers = users.slice(0, 6);
      for (const user of lowVoteUsers) {
        const m = BigInt(Math.floor(Math.random() * 3) + 2);
        await buyTokens(votingExchange, user, ethToVote * m);
        await token
          .connect(user)
          .approve(votingExchange, hre.ethers.MaxUint256);
      }

      const highVoteUsers = users.slice(6);
      for (const user of highVoteUsers) {
        const m = BigInt(Math.floor(Math.random() * 5) + 6);
        await buyTokens(votingExchange, user, ethToVote * m);
        await token
          .connect(user)
          .approve(votingExchange, hre.ethers.MaxUint256);
      }

      await votingExchange.startVoting();
      for (const user of lowVoteUsers) {
        const price = BigInt(Math.floor(Math.random() * 50) + 1);
        const balance = await token.balanceOf(user);
        const [prev, next] = await votingExchange.findInsertPosition(
          balance,
          0,
          0,
        );
        await votingExchange.connect(user).vote(price, balance, prev, next);
      }

      let tailPrice = await votingExchange.getCurrentTopPrice();
      while (tailPrice !== 0n) {
        const [, next] = await votingExchange.getNode(tailPrice);
        if (next === 0n) break;
        tailPrice = next;
      }

      for (const user of highVoteUsers) {
        const price = BigInt(Math.floor(Math.random() * 50) + 51);

        const currentBalance = await token.balanceOf(user);

        const [prev, next] = await votingExchange.findInsertPosition(
          currentBalance,
          0,
          tailPrice,
        );

        await expect(
          votingExchange.connect(user).vote(price, currentBalance, prev, next),
        ).to.not.be.reverted;

        tailPrice = await votingExchange.getCurrentTopPrice();
        while (tailPrice !== 0n) {
          const [, next] = await votingExchange.getNode(tailPrice);
          if (next === 0n) break;
          tailPrice = next;
        }
      }

      const prices: bigint[] = [];
      let current = await votingExchange.getCurrentTopPrice();

      while (current !== 0n) {
        prices.push(current);
        const [, next] = await votingExchange.getNode(current);
        current = next;
      }

      for (let i = 1; i < prices.length; i++) {
        const votesPrev = await votingExchange.pendingPriceVotes(
          1,
          prices[i - 1],
        );
        const votesCurr = await votingExchange.pendingPriceVotes(1, prices[i]);
        expect(votesPrev).to.be.gte(
          votesCurr,
          'List is not sorted in descending order',
        );
      }

      const topPrice = await votingExchange.getCurrentTopPrice();
      const topVotes = await votingExchange.pendingPriceVotes(1, topPrice);

      for (const price of prices) {
        const votes = await votingExchange.pendingPriceVotes(1, price);
        expect(topVotes).to.be.gte(votes, 'Top price should have most votes');
      }

      expect(new Set(prices).size).to.equal(
        prices.length,
        'Duplicate nodes detected',
      );

      for (let i = 0; i < prices.length - 1; i++) {
        const [, next] = await votingExchange.getNode(prices[i]);
        expect(next).to.equal(prices[i + 1], 'Broken next pointer in list');
      }
    });

    it('should handle descending traversal when hints require walking down the list', async () => {
      const { votingExchange, token } = await loadFixture(deploySetupFixture);

      const signers = await hre.ethers.getSigners();
      const users = signers.slice(0, 12);

      const highVoteUsers = users.slice(0, 6);
      for (const user of highVoteUsers) {
        const m = BigInt(Math.floor(Math.random() * 5) + 6);
        await buyTokens(votingExchange, user, ethToVote * m);
        await token
          .connect(user)
          .approve(votingExchange, hre.ethers.MaxUint256);
      }

      const lowVoteUsers = users.slice(6);
      for (const user of lowVoteUsers) {
        const m = BigInt(Math.floor(Math.random() * 3) + 2);
        await buyTokens(votingExchange, user, ethToVote * m);
        await token
          .connect(user)
          .approve(votingExchange, hre.ethers.MaxUint256);
      }

      await votingExchange.startVoting();

      for (const user of highVoteUsers) {
        const price = BigInt(Math.floor(Math.random() * 50) + 51);
        const balance = await token.balanceOf(user);
        const [prev, next] = await votingExchange.findInsertPosition(
          balance,
          0,
          0,
        );
        await votingExchange.connect(user).vote(price, balance, prev, next);
      }

      const headPrice = await votingExchange.getCurrentTopPrice();

      for (const user of lowVoteUsers) {
        const price = BigInt(Math.floor(Math.random() * 50) + 1);

        const currentBalance = await token.balanceOf(user);

        const [prev, next] = await votingExchange.findInsertPosition(
          currentBalance,
          headPrice,
          0,
        );

        await expect(
          votingExchange.connect(user).vote(price, currentBalance, prev, next),
        ).to.not.be.reverted;
      }

      const prices: bigint[] = [];
      let current = await votingExchange.getCurrentTopPrice();

      while (current !== 0n) {
        prices.push(current);
        const [, next] = await votingExchange.getNode(current);
        current = next;
      }

      for (let i = 1; i < prices.length; i++) {
        const votesPrev = await votingExchange.pendingPriceVotes(
          1,
          prices[i - 1],
        );
        const votesCurr = await votingExchange.pendingPriceVotes(1, prices[i]);
        expect(votesPrev).to.be.gte(
          votesCurr,
          'List is not sorted in descending order',
        );
      }

      const topPrice = await votingExchange.getCurrentTopPrice();
      const topVotes = await votingExchange.pendingPriceVotes(1, topPrice);

      for (const price of prices) {
        const votes = await votingExchange.pendingPriceVotes(1, price);
        expect(topVotes).to.be.gte(votes, 'Top price should have most votes');
      }

      expect(new Set(prices).size).to.equal(
        prices.length,
        'Duplicate nodes detected',
      );

      for (let i = 0; i < prices.length - 1; i++) {
        const [, next] = await votingExchange.getNode(prices[i]);
        expect(next).to.equal(prices[i + 1], 'Broken next pointer in list');
      }
    });

    it('stress tests outdated hints with 20 concurrent users', async function () {
      const { votingExchange, token } = await loadFixture(deploySetupFixture);

      const signers = await hre.ethers.getSigners();
      const users = signers.slice(0, 20);

      for (const user of users) {
        const m = BigInt(Math.floor(Math.random() * 8) + 2);
        await buyTokens(votingExchange, user, ethToVote * m);
        await token
          .connect(user)
          .approve(votingExchange, hre.ethers.MaxUint256);
      }

      await votingExchange.startVoting();

      const hints = [];
      for (const user of users) {
        const price = BigInt(Math.floor(Math.random() * 100) + 1);

        const [prev, next] = await votingExchange
          .connect(user)
          .findInsertPosition(await token.balanceOf(user), 0, 0);

        hints.push({ user, price, prev, next });
      }

      hints.sort(() => Math.random() - 0.5);

      for (const { user, price, prev, next } of hints) {
        await votingExchange
          .connect(user)
          .vote(price, await token.balanceOf(user), prev, next);
      }

      const prices: bigint[] = [];
      let current = await votingExchange.getCurrentTopPrice();

      while (current !== 0n) {
        prices.push(current);
        const [, next] = await votingExchange.getNode(current);
        current = next;
      }

      // const pricesWithVotes = await Promise.all(
      //   prices.map(async (p) => {
      //     const votes = await votingExchange.pendingPriceVotes(1, p);
      //     return `${p.toString()} -> ${votes.toString()}`;
      //   })
      // );

      // console.log(pricesWithVotes.join(", "));

      for (let i = 1; i < prices.length; i++) {
        const votesPrev = await votingExchange.pendingPriceVotes(
          1,
          prices[i - 1],
        );
        const votesCurr = await votingExchange.pendingPriceVotes(1, prices[i]);
        expect(votesPrev).to.be.gte(votesCurr, 'List is not sorted correctly');
      }

      if (prices.length > 0) {
        const headVotes = await votingExchange.pendingPriceVotes(1, prices[0]);
        for (let i = 1; i < prices.length; i++) {
          const votes = await votingExchange.pendingPriceVotes(1, prices[i]);
          expect(headVotes).to.be.gte(
            votes,
            'Head does not have the most votes',
          );
        }
      }

      expect(new Set(prices).size).to.equal(
        prices.length,
        'Duplicate nodes detected',
      );

      for (let i = 0; i < prices.length - 1; i++) {
        const [, next] = await votingExchange.getNode(prices[i]);
        expect(next).to.equal(prices[i + 1], 'Broken next pointer in list');
      }
    });
  });
});
