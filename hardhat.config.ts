import { HardhatUserConfig } from "hardhat/config";
import "@nomicfoundation/hardhat-toolbox";
import { config as dotenvConfig } from 'dotenv'
import { resolve } from 'path'
import "hardhat-deploy"

dotenvConfig({ path: resolve(__dirname, './.env') })

const { PRIVATE_KEY } = process.env
const accounts = PRIVATE_KEY ? [PRIVATE_KEY] : []

const config: HardhatUserConfig = {
  solidity: {
    version: "0.8.28",
    settings: {
      viaIR: true,
      optimizer: {
        enabled: true,
        runs: 200
      }
    }
  },
  networks: {
    bscTestnet: {
      url: `https://data-seed-prebsc-1-s1.binance.org:8545/`,
      accounts
    },
    bscMainnet: {
      url: `https://bsc-dataseed.binance.org/`,
      accounts
    }
  }
};

export default config;
