import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { getAlchemySepoliaUrl } from "./helpers/alchemy.helpers";
import dotenv from "dotenv";

dotenv.config();

function getEnvVar(name: string): string {
  const value = process.env[name];
  if (!value) {
    throw new Error(`Environment variable ${name} is not defined`);
  }
  return value;
}

const ALCHEMY_API_KEY = getEnvVar("ALCHEMY_API_KEY");
const PRIVATE_KEY = getEnvVar("PRIVATE_KEY");

const config: HardhatUserConfig = {
  solidity: "0.8.28",
  networks: {
    sepolia: {
      chainId: 11155111,
      url: getAlchemySepoliaUrl(ALCHEMY_API_KEY),
      accounts: [PRIVATE_KEY],
    },
  },
};

export default config;
