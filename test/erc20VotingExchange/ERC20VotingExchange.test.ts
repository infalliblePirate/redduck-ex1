// import { time } from '@nomicfoundation/hardhat-network-helpers';
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
  // const TIME_TO_VOTE = 5n * 60n;
  // const CHALLENGE_PERIOD = 2n * 60n * 60n;
  // const PRICE_SUGGESTION_THRESHOLD_BPS = 10n;
  // const VOTE_THRESHOLD_BPS = 5n;
  // const BPS_DENOMINATOR = 10000n;

  const FEE_DENOMINATOR: bigint = 10_000n;

  const name = 'Penguin';
  const symbol = 'PNGN';
  const decimals = 6n;

  const expectedSupply = hre.ethers.parseUnits('1000', decimals);
  const expectedPrice = hre.ethers.parseEther('0.000001');
  const expectedLiquidityEth = hre.ethers.parseEther('10');
  const expectedFeeBP = 10n;

  const tradeEthAmount = hre.ethers.parseEther('0.000001');
  // const newSuggestedPrice = hre.ethers.parseEther('0.000002');
  // const tokensToVote = (expectedSupply * VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;
  // const tokensToSuggest =
  //   (expectedSupply * PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;

  // const bufferMultiplier = 101n;
  // const bufferDenominator = 100n;

  // const ethToSuggest =
  //   (tokensToSuggest * expectedPrice * bufferMultiplier) /
  //   (10n ** decimals * bufferDenominator);
  // const ethToVote =
  //   (tokensToVote * expectedPrice * bufferMultiplier) /
  //   (10n ** decimals * bufferDenominator);

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
});
