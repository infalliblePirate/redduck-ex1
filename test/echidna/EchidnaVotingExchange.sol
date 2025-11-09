// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "../../contracts/erc20/ERC20VotingExchange.sol";
import "../../contracts/erc20/ERC20.sol";

contract EchidnaVotingExchange {
    ERC20VotingExchange internal exchange;
    ERC20 internal token;

    mapping(uint256 => uint256) internal shadowTotalVotedPerRound;
    mapping(uint256 => mapping(address => mapping(uint256 => uint256)))
        internal shadowUserVotes; // [round][user][price]
    uint256 internal shadowCurrentRound;

    uint256 internal initialBalance;

    uint256 constant TIME_TO_VOTE = 1 days;
    uint8 constant VOTE_THRESHOLD_BPS = 5;
    uint16 constant BPS_DENOMINATOR = 10_000;
    uint256 constant INITIAL_SUPPLY = 1_000 * 10 ** 6;

    event DebugBalance(uint256 balance);

    mapping(address => bool) internal hasApproved;

    address[3] private senders = [
        address(0x10000),
        address(0x20000),
        address(0x30000)
    ];

    constructor() payable {
        token = new ERC20(6, "Penguin", "PNGN");
        exchange = new ERC20VotingExchange(address(token), 1 ether, 100);

        token.setMinter(address(exchange));
        exchange.addLiquidity{value: 1000 ether}(INITIAL_SUPPLY);

        exchange.buy{value: 900 ether}();
        initialBalance = token.balanceOf(address(this));
        token.approve(address(exchange), type(uint256).max);

        uint256 balanceForEach = initialBalance / 4;
        for (uint256 i = 0; i < senders.length; ++i) {
            token.transfer(senders[i], balanceForEach);
        }
    }

    function echidna_token_accounting() public view returns (bool) {
        uint256 accountBalance = token.balanceOf(address(this));

        uint256 totalShouldBeLocked = 0;
        for (uint256 i = 1; i <= shadowCurrentRound; ++i) {
            totalShouldBeLocked += shadowTotalVotedPerRound[i];
        }

        uint256 sharedAccrossSenders = 0;
        for (uint256 i = 0; i < senders.length; ++i) {
            sharedAccrossSenders += token.balanceOf(senders[i]);
        }

        uint256 expectedBalance = initialBalance -
            totalShouldBeLocked -
            sharedAccrossSenders;
        return accountBalance == expectedBalance;
    }

    function helper_approve() public {
        token.approve(address(exchange), type(uint256).max);
        hasApproved[msg.sender] = true;
    }

    function helper_startVoting() public {
        try exchange.startVoting() {
            uint256 newRound = exchange.currentVotingNumber();
            if (newRound > shadowCurrentRound) {
                shadowCurrentRound = newRound;
            }
        } catch {}
    }

    function helper_vote(uint256 price, uint256 tokenAmount) public {
        if (!hasApproved[msg.sender]) return;

        uint256 roundNum = exchange.currentVotingNumber();
        if (roundNum == 0) return;

        uint256 requiredSupplyToVote = (INITIAL_SUPPLY * VOTE_THRESHOLD_BPS) /
            BPS_DENOMINATOR;

        uint256 balance = token.balanceOf(msg.sender);

        emit DebugBalance(balance);

        if (balance < requiredSupplyToVote) return;

        price = _bound(price, 0.001 ether, 100 ether);
        tokenAmount = _bound(tokenAmount, requiredSupplyToVote, balance);

        try exchange.vote(price, tokenAmount) {
            shadowUserVotes[roundNum][msg.sender][price] += tokenAmount;
            shadowTotalVotedPerRound[roundNum] += tokenAmount;
        } catch {}
    }

    function helper_withdrawTokens(uint256 roundNumber, uint256 price) public {
        uint256 currentRound = exchange.currentVotingNumber();

        roundNumber = _bound(roundNumber, 1, currentRound);
        price = _bound(price, 0.001 ether, 100 ether);

        if (shadowUserVotes[roundNumber][msg.sender][price] <= 0) return;

        try exchange.withdrawTokens(roundNumber, price) {
            uint256 balance = shadowUserVotes[roundNumber][msg.sender][price];
            shadowUserVotes[roundNumber][msg.sender][price] = 0;
            
            uint256 toSubtract = balance;
            if (shadowTotalVotedPerRound[roundNumber] >= toSubtract) {
                shadowTotalVotedPerRound[roundNumber] -= toSubtract;
            }
        } catch {}
    }

    function _bound(
        uint256 x,
        uint256 min,
        uint256 max
    ) internal pure returns (uint256) {
        if (max < min) return min;
        if (x < min) return min;
        if (x > max) return max;
        return x;
    }
}
