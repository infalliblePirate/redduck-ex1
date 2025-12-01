import { buildModule } from '@nomicfoundation/hardhat-ignition/modules';

export default buildModule('SortedPriceList', (m) => {
  const list = m.contract('SortedPriceList', []);
  return { list };
});
