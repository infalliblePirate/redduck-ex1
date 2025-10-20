import { Signer } from 'ethers';

import { ERC20, ERC20Exchange } from '../../typechain-types';

export type ERC20ExchangeSetup = {
  deployer: Signer;
  user: Signer;
  exchange: ERC20Exchange;
  token: ERC20;
};
