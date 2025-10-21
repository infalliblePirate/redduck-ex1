import hre from 'hardhat';

import ERC20ExchangeModule from '../ignition/modules/ERC20ExchangeModule';
import ERC20Module from '../ignition/modules/ERC20Module';
import ERC20VotingExchangeModule from '../ignition/modules/ERC20VotingExchangeModule';

const config = {
  token: {
    name: 'Penguin',
    symbol: 'PNGN',
    decimals: 6,
  },
  exchange: {
    price: hre.ethers.parseEther('0.000001'),
    feeBP: 100,
  },
  votingExchange: {
    price: hre.ethers.parseEther('0.000001'),
    feeBP: 100,
  },
};

async function main() {
  const { token } = await hre.ignition.deploy(ERC20Module, {
    parameters: { ERC20: config.token },
  });

  const tokenAddress = await token.getAddress();

  const { exchange } = await hre.ignition.deploy(ERC20ExchangeModule, {
    parameters: {
      ERC20Exchange: {
        tokenAddress,
        price: config.exchange.price,
        feeBP: config.exchange.feeBP,
      },
    },
  });

  const exchangeAddress = await exchange.getAddress();

  const { votingExchange } = await hre.ignition.deploy(
    ERC20VotingExchangeModule,
    {
      parameters: {
        ERC20VotingExchange: {
          tokenAddress,
          price: config.votingExchange.price,
          feeBP: config.votingExchange.feeBP,
        },
      },
    },
  );

  const votingExchangeAddress = await votingExchange.getAddress();

  const [deployer] = await hre.ethers.getSigners();
  const tokenContract = await hre.ethers.getContractAt(
    'ERC20',
    tokenAddress,
    deployer,
  );

  await (await tokenContract.setMinter(exchangeAddress)).wait();
  await (await tokenContract.setMinter(votingExchangeAddress)).wait();
}

main()
  .then(() => process.exit(0))
  .catch((error) => {
    console.error(error);
    process.exit(1);
  });
