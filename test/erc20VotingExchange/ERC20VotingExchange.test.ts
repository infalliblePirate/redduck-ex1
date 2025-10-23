import { time } from '@nomicfoundation/hardhat-network-helpers';
import { expect } from 'chai';
import { Signer } from 'ethers';
import hre from 'hardhat';

import { ERC20VotingExchangeSetup } from './types';

import { ERC20 } from '../../typechain-types';
import {
  ERC20__factory,
  ERC20VotingExchange__factory,
  ERC20VotingExchange,
} from '../../typechain-types';

describe('ERC20VotingExchange test', () => {
  const TIME_TO_VOTE = 5n * 60n;
  const CHALLENGE_PERIOD = 2n * 60n * 60n;
  const PRICE_SUGGESTION_THRESHOLD_BPS = 10n;
  const VOTE_THRESHOLD_BPS = 5n;
  const BPS_DENOMINATOR = 10000n;

  const FEE_DENOMINATOR: bigint = 10_000n;

  const name = 'Penguin';
  const symbol = 'PNGN';
  const decimals = 6n;

  const expectedSupply = hre.ethers.parseUnits('1000', decimals);
  const expectedPrice = hre.ethers.parseEther('0.000001');
  const expectedLiquidityEth = hre.ethers.parseEther('10');
  const expectedFeeBP = 10n;

  const tradeEthAmount = hre.ethers.parseEther('0.000001');
  const newSuggestedPrice = hre.ethers.parseEther('0.000002');
  const tokensToVote = (expectedSupply * VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;
  const tokensToSuggest =
    (expectedSupply * PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;

  const bufferMultiplier = 101n;
  const bufferDenominator = 100n;

  const ethToSuggest =
    (tokensToSuggest * expectedPrice * bufferMultiplier) /
    (10n ** decimals * bufferDenominator);
  const ethToVote =
    (tokensToVote * expectedPrice * bufferMultiplier) /
    (10n ** decimals * bufferDenominator);

  const setup = async (): Promise<ERC20VotingExchangeSetup> => {
    const [deployer, user] = await hre.ethers.getSigners();

    const token = await new ERC20__factory(deployer).deploy(
      decimals,
      name,
      symbol,
    );

    const votingExchange = await new ERC20VotingExchange__factory(
      deployer,
    ).deploy(token, expectedPrice, expectedFeeBP);

    await token.setMinter(votingExchange);
    await votingExchange.addLiquidity(expectedSupply, {
      value: expectedLiquidityEth,
    });

    return {
      deployer,
      user,
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

    const fee = (tokensBought * expectedFeeBP) / FEE_DENOMINATOR;
    const tokensBoughtAfterFee = tokensBought - fee;

    return tokensBoughtAfterFee;
  };

  const calculateWinningPrice = async (
    suggestedPrices: bigint[],
    token: ERC20,
    votingExchange: ERC20VotingExchange,
  ): Promise<bigint> => {
    let highestVotes = 0n;
    let winningPrice = 0n;

    for (const price of suggestedPrices) {
      const voters = await votingExchange.votedAddresses(price);
      let totalVotes = 0n;

      for (const voter of voters) {
        const balance = await token.balanceOf(voter);
        totalVotes += BigInt(balance);
      }

      if (totalVotes > highestVotes) {
        highestVotes = totalVotes;
        winningPrice = BigInt(price);
      }
    }

    return winningPrice;
  };

  describe('Buy', () => {
    it('should allow buying tokens', async () => {
      const { votingExchange, user } = await setup();
      await expect(
        votingExchange.connect(user).buy({ value: tradeEthAmount }),
      ).to.emit(votingExchange, 'Buy');
    });

    it('should allow buying during active voting', async () => {
      const { votingExchange, user } = await setup();

      await votingExchange.startVoting();

      await expect(
        votingExchange.connect(user).buy({ value: tradeEthAmount }),
      ).to.emit(votingExchange, 'Buy');
    });
  });

  describe('Sell', () => {
    it('should allow selling tokens', async () => {
      const { votingExchange, user, token } = await setup();

      const boughtTokens = await buyTokens(
        votingExchange,
        user,
        tradeEthAmount,
      );
      await token.connect(user).approve(votingExchange, boughtTokens);
      await expect(votingExchange.connect(user).sell(boughtTokens)).to.emit(
        votingExchange,
        'Sell',
      );
    });
  });

  describe('Transfer', () => {
    it('should allow transferring tokens', async () => {
      const { votingExchange, user, deployer } = await setup();

      const boughtTokens = await buyTokens(
        votingExchange,
        user,
        tradeEthAmount,
      );

      await expect(
        votingExchange.connect(user).transfer(deployer, boughtTokens),
      ).to.not.be.reverted;
    });
  });

  describe('Start voting', () => {
    it('should start a new voting round and emit StartVoting event', async () => {
      const { votingExchange, deployer } = await setup();

      await expect(votingExchange.connect(deployer).startVoting()).to.emit(
        votingExchange,
        'StartVoting',
      );

      expect(await votingExchange.votingStartedTimeStamp()).to.be.closeTo(
        await time.latest(),
        1,
      );
    });

    it('should revert if non-owner starts voting', async () => {
      const { votingExchange, user } = await setup();
      await expect(votingExchange.connect(user).startVoting()).to.be.reverted;
    });

    it('should revert if voting is already active', async () => {
      const { votingExchange } = await setup();

      await votingExchange.startVoting();
      await expect(votingExchange.startVoting()).to.be.revertedWith(
        'Voting already active',
      );
    });

    it('should allow starting new voting after previous round ended', async () => {
      const { votingExchange } = await setup();

      await votingExchange.startVoting();
      await time.increase(TIME_TO_VOTE);

      await expect(votingExchange.startVoting()).to.not.be.reverted;
    });
  });

  describe('Suggest price', () => {
    it('should revert if user does not have enough balance', async () => {
      const { votingExchange, user } = await setup();

      await votingExchange.startVoting();
      await expect(
        votingExchange.connect(user).vote(newSuggestedPrice),
      ).to.be.revertedWith('The account cannot suggest price');
    });

    it('should revert if voting not started', async () => {
      const { votingExchange, user } = await setup();
      await expect(
        votingExchange.connect(user).vote(newSuggestedPrice),
      ).to.be.revertedWith('No active voting');
    });

    it('should allow suggesting a price and emit PriceSuggested', async () => {
      const { votingExchange, user, token } = await setup();

      await buyTokens(votingExchange, user, ethToSuggest);
      const userBalance = await token.balanceOf(user);

      await votingExchange.startVoting();

      await expect(votingExchange.connect(user).vote(newSuggestedPrice))
        .to.emit(votingExchange, 'PriceSuggested')
        .withArgs(user, newSuggestedPrice, userBalance);
      expect(
        (await votingExchange.suggestedPrices()).includes(newSuggestedPrice),
      ).to.eq(true);
    });

    it('should revert after voting time has passed', async () => {
      const { votingExchange, user } = await setup();

      await buyTokens(votingExchange, user, ethToSuggest);
      await votingExchange.startVoting();

      await time.increase(TIME_TO_VOTE);

      await expect(
        votingExchange.connect(user).vote(newSuggestedPrice),
      ).to.be.revertedWith('No active voting');
    });

    it('should not allow same user to suggest multiple prices', async () => {
      const { votingExchange, deployer } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await votingExchange.startVoting();

      const price1 = hre.ethers.parseEther('0.000002');
      const price2 = hre.ethers.parseEther('0.000003');

      await expect(votingExchange.connect(deployer).vote(price1)).to.emit(
        votingExchange,
        'PriceSuggested',
      );

      await expect(
        votingExchange.connect(deployer).vote(price2),
      ).to.be.revertedWith('User already voted');
    });
  });

  describe('Vote', () => {
    it('should revert if no active voting', async () => {
      const { votingExchange, user } = await setup();

      await expect(
        votingExchange.connect(user).vote(newSuggestedPrice),
      ).to.be.revertedWith('No active voting');
    });

    it('should revert if user balance below threshold', async () => {
      const { votingExchange, user, deployer } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await votingExchange.startVoting();
      await votingExchange.connect(deployer).vote(newSuggestedPrice);

      await expect(
        votingExchange.connect(user).vote(newSuggestedPrice),
      ).to.be.revertedWith('The account cannot vote');
    });

    it('should allow voting on suggested price and emit VoteCasted', async () => {
      const { votingExchange, user, deployer, token } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await buyTokens(votingExchange, user, ethToVote);

      await votingExchange.startVoting();

      await votingExchange.connect(deployer).vote(newSuggestedPrice);

      const userBalance = await token.balanceOf(user);

      await expect(votingExchange.connect(user).vote(newSuggestedPrice))
        .to.emit(votingExchange, 'VoteCasted')
        .withArgs(user, newSuggestedPrice, userBalance);
    });

    it('should allow multiple users to vote for same price', async () => {
      const { votingExchange, deployer, user } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await buyTokens(votingExchange, user, ethToVote);

      await votingExchange.startVoting();

      await votingExchange.connect(deployer).vote(newSuggestedPrice);
      await expect(
        votingExchange.connect(user).vote(newSuggestedPrice),
      ).to.emit(votingExchange, 'VoteCasted');
      expect(
        (await votingExchange.votedAddresses(newSuggestedPrice)).includes(
          await deployer.getAddress(),
        ),
      ).to.eq(true);
      expect(
        (await votingExchange.votedAddresses(newSuggestedPrice)).includes(
          await user.getAddress(),
        ),
      ).to.eq(true);
    });

    it('should not allow same user to vote for multiple prices', async () => {
      const { votingExchange, deployer, user } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await buyTokens(votingExchange, user, ethToSuggest);

      await votingExchange.startVoting();

      const price1 = hre.ethers.parseEther('0.000002');
      const price2 = hre.ethers.parseEther('0.000003');

      await votingExchange.connect(deployer).vote(price1);
      await votingExchange.connect(user).vote(price2);

      await expect(
        votingExchange.connect(deployer).vote(price2),
      ).to.be.revertedWith('User already voted');
    });
  });

  describe('Propose Result', () => {
    it('should revert if no voting in progress', async () => {
      const { votingExchange, deployer } = await setup();

      await expect(
        votingExchange.connect(deployer).proposeResult(newSuggestedPrice),
      ).to.be.revertedWith('No voting in progress');
    });

    it('should revert if voting is still in progress', async () => {
      const { votingExchange, deployer } = await setup();

      await votingExchange.startVoting();

      await expect(
        votingExchange.connect(deployer).proposeResult(newSuggestedPrice),
      ).to.be.revertedWith('Voting is still in progress');
    });

    it('should allow proposing result after voting time passed', async () => {
      const { votingExchange, deployer, user, token } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await votingExchange.startVoting();
      await votingExchange.connect(deployer).vote(newSuggestedPrice);

      await time.increase(TIME_TO_VOTE);

      const winner = await calculateWinningPrice(
        await votingExchange.suggestedPrices(),
        token,
        votingExchange,
      );

      const tx = await votingExchange.connect(user).proposeResult(winner);
      const receipt = (await tx.wait())!;

      const eventTopic =
        votingExchange.interface.getEvent('ResultProposed').topicHash;
      const log = receipt.logs.find((log) => log.topics[0] === eventTopic);
      const parsed = votingExchange.interface.parseLog(log!);

      const [proposer, winningPrice, proposedAt] = parsed!.args;

      expect(proposer).to.eq(user);
      expect(winningPrice).to.eq(newSuggestedPrice);
      expect(proposedAt).to.be.closeTo(await time.latest(), 1);
    });
  });

  describe('Challenge Result', () => {
    it('should revert if no result to challenge', async () => {
      const { votingExchange, user } = await setup();

      await expect(
        votingExchange.connect(user).challengeResult(newSuggestedPrice),
      ).to.be.revertedWith('No result to challenge');
    });

    it('should revert if result already finalized', async () => {
      const { votingExchange, deployer } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await votingExchange.startVoting();
      await votingExchange.connect(deployer).vote(newSuggestedPrice);

      await time.increase(TIME_TO_VOTE);
      await votingExchange.proposeResult(newSuggestedPrice);

      await time.increase(CHALLENGE_PERIOD);
      await votingExchange.finalizeVoting();

      await expect(
        votingExchange.connect(deployer).challengeResult(newSuggestedPrice),
      ).to.be.revertedWith('Result already finalized');
    });

    it('should revert if challenge period ended', async () => {
      const { votingExchange, deployer } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await votingExchange.startVoting();
      await votingExchange.connect(deployer).vote(newSuggestedPrice);

      await time.increase(TIME_TO_VOTE);
      await votingExchange.proposeResult(newSuggestedPrice);

      await time.increase(CHALLENGE_PERIOD + 1n);

      await expect(
        votingExchange.connect(deployer).challengeResult(newSuggestedPrice),
      ).to.be.revertedWith('Challenge period ended');
    });

    it('should revert if claimed winner is wrong', async () => {
      const { votingExchange, deployer, user } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest * 2n);
      await buyTokens(votingExchange, user, ethToSuggest);

      await votingExchange.startVoting();

      const price1 = hre.ethers.parseEther('0.000002');
      const price2 = hre.ethers.parseEther('0.000003');

      await votingExchange.connect(deployer).vote(price1);
      await votingExchange.connect(user).vote(price2);

      await time.increase(TIME_TO_VOTE);
      await votingExchange.proposeResult(price2);

      await expect(
        votingExchange.connect(deployer).challengeResult(price2),
      ).to.be.revertedWith('The claimed winner is wrong');
    });

    it('should succeed and emit ResultChallenged if winner is correct', async () => {
      const { votingExchange, deployer, user, token } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest * 2n);
      await buyTokens(votingExchange, user, ethToSuggest);

      await votingExchange.startVoting();

      const price1 = hre.ethers.parseEther('0.000002');
      const price2 = hre.ethers.parseEther('0.000003');

      await votingExchange.connect(deployer).vote(price1);
      await votingExchange.connect(user).vote(price2);

      await time.increase(TIME_TO_VOTE);
      await votingExchange.proposeResult(price1);

      const winner = await calculateWinningPrice(
        await votingExchange.suggestedPrices(),
        token,
        votingExchange,
      );

      await expect(votingExchange.connect(user).challengeResult(price1))
        .to.emit(votingExchange, 'ResultChallenged')
        .withArgs(winner, user);
    });
  });
});
