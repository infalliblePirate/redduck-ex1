import { ERC20, ERC20VotingExchange } from '../../typechain-types';
import { Signer } from 'ethers';

export type ERC20VotingExchangeSetup = {
  deployer: Signer;
  user: Signer;
  votingExchange: ERC20VotingExchange;
  token: ERC20;
};
