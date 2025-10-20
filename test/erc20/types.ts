import { Signer } from 'ethers';

import { ERC20 } from '../../typechain-types';

export type ERC20Setup = {
  deployer: Signer;
  user: Signer;
  token: ERC20;
};
