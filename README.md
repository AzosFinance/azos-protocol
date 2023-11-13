# Azos

Azos is a modified fork of the upcoming HAI stablecoin protocol which will soon be live on Optimism mainnet.  Big shout out to the hard working legends from MakerDAO, Reflexer Finance and the Wonderland DeFi team moving HAI into production.

This repository contains the core smart contract code for HAI, a GEB fork. GEB is the abbreviation of [Gödel, Escher and Bach](https://en.wikipedia.org/wiki/G%C3%B6del,_Escher,_Bach) as well as the name of an [Egyptian god](https://en.wikipedia.org/wiki/Geb).

# Additions:

## SRC:

- StabilityModule.sol
- UniswapV2Adapter.sol
- BasicActionsMock.sol
- Distributor.sol

## SCRIPT:

- BasicActionsMockDeploy.s.sol
- Concentrate.s.sol
- DistributeETH.s.sol
- StabilityModuleDeploy.s.sol
- TestnetState.s.sol
- TestnetStateNoProxy.s.sol
- UniswapPoker.s.sol

# Modifications

The HAI core contracts and deployment scripts were modified to facilitate rapid prototyping.
