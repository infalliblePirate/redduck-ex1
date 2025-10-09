import { ERC20 } from '../typechain-types';

export type ERC20Setup = {
    deployer: string,
    user: string,
    token: ERC20,
};