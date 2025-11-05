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

  describe('EndVoting', () => {
    it('should revert if voting time not passed', async () => {
      const { votingExchange } = await setup();

      await votingExchange.startVoting();
      await expect(votingExchange.endVoting()).to.be.revertedWith(
        'Voting is still in progress',
      );
    });

    it('should set winning price for single suggestion', async () => {
      const { votingExchange, deployer } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);

      await votingExchange.startVoting();
      const votingNumber = await votingExchange.currentVotingNumber();

      await votingExchange.connect(deployer).suggestNewPrice(newSuggestedPrice);

      await time.increase(TIME_TO_VOTE);

      const tx = await votingExchange.endVoting();
      const receipt = (await tx.wait())!;
      const eventTopic =
        votingExchange.interface.getEvent('EndVoting').topicHash;
      const endLog = receipt.logs.find((log) => log.topics[0] === eventTopic)!;
      const parsed = votingExchange.interface.parseLog(endLog)!;

      expect(parsed.args.votingNumber).to.equal(votingNumber);
      expect(parsed.args.price).to.equal(newSuggestedPrice);
    });

    it('should pick price with highest votes when multiple suggestions exist', async () => {
      const { votingExchange, deployer, user, token } = await setup();

      const signers = await hre.ethers.getSigners();
      const user2 = signers[2];
      const user3 = signers[3];

      await buyTokens(votingExchange, deployer, ethToSuggest);
      await buyTokens(votingExchange, user, ethToSuggest);
      await buyTokens(votingExchange, user2, ethToVote);
      await buyTokens(votingExchange, user3, ethToSuggest);

      await votingExchange.startVoting();

      const price1 = hre.ethers.parseEther('0.000003');
      const price2 = hre.ethers.parseEther('0.000004');

      await votingExchange.connect(deployer).suggestNewPrice(price1);
      await votingExchange.connect(user).suggestNewPrice(price2);

      await votingExchange.connect(user2).vote(price1);
      await votingExchange.connect(user3).vote(price2);

      await time.increase(TIME_TO_VOTE);

      const tx = await votingExchange.endVoting();
      const receipt = (await tx.wait())!;
      const eventTopic =
        votingExchange.interface.getEvent('EndVoting').topicHash;
      const endLog = receipt.logs.find((log) => log.topics[0] === eventTopic)!;
      const parsed = votingExchange.interface.parseLog(endLog)!;

      const deployerVotes = await token.balanceOf(deployer);
      const userVotes = await token.balanceOf(user);
      const user2Votes = await token.balanceOf(user2);
      const user3Votes = await token.balanceOf(user3);

      const expectedWinner =
        deployerVotes + user2Votes > userVotes + user3Votes ? price1 : price2;
      expect(parsed.args?.price).to.equal(expectedWinner);
    });

    it('should emit 0 price if no suggestions were made', async () => {
      const { votingExchange } = await setup();

      await votingExchange.startVoting();
      await time.increase(TIME_TO_VOTE);

      const tx = await votingExchange.endVoting();
      const receipt = (await tx.wait())!;
      const eventTopic =
        votingExchange.interface.getEvent('EndVoting').topicHash;
      const endLog = receipt.logs.find((log) => log.topics[0] === eventTopic)!;
      const parsed = votingExchange.interface.parseLog(endLog)!;

      expect(parsed.args.price).to.equal(0);
    });

    it('should allow to start a new voting round after ending previous', async () => {
      const { votingExchange, deployer } = await setup();

      await buyTokens(votingExchange, deployer, ethToSuggest);

      await votingExchange.startVoting();
      await votingExchange.connect(deployer).suggestNewPrice(newSuggestedPrice);
      await time.increase(TIME_TO_VOTE);
      await votingExchange.endVoting();

      await expect(votingExchange.startVoting()).to.not.be.reverted;

      const newVotingNumber = await votingExchange.currentVotingNumber();
      expect(newVotingNumber).to.equal(2);
    });

    it('revert if there is no active voting', async () => {
      const { votingExchange } = await setup();
      await expect(votingExchange.endVoting()).be.revertedWith(
        'No voting in progress',
      );
    });
  });
});
