// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Script} from 'forge-std/Script.sol';
import {BasicActionsMock} from "@src/BasicActionsMock.sol";

contract BasicActionsMockDeploy is Script {
  BasicActionsMock public basicActionsMock;
  address deployer;
  uint256 _deployerPk;

  function run() public {
    _deployerPk = uint256(vm.envBytes32("SEPOLIA_DEPLOYER_PK"));
    deployer = vm.addr(_deployerPk);
    vm.startBroadcast(deployer);

    basicActionsMock = new BasicActionsMock();
  }

  // forge script script/BasicActionsMockDeploy.s.sol:BasicActionsMockDeploy -f sepolia --broadcast --verify -vvvvv
}