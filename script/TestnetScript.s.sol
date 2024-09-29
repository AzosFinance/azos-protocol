// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Contracts.s.sol';
import {Script, console} from 'forge-std/Script.sol';
import {Params, ParamChecker, WETH, OP} from '@script/Params.s.sol';
import {Common} from '@script/Common.s.sol';
import {TestnetDeployment} from '@script/TestnetDeployment.s.sol';
import '@script/Registry.s.sol';
import {TestnetParams, WETH, OP, WBTC, STONES, TOTEM} from '@script/TestnetParams.s.sol';

/**
 * @title  TestnetScript
 * @notice This contract is used to deploy the system on Testnet
 * @dev    This contract imports deployed addresses from `TestnetDeployment.s.sol`
 */
contract TestnetScript is TestnetDeployment, Common, Script {

  string public mnemonic;
  address[] public publicKeys;
  uint256[] public privateKeys;
  HaiProxy[] public proxies;

  function setUp() public virtual {}

  function deployProxy(address owner) public returns (address proxy) {
    proxy = proxyFactory.build(owner);
  }

  function mintTokens(address user, uint256 amount, address token) public {
    MintableERC20(token).mint(user, amount);
  }

  function mintAllTokens() public {
    for (uint256 i; i < publicKeys.length; i++) {
      uint256 userAmount = 10_000 * 1 ether * (i + 1);
      mintTokens(publicKeys[i], userAmount, address(collateral[WBTC]));
      mintTokens(publicKeys[i], userAmount, address(collateral[STONES]));
      mintTokens(publicKeys[i], userAmount, address(collateral[TOTEM]));
    }
  }

  function setApprovals() public {
    for (uint256 i; i < publicKeys.length; i++) {
      vm.stopBroadcast();
      vm.startBroadcast(publicKeys[i]);
      collateral[WBTC].approve(address(proxies[i]), type(uint256).max);
      collateral[STONES].approve(address(proxies[i]), type(uint256).max);
      collateral[TOTEM].approve(address(proxies[i]), type(uint256).max);
    }
  }

    // note that the SafeIds from the GebSafeManager will correspond to the indices of the publicKeys array
  function openSafe(
    address owner,
    HaiProxy proxy,
    uint256 collateralAmount,
    uint256 deltaWad,
    address collateralJoin,
    bytes32 collateralType
  ) public {
    vm.stopBroadcast();
    vm.startBroadcast(owner);
    bytes memory data = abi.encodeWithSelector(
      basicActions.openLockTokenCollateralAndGenerateDebt.selector,
      safeManager,
      taxCollector,
      collateralJoin,
      coinJoin,
      collateralType,
      collateralAmount,
      deltaWad
    );
    proxy.execute(address(basicActions), data);
  }

  function openAllSafes() public {
    for (uint32 i = 0; i < publicKeys.length; i++) {
      uint256 userAmount = 10_000 * 1 ether * (i + 1);
      uint256 dollarAmountWbtc = userAmount * delayedOracle[WBTC].read();
      uint256 dollarAmountStones = userAmount * delayedOracle[STONES].read();
      uint256 dollarAmountTotem = userAmount * delayedOracle[TOTEM].read();
      uint256 wbtcDelta = 1000 ether;
      uint256 stonesDelta = 1000 ether;
      uint256 totemDelta = 1000 ether;
      openSafe(publicKeys[i], proxies[i], userAmount, wbtcDelta, address(collateralJoin[WBTC]), WBTC );
      openSafe(publicKeys[i], proxies[i], userAmount, stonesDelta, address(collateralJoin[STONES]), STONES);
      openSafe(publicKeys[i], proxies[i], userAmount, totemDelta, address(collateralJoin[TOTEM]), TOTEM);
    }
  }

  function deriveKeys() public {
    for (uint32 i = 0; i < 10; i++) {
      (address publicKey, uint256 privateKey) = deriveRememberKey(mnemonic, i);
      publicKeys.push(publicKey);
      privateKeys.push(privateKey);
    }
  }

  function deployProxies() public {
    for (uint32 i = 0; i < publicKeys.length; i++) {
      address userProxyAddress = deployProxy(publicKeys[i]);
      HaiProxy userProxy = HaiProxy(payable(userProxyAddress));
      proxies.push(userProxy);
    }
  }

  /**
   * @notice This script is left as an example on how to use TestnetScript contract
   * @dev    This script is executed with `yarn script:testnet` command
   */
  function run() public {
    mnemonic = vm.envString('MNEMONIC');
    _getEnvironmentParams();
    deriveKeys();
    vm.startBroadcast();

    // Script goes here
    deployProxies();
    mintAllTokens();
    setApprovals();
    openAllSafes();

    vm.stopBroadcast();
  }
}
