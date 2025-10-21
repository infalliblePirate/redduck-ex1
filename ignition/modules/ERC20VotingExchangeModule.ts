import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export default buildModule('ERC20VotingExchange', (m) => {
  const tokenAddress = m.getParameter('tokenAddress');
  const price = m.getParameter('price');
  const feeBP = m.getParameter('feeBP');

  const votingExchange = m.contract('ERC20VotingExchange', [
    tokenAddress,
    price,
    feeBP,
  ]);
  return { votingExchange };
});
