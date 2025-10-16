import { expect } from "chai";
import hre from "hardhat";
import { ERC20__factory, ERC20VotingExchange__factory, ERC20VotingExchange } from "../../typechain-types";
import { ERC20VotingExchangeSetup } from "./types";
import { Signer } from "ethers";

import { time } from "@nomicfoundation/hardhat-network-helpers";

describe('ERC20VotingExchange test', () => {

    const TIME_TO_VOTE = 5n * 60n;
    const PRICE_SUGGESTION_THRESHOLD_BPS = 10n;
    const VOTE_THRESHOLD_BPS = 5n;
    const BPS_DENOMINATOR = 10000n;

    const FEE_DENOMINATOR: bigint = 10_000n;

    const name = "Penguin";
    const symbol = "PNGN";
    const decimals = 6n;

    const expectedSupply = hre.ethers.parseUnits("1000", decimals);
    const expectedPrice = hre.ethers.parseEther("0.000001");
    const expectedLiquidityEth = hre.ethers.parseEther("10");
    const expectedFeeBP = 10n;

    const tradeEthAmount = hre.ethers.parseEther("0.000001");
    const newSuggestedPrice = hre.ethers.parseEther("0.000002");
    const tokensToVote = (expectedSupply * VOTE_THRESHOLD_BPS) / BPS_DENOMINATOR;
    const tokensToSuggest = (expectedSupply * PRICE_SUGGESTION_THRESHOLD_BPS) / BPS_DENOMINATOR;

    // 1% to acount for the fee
    const bufferMultiplier = 101n;
    const bufferDenominator = 100n;

    const ethToSuggest = (tokensToSuggest * expectedPrice * bufferMultiplier) / ((10n ** decimals) * bufferDenominator);
    const ethToVote = (tokensToVote * expectedPrice * bufferMultiplier) / ((10n ** decimals) * bufferDenominator);

    const setup = async (): Promise<ERC20VotingExchangeSetup> => {
        const [deployer, user] = await hre.ethers.getSigners();

        const token = await new ERC20__factory(deployer)
            .deploy(decimals, name, symbol);

        const votingExchange = await new ERC20VotingExchange__factory(deployer).deploy(
            token, expectedPrice, expectedFeeBP);

        await token.setMinter(votingExchange);
        await votingExchange.addLiquidity(expectedSupply, { value: expectedLiquidityEth });

        return {
            deployer,
            user,
            votingExchange,
            token
        };
    };

    const buyTokens = async (votingExchange: ERC20VotingExchange, user: Signer, amount: bigint): Promise<bigint> => {
        const tx = await votingExchange.connect(user).buy({ value: amount });
        const receipt = (await tx.wait())!;

        const eventTopic = votingExchange.interface.getEvent('Buy').topicHash;
        const buyLog = receipt?.logs.find((log) => log.topics[0] === eventTopic)!;

        const parsed = votingExchange.interface.parseLog(buyLog)!;
        const tokensBought = parsed.args.tokensBought;

        const fee = tokensBought * expectedFeeBP / FEE_DENOMINATOR;
        const tokensBoughtAfterFee = tokensBought - fee;

        return tokensBoughtAfterFee;
    };

    describe("Restrictions during voting", () => {

        it("should revert buy/sell/transfer after user voted", async () => {
            const { votingExchange, deployer, user, token } = await setup();

            await votingExchange.connect(deployer).startVoting();
            await buyTokens(votingExchange, deployer, ethToSuggest);
            await votingExchange.connect(deployer).suggestNewPrice(newSuggestedPrice);
            await expect(
                votingExchange.connect(deployer).buy({ value: tradeEthAmount })
            ).to.be.revertedWith("The account has voted, cannot buy, sell or transfer");
            await expect(
                votingExchange.connect(deployer).transfer(user, await token.balanceOf(deployer))
            ).to.be.revertedWith("The account has voted, cannot buy, sell or transfer");

            await buyTokens(votingExchange, user, ethToVote);
            await votingExchange.connect(user).vote(newSuggestedPrice);

            await expect(
                votingExchange.connect(user).buy({ value: tradeEthAmount })
            ).to.be.revertedWith("The account has voted, cannot buy, sell or transfer");

            const userTokens = await token.balanceOf(user);
            await token.connect(user).approve(votingExchange, userTokens);
            await expect(
                votingExchange.connect(user).sell(userTokens)
            ).to.be.revertedWith("The account has voted, cannot buy, sell or transfer");

            await expect(
                votingExchange.connect(user).transfer(deployer, userTokens)
            ).to.be.revertedWith("The account has voted, cannot buy, sell or transfer");
        });
    });

    describe('Buy', () => {
        it("should allow buying when user has not voted", async () => {
            const { votingExchange, user } = await setup();
            await expect(votingExchange.connect(user).buy({ value: tradeEthAmount }))
                .to.emit(votingExchange, "Buy");
        });
    });

    describe('Sell', () => {
        it("should allow selling when user has not voted", async () => {
            const { votingExchange, user, token } = await setup();

            const boughtTokens = await buyTokens(votingExchange, user, tradeEthAmount);
            await token.connect(user).approve(votingExchange, boughtTokens);
            await expect(votingExchange.connect(user).sell(boughtTokens))
                .to.emit(votingExchange, "Sell");
        });
    });

    describe("Start voting", () => {
        it("should start a new voting round, update isVotingActive, votingNumber, votingStartedTimeStamp, emit StartVoting event",
            async () => {
                const { votingExchange, deployer } = await setup();

                await expect(votingExchange.connect(deployer).startVoting())
                    .to.emit(votingExchange, "StartVoting");

                expect(await votingExchange.votingNumber()).to.eq(1);
                expect(await votingExchange.votingStartedTimeStamp())
                    .to.be.closeTo(await time.latest(), 1);
            });
        it("should revert if non-owner starts voting or when we try to start aready pending", async () => {
            const { votingExchange, user } = await setup();
            await expect(votingExchange.connect(user).startVoting())
                .to.be.reverted;
        });
    });

    describe('Suggest price', () => {
        it('should revert if user doesn\'t have enough balance or voting not started', async () => {
            const { votingExchange, user } = await setup();

            await expect(
                votingExchange.connect(user).suggestNewPrice(newSuggestedPrice)
            ).to.be.revertedWith("No active voting");

            await votingExchange.startVoting();
            await expect(
                votingExchange.connect(user).suggestNewPrice(newSuggestedPrice)
            ).to.be.revertedWith("The account cannot suggest price");
        });

        it("should allow to suggest price and emit PriceSuggested, updating state correctly", async () => {
            const { votingExchange, user, token } = await setup();

            await buyTokens(votingExchange, user, ethToSuggest);
            const userBalance = await token.balanceOf(user);

            await votingExchange.startVoting();
            const votingNumber = await votingExchange.currentVotingNumber();

            const tx = await votingExchange.connect(user).suggestNewPrice(newSuggestedPrice);
            await expect(tx)
                .to.emit(votingExchange, "PriceSuggested")
                .withArgs(user, votingNumber, newSuggestedPrice, userBalance);
            await tx.wait();

            const pendingVotes = await votingExchange.pendingPriceVotes(votingNumber, newSuggestedPrice);
            expect(pendingVotes).to.equal(userBalance);
        });


        it('should revert because time has passed', async () => {
            const { votingExchange, user } = await setup();

            await buyTokens(votingExchange, user, ethToSuggest);
            await votingExchange.startVoting();

            await time.increase(TIME_TO_VOTE);

            await expect(
                votingExchange.connect(user).suggestNewPrice(newSuggestedPrice)
            ).to.be.revertedWith("No active voting");
        });

        it('should revert if same price is suggested twice', async () => {
            const { votingExchange, user } = await setup();

            await buyTokens(votingExchange, user, ethToSuggest);
            await votingExchange.startVoting();

            await expect(
                votingExchange.connect(user).suggestNewPrice(newSuggestedPrice)
            ).to.emit(votingExchange, "PriceSuggested");

            await expect(
                votingExchange.connect(user).suggestNewPrice(newSuggestedPrice)
            ).to.be.revertedWith("The account has voted, cannot buy, sell or transfer");
        });
    });

    describe("Vote", () => {
        it("should revert if no active voting", async () => {
            const { votingExchange, user } = await setup();

            await expect(votingExchange.connect(user).vote(newSuggestedPrice))
                .to.be.revertedWith("No active voting");
        });

        it("should revert if user balance below threshold", async () => {
            const { votingExchange, user } = await setup();

            await votingExchange.startVoting();

            await expect(votingExchange.connect(user).vote(newSuggestedPrice))
                .to.be.revertedWith("The account cannot vote");
        });

        it("should revert if price has not been suggested", async () => {
            const { votingExchange, user } = await setup();

            await buyTokens(votingExchange, user, ethToVote);
            await votingExchange.startVoting();

            await expect(votingExchange.connect(user).vote(newSuggestedPrice))
                .to.be.revertedWith("Price has not been suggested");
        });

        it("should allow voting, lock balance, update pending votes, and emit VoteCast", async () => {
            const { votingExchange, user, deployer, token } = await setup();

            await buyTokens(votingExchange, deployer, ethToSuggest);
            await buyTokens(votingExchange, user, ethToVote);

            await votingExchange.startVoting();
            const votingNumber = await votingExchange.currentVotingNumber();

            await votingExchange.connect(deployer).suggestNewPrice(newSuggestedPrice);
            const pendingVotesBefore = await votingExchange.pendingPriceVotes(votingNumber, newSuggestedPrice);
            const userBalance = await token.balanceOf(user);

            const tx = await votingExchange.connect(user).vote(newSuggestedPrice);
            await expect(tx)
                .to.emit(votingExchange, "VoteCasted")
                .withArgs(user, votingNumber, newSuggestedPrice, userBalance);

            const pendingVotesAfter = await votingExchange.pendingPriceVotes(votingNumber, newSuggestedPrice);
            expect(pendingVotesAfter - pendingVotesBefore).to.equal(userBalance);

            await expect(votingExchange.connect(user).vote(newSuggestedPrice))
                .to.be.revertedWith("The account has voted, cannot buy, sell or transfer");

            await expect(votingExchange.connect(user).buy({ value: tradeEthAmount }))
                .to.be.revertedWith("The account has voted, cannot buy, sell or transfer");

            const tokens = await token.balanceOf(user);
            await token.connect(user).approve(votingExchange, tokens);

            await expect(votingExchange.connect(user).sell(tokens))
                .to.be.revertedWith("The account has voted, cannot buy, sell or transfer");

            await expect(votingExchange.connect(user).transfer(user, tokens))
                .to.be.revertedWith("The account has voted, cannot buy, sell or transfer");
        });

        it("should allow multiple users to vote and accumulate votes correctly", async () => {
            const { votingExchange, deployer, user, token } = await setup();

            await buyTokens(votingExchange, deployer, ethToSuggest);
            await buyTokens(votingExchange, user, ethToVote);

            await votingExchange.startVoting();
            const votingNumber = await votingExchange.currentVotingNumber();

            await votingExchange.connect(deployer).suggestNewPrice(newSuggestedPrice);

            const deployerBalance = await token.balanceOf(deployer);
            const userBalance = await token.balanceOf(user);

            await votingExchange.connect(user).vote(newSuggestedPrice);

            const totalVotes = await votingExchange.pendingPriceVotes(votingNumber, newSuggestedPrice);
            expect(totalVotes).to.equal(deployerBalance + userBalance);
        });
    });

});