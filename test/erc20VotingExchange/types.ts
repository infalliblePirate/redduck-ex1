import { Signer } from 'ethers';

import { ERC20, ERC20VotingExchange } from '../../typechain-types';

export type ERC20VotingExchangeSetup = {
  deployer: Signer;
  user: Signer;
  votingExchange: ERC20VotingExchange;
  token: ERC20;
};
