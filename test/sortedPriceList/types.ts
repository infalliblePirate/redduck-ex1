import { Signer } from 'ethers';

import { SortedArraySet } from '../../typechain-types';

export type SortedArraySetSetup = {
  deployer: Signer;
  set: SortedArraySet;
};
