// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@azos/MOMRegistry.sol";
import {ProtocolToken} from '@contracts/tokens/ProtocolToken.sol';
import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';

contract MOMRegistryTest is Test {
	MOMRegistry public registry;
	SystemCoin public systemCoin;
	ProtocolToken public protocolToken;
	address public governor;
	address public module1;
	address public module2;
	
	function setUp() public {
		governor = address(this);
		module1 = address(this);
		module2 = address(0x2);
		
		// Deploy actual contracts
		systemCoin = new SystemCoin("Zai Test", "ZAI");
		protocolToken = new ProtocolToken("Azos Test", "AZOS");
		
		// Deploy MOMRegistry
		registry = new MOMRegistry(
			address(systemCoin),
			address(protocolToken),
			address(0), // We're not using OracleRelayer
			governor
		);
		
		vm.mockCall(
			address(0),
			abi.encodeWithSignature("redemptionPrice()"),
			abi.encode(1e27) // 1 RAY
		);
		
		// Authorize registry on tokens
		systemCoin.addAuthorization(address(registry));
		protocolToken.addAuthorization(address(registry));
		protocolToken.unpause();
		
	}
	
	function testRegisterMOM() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		(uint256 pIssuance, uint256 cIssuance, uint256 pLimit, uint256 cLimit) = registry.getModuleData(module1);
		assertEq(pIssuance, 0);
		assertEq(cIssuance, 0);
		assertEq(pLimit, protocolLimit);
		assertEq(cLimit, coinLimit);
		assertTrue(registry.isMOM(module1));
	}
	
	function testAdjustMOM() public {
		uint256 initialProtocolLimit = 1000 * 1e18;
		uint256 initialCoinLimit = 2000 * 1e18;
		registry.registerMOM(module1, initialProtocolLimit, initialCoinLimit, true);
		
		// Mint some tokens first
		vm.startPrank(module1);
		registry.mintProtocolToken(300 * 1e18);
		registry.mintCoin(500 * 1e18);
		vm.stopPrank();
		
		// Now adjust the limits to be exactly equal to the current issuances
		uint256 newProtocolLimit = 300 * 1e18;
		uint256 newCoinLimit = 500 * 1e18;
		registry.adjustMOM(module1, newProtocolLimit, newCoinLimit);
		
		(uint256 pIssuance, uint256 cIssuance, uint256 pLimit, uint256 cLimit) = registry.getModuleData(module1);
		assertEq(pIssuance, 300 * 1e18);
		assertEq(cIssuance, 500 * 1e18);
		assertEq(pLimit, newProtocolLimit);
		assertEq(cLimit, newCoinLimit);
	}
	
	function testMintProtocolToken() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.prank(module1);
		registry.mintProtocolToken(500 * 1e18);
		
		(uint256 pIssuance,,, ) = registry.getModuleData(module1);
		assertEq(pIssuance, 500 * 1e18);
		assertEq(protocolToken.balanceOf(module1), 500 * 1e18);
	}
	
	function testBurnProtocolToken() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.startPrank(module1);
		registry.mintProtocolToken(500 * 1e18);
		protocolToken.approve(address(registry), 500 * 1e18);
		registry.burnProtocolToken(500 * 1e18);
		vm.stopPrank();
		
		(uint256 pIssuance,,, ) = registry.getModuleData(module1);
		assertEq(pIssuance, 0);
		assertEq(protocolToken.balanceOf(module1), 0);
	}
	
	function testMintCoin() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.prank(module1);
		registry.mintCoin(1000 * 1e18);
		
		(, uint256 cIssuance,, ) = registry.getModuleData(module1);
		assertEq(cIssuance, 1000 * 1e18);
		assertEq(systemCoin.balanceOf(module1), 1000 * 1e18);
	}
	
	function testBurnCoin() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.startPrank(module1);
		registry.mintCoin(1000 * 1e18);
		systemCoin.approve(address(registry), 1000 * 1e18);
		registry.burnCoin(1000 * 1e18);
		vm.stopPrank();
		
		(, uint256 cIssuance,, ) = registry.getModuleData(module1);
		assertEq(cIssuance, 0);
		assertEq(systemCoin.balanceOf(module1), 0);
	}
	
	function testMintProtocolTokenOverLimit() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.prank(module1);
		registry.mintProtocolToken(500 * 1e18);
		
		vm.expectRevert(IMOMRegistry.ProtocolMint.selector);
		vm.prank(module1);
		registry.mintProtocolToken(501 * 1e18);
	}
	
	function testMintCoinOverLimit() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.prank(module1);
		registry.mintCoin(1500 * 1e18);
		
		vm.expectRevert(IMOMRegistry.CoinLimit.selector);
		vm.prank(module1);
		registry.mintCoin(501 * 1e18);
	}
	
	function testUnauthorizedModuleMintProtocolToken() public {
		vm.expectRevert(IMOMRegistry.NotMOM.selector);
		vm.prank(address(0x9999));
		registry.mintProtocolToken(100 * 1e18);
	}
	
	function testUnauthorizedModuleMintCoin() public {
		vm.expectRevert(IMOMRegistry.NotMOM.selector);
		vm.prank(address(0x9999));
		registry.mintCoin(100 * 1e18);
	}
	
	function testAdjustMOMBelowIssuance() public {
		uint256 protocolLimit = 1000 * 1e18;
		uint256 coinLimit = 2000 * 1e18;
		registry.registerMOM(module1, protocolLimit, coinLimit, true);
		
		vm.prank(module1);
		registry.mintProtocolToken(500 * 1e18);
		
		vm.expectRevert(IMOMRegistry.InvalidLimit.selector);
		registry.adjustMOM(module1, 400 * 1e18, coinLimit);
	}
	
	function testRegisterMOMWithZeroLimit() public {
		vm.expectRevert(IMOMRegistry.InvalidLimit.selector);
		registry.registerMOM(module1, 0, 1000 * 1e18, true);
		
		vm.expectRevert(IMOMRegistry.InvalidLimit.selector);
		registry.registerMOM(module1, 1000 * 1e18, 0, true);
	}
	
	function testRegisterMOMWithZeroAddress() public {
		vm.expectRevert(IMOMRegistry.InvalidModule.selector);
		registry.registerMOM(address(0), 1000 * 1e18, 1000 * 1e18, true);
	}
	
	function testExecute() public {
		address[] memory tos = new address[](1);
		tos[0] = address(systemCoin);
		
		uint256[] memory values = new uint256[](1);
		values[0] = 0;
		
		bytes[] memory datas = new bytes[](1);
		datas[0] = abi.encodeWithSignature("balanceOf(address)", address(this));
		
		(bool[] memory successes, bytes[] memory results) = registry.execute(tos, values, datas);
		
		assertTrue(successes[0]);
		assertEq(abi.decode(results[0], (uint256)), 0);
	}
}
