// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Script, console2} from 'forge-std/Script.sol';
import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {StabilityModule} from '@src/StabilityModule.sol';
import {UniswapV2Adapter} from '@src/UniswapV2Adapter.sol';
import {MintableERC20} from '@contracts/for-test/MintableERC20.sol';
import {IUniswapV2Router02} from '@router/IUniswapV2Router02.sol';

contract StabilityModuleDeploy is Script {
  ISystemCoin public systemCoin;
  IUniswapV2Router02 public uniswapV2Router02;
  address public deployer;
  uint256 public _deployerPk;
  MintableERC20 public usdc;
  StabilityModule public stabilityModule;
  UniswapV2Adapter public uniswapV2Adapter;
  bytes32 public USDC;

  address[] public usdcZaiPath;
  address[] public zaiUsdcPath;

  function run() public {

    _deployerPk = uint256(vm.envBytes32('SEPOLIA_DEPLOYER_PK'));
    deployer = vm.addr(_deployerPk);
    vm.startBroadcast(deployer);

    systemCoin = ISystemCoin(vm.envAddress('SYSTEM_COIN'));
    uniswapV2Router02 = IUniswapV2Router02(vm.envAddress('UNISWAP_V2_ROUTER_02'));
    USDC = bytes32('USDC');

    usdc = MintableERC20(vm.envAddress('USDC'));
    uniswapV2Adapter = new UniswapV2Adapter();

    usdcZaiPath.push(address(usdc));
    usdcZaiPath.push(address(systemCoin));
    zaiUsdcPath.push(address(systemCoin));
    zaiUsdcPath.push(address(usdc));

    stabilityModule = new StabilityModule(
        address(usdc),
        address(uniswapV2Adapter),
        USDC,
        msg.sender,
        address(systemCoin),
        msg.sender,
        2_000_000 ether,
        10_000_000 ether,
        1_000,
        address(uniswapV2Router02));

    console2.log("USDC Address: ");
    console2.logAddress(address(usdc));
    console2.log("Adapter Address: ");
    console2.logAddress(address(uniswapV2Adapter));
    console2.log("USDC hex: ");
    console2.logBytes32(USDC);
    console2.log("My Address: ");
    console2.logAddress(msg.sender);
    console2.log("System Coin Address: ");
    console2.logAddress(address(systemCoin));
    console2.log("My Address: ");
    console2.logAddress(msg.sender);
    console2.log("uniswapV2Router02: ");
    console2.logAddress(address(uniswapV2Router02));

    systemCoin.addAuthorization(address(stabilityModule));
    usdc.mint(deployer, 2_200_000 ether);

    usdc.approve(address(stabilityModule), 1_100_000 ether);
    stabilityModule.deposit(1_100_000 ether);

    usdc.approve(address(uniswapV2Router02), 1_100_000 ether);
    systemCoin.approve(address(uniswapV2Router02), 1_000_000 ether);
    uniswapV2Router02.addLiquidity(
      address(usdc),
      address(systemCoin),
      1_000_000 ether,
      1_000_000 ether,
      1_000_000 ether,
      1_000_000 ether,
      deployer,
      block.timestamp + 1 days
    );

    uniswapV2Router02.swapExactTokensForTokens(
      100_000 ether, 90_000 ether, usdcZaiPath, deployer, block.timestamp + 1 days
    );

    bytes memory _preData =
      abi.encode(90_000 ether, 90_000 ether, zaiUsdcPath, block.timestamp + 1 days, address(uniswapV2Router02));

    bytes memory data = abi.encodeWithSelector(uniswapV2Adapter.swap.selector, _preData);

    stabilityModule.expandAndBuy(USDC, data, 90_000 ether);

    vm.stopBroadcast();
  }
  // forge script script/StabilityModuleDeploy.s.sol:StabilityModuleDeploy -f sepolia --broadcast --verify -vvvvv --private-key
}
