// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Script, console2} from 'forge-std/Script.sol';
import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {MintableERC20} from '@contracts/for-test/MintableERC20.sol';
import {IUniswapV2Router02} from '@router/IUniswapV2Router02.sol';

contract UniswapPoker is Script {
  ISystemCoin public systemCoin;
  IUniswapV2Router02 public uniswapV2Router02;
  address public deployer;
  uint256 public _deployerPk;
  MintableERC20 public usdc;

  address[] public usdcZaiPath;
  address[] public zaiUsdcPath;

  function run() public {

    _deployerPk = uint256(vm.envBytes32('SEPOLIA_DEPLOYER_PK'));
    deployer = vm.addr(_deployerPk);
    vm.startBroadcast(deployer);

    systemCoin = ISystemCoin(vm.envAddress('SYSTEM_COIN'));
    uniswapV2Router02 = IUniswapV2Router02(vm.envAddress('UNISWAP_V2_ROUTER_02'));
    usdc = MintableERC20(vm.envAddress('USDC'));

    usdcZaiPath.push(address(usdc));
    usdcZaiPath.push(address(systemCoin));
    zaiUsdcPath.push(address(systemCoin));
    zaiUsdcPath.push(address(usdc));

    usdc.mint(deployer, 1_000_000 ether);

    usdc.approve(address(uniswapV2Router02), 500_000 ether);
    systemCoin.approve(address(uniswapV2Router02), 500_000 ether);

    console2.logUint(systemCoin.balanceOf(deployer));

    uniswapV2Router02.swapExactTokensForTokens(
      10_000 ether, 8_000 ether, zaiUsdcPath, deployer, block.timestamp + 1 days
    );

    vm.stopBroadcast();
  }
  // forge script script/UniswapPoker.s.sol:UniswapPoker -f sepolia --broadcast --verify -vvvvv --private-key
}
