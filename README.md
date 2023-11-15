# Azos

Azos is a modified fork of the upcoming HAI stablecoin protocol which will soon be live on Optimism mainnet.  Big shout out to the hard working legends from MakerDAO, Reflexer Finance and the Wonderland DeFi team.

This repository contains the core smart contract code for HAI, a GEB fork. GEB is the abbreviation of [Gödel, Escher and Bach](https://en.wikipedia.org/wiki/G%C3%B6del,_Escher,_Bach) as well as the name of an [Egyptian god](https://en.wikipedia.org/wiki/Geb).

# Instructions

- [Install Foundry](https://book.getfoundry.sh/getting-started/installation)
- `yarn install`
- `forge install`
- `forge compile`
- Create a new file named `.env` and copy the contents of `env.example` into it
- Configure your `.env` file's missing environment variables
- All of the commands to execute scripts live as comments at the bottom of each script contract

# Additions

The following files were written from scratch during the Hackathon:

## SRC:

- [StabilityModule.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/src/StabilityModule.sol)

`The Stability Module is the first Algorithmic Market Operations Module (AMO) created for a CDP-based Stablecoin protocol.  It allows flash-loan-like capabilities for specific constrained contract interactions.  Contract interactions from the Staility Module MUST stabilize the price of the ZAI stablecoin, and they MUST be profitable.`

---

- [UniswapV2Adapter.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/src/UniswapV2Adapter.sol)

`In order to facilitate constrained, gas efficient and secure market operations - the Stability Module needs special adapter contracts.  Each adapter contract allows the Stability Module to interact with a new external DeFi protocol.  We built a quick easy adapter to utilize Uniswap V2 in order to execute swap trades from the Stability module.`

---

- [BasicActionsMock.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/src/BasicActionsMock.sol)

`We made a small modification to the original "BasicActions.sol" contract in order to create a special event that reduced the time required to construct our front end and subgraphs.`

---

- [Distributor.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/src/Distributor.sol)

`This is a helper contract to enable us to automaticaly create, open and collateralize debt positions for many testing wallets.`

---

## SCRIPT:

- [BasicActionsMockDeploy.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/BasicActionsMockDeploy.s.sol)

`Deploys the modified BasicActions contract which simplifies creating and managing Safes.`

---

- [Concentrate.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/Concentrate.s.sol)

`Recovers testnet ETH from all of our testing wallets back to the deployer's wallet.`

---

- [DistributeETH.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/DistributeETH.s.sol)

`Generates test wallets and distributes ETH to all of them.`

---

- [StabilityModuleDeploy.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/StabilityModuleDeploy.s.sol)

`Deploys the Stability Module, Uniswap V2 Adapter, a mock "USDC" Stablecoin token. Deposits the "USDC" into the StabilityModule for "ZAI" then creates a new Uniswap liquidity pool for ZAI/USDC tokens. Then it trades against the Uniswap pool in order to imbalance the pool and thus disrupt ZAI's $1 peg. Afterwards it calls the Stability Module's expandAndBuy function in order to rebalance ZAI's price back towards the peg.`

---

- [TestnetState.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/TestnetState.s.sol)

`Used after "Distribute".  This mints tokens, distributes tokens, creates user proxies from the proxy registry and proxy factory, approves tokens and then creates new Safes for an arbitrary number of test wallets."

---

- [TestnetStateNoProxy.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/TestnetStateNoProxy.s.sol)

`This script allows recovering if at any point the RPC or mempool rejects a transaction because user wallets can only own one proxy - and calls to create another new proxy will revert.`

---

- [UniswapPoker.s.sol](https://github.com/AzosFinance/azos-protocol/blob/deployment/script/UniswapPoker.s.sol)

`This script is used to test the automated Stability Keeper.  We poke the Uniswap pools to execute trades and imbalance the pool; and thus the price of ZAI.`

# Modifications

Some of the HAI core contracts and deployment scripts were modified to facilitate rapid prototyping during the hackathon.
