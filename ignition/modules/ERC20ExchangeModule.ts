import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export default buildModule('ERC20Exchange', (m) => {
  const tokenAddress = m.getParameter('tokenAddress');
  const price = m.getParameter('price');
  const feeBP = m.getParameter('feeBP');
  const exchange = m.contract('ERC20Exchange', [tokenAddress, price, feeBP]);
  return { exchange };
});
