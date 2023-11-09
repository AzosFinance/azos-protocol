// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {Script} from 'forge-std/Script.sol';
import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';
import {StabilityModule} from "@src/StabilityModule.sol";
import {UniswapV2Adapter} from "@src/UniswapV2Adapter.sol";
import {MintableERC20} from '@contracts/for-test/MintableERC20.sol';

contract StabilityModuleDeploy is Script {

    SystemCoin public systemCoin;
    address public deployer;
    uint256 public _deployerPk;
    MintableERC20 public usdc;
    StabilityModule public stabilityModule;
    UniswapV2Adapter public uniswapV2Adapter;
    bytes32 public constant USDC = bytes32("USDC");

    function setUp() public virtual {
        _deployerPk = uint256(vm.envBytes32("SEPOLIA_DEPLOYER_PK"));
        deployer = vm.addr(_deployerPk);
        vm.startBroadcast(deployer);
        systemCoin = SystemCoin(vm.envAddress("SYSTEM_COIN"));
    }

    function run() public {

        uniswapV2Adapter = new UniswapV2Adapter();

        usdc = new MintableERC20("USDC", "USDC", 18);

        stabilityModule = new StabilityModule(address(usdc), address(uniswapV2Adapter), USDC, msg.sender, address(systemCoin), msg.sender, 1_000_000 ether, 10_000_000 ether, 1_000);
        usdc.mint(deployer, 2_000_000 ether);

        systemCoin.addAuthorization(address(stabilityModule));
        stabilityModule.deposit(1_000_000 ether);

        vm.stopBroadcast();
    }
    // forge script script/StabilityModuleDeploy.s.sol:StabilityModuleDeploy -f sepolia --broadcast -vvvvv --private-key
}