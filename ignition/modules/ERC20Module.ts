import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export default buildModule('ERC20', (m) => {
  const decimals = m.getParameter<number>('decimals');
  const name = m.getParameter<string>('name');
  const symbol = m.getParameter<string>('symbol');
  const token = m.contract('ERC20', [decimals, name, symbol]);
  return { token };
});
