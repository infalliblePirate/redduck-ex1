import { Signer } from 'ethers';

import { ERC20, ERC20VotingExchange } from '../../typechain-types';

export type ERC20VotingExchangeSetup = {
  deployer: Signer;
  voter1: Signer;
  voter2: Signer;
  votingExchange: ERC20VotingExchange;
  token: ERC20;
};
