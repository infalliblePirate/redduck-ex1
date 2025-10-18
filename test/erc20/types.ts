import { ERC20 } from '../../typechain-types';
import { Signer } from 'ethers';

export type ERC20Setup = {
  deployer: Signer;
  user: Signer;
  token: ERC20;
};
