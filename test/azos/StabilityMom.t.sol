// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "@azos/StabilityMOM.sol";
import "@azos/MOMRegistry.sol";
import {MockERC20} from "@mock/MockERC20.sol";
import {MockAction} from "@mock/MockAction.sol";
import {ProtocolToken} from '@contracts/tokens/ProtocolToken.sol';
import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';
import {MockERC20} from "../mocks/MockERC20.sol";

contract StabilityMOMTest is Test {
	StabilityMOM public stabilityMOM;
	MOMRegistry public registry;
	SystemCoin public systemCoin;
	ProtocolToken public protocolToken;
	MockERC20 public assetToken;
	MockAction public mockAction;
	address public governor;
	address public pauser;
	
	uint256 constant INITIAL_DEPOSIT_CAP = 1000000 * 1e18;
	
	function setUp() public {
		governor = address(this);
		pauser = address(0x1);
		
		// Deploy actual contracts
		systemCoin = new SystemCoin("Zai Test", "ZAI");
		protocolToken = new ProtocolToken("Azos Test", "AZOS");
		assetToken = new MockERC20("Asset Test", "ASST", 18);
		
		// Deploy mock logic contract
		mockAction = new MockAction();
		
		// Deploy MOMRegistry
		registry = new MOMRegistry(
			address(systemCoin),
			address(protocolToken),
			address(0), // oracle relayer not needed for this test
			governor
		);
		console2.log(governor);
	
		
		// Deploy StabilityMOM
		stabilityMOM = new StabilityMOM(
			address(mockAction),
			IMOMRegistry(address(registry)),
			IERC20Metadata(address(assetToken)),
			pauser,
			INITIAL_DEPOSIT_CAP
		);
		
		vm.mockCall(
			address(0),
			abi.encodeWithSignature("redemptionPrice()"),
			abi.encode(1e27) // 1 RAY
		);
		
		// Explicitly register the action
		vm.prank(address(registry));
		stabilityMOM.registerAction(address(mockAction));
		
		// Verify that the action is registered
		require(stabilityMOM.isActionRegistered(1), "Action should be registered after setup");
		
		address[] memory assets = new address[](2);
		assets[0] = address(assetToken);
		
		bool[] memory statuses = new bool[](1);
		statuses[0] = true;
		
		// Authorize registry on tokens
		systemCoin.addAuthorization(address(registry));
		protocolToken.addAuthorization(address(registry));
		
		// Register StabilityMOM in the registry
		registry.registerMOM(address(stabilityMOM), type(uint256).max, type(uint256).max, true);
		
		// Mint some tokens for testing
		systemCoin.mint(address(this), 50000000 * 1e18);
		systemCoin.approve(address(stabilityMOM), type(uint256).max);
		systemCoin.approve(address(this), type(uint256).max);
		
		assetToken.mint(address(this), 50000000 * 1e18);
		assetToken.approve(address(stabilityMOM), type(uint256).max);
		assetToken.approve(address(this), type(uint256).max);
	}
	
	function testConstructor() public {
		// Check allowed assets
		assertTrue(stabilityMOM.allowedAssets(address(assetToken)), "Asset token should be allowed");
		assertTrue(stabilityMOM.allowedAssets(address(systemCoin)), "System coin should be allowed");
		
		// Check initial equity
		assertEq(stabilityMOM.checkpointEquity(), 0, "Initial equity should be zero");
		
		// Check initial deposit cap
		assertEq(stabilityMOM.getDepositCap(), INITIAL_DEPOSIT_CAP, "Initial deposit cap should be set correctly");
		
		// Check initial deposited amount
		assertEq(stabilityMOM.getDeposited(), 0, "Initial deposited amount should be zero");
		
		// Check if StabilityMOM is registered in MOMRegistry
		assertTrue(registry.isMOM(address(stabilityMOM)), "StabilityMOM should be registered in MOMRegistry");
		
		// Check initial balances
		assertEq(assetToken.balanceOf(address(stabilityMOM)), 0, "Initial asset token balance should be zero");
		assertEq(systemCoin.balanceOf(address(stabilityMOM)), 0, "Initial system coin balance should be zero");
		
		// Check if the contract is not paused initially
		assertFalse(stabilityMOM.paused(), "Contract should not be paused initially");
	}
	
	function testRaiseDepositCap() public {
		uint256 initialCap = stabilityMOM.getDepositCap();
		uint256 increaseAmount = initialCap; // Double the cap
		uint256 expectedNewCap = initialCap + increaseAmount;
		
		vm.prank(address(registry));
		stabilityMOM.raiseDepositCap(increaseAmount);
		
		assertEq(stabilityMOM.getDepositCap(), expectedNewCap, "Deposit cap not raised correctly");
		
		uint256 depositAmount = initialCap + 1000 * 1e18;
		require(depositAmount < expectedNewCap, "Test deposit amount should be less than new cap but more than initial cap");
		
		uint256 prevAssetBal = assetToken.balanceOf(address(this));
		uint256 prevSystemBal = systemCoin.balanceOf(address(this));
		
		stabilityMOM.receiveLiquidity(depositAmount);
		
		uint256 postAssetBal = assetToken.balanceOf(address(this));
		uint256 postSystemBal = systemCoin.balanceOf(address(this));
		
		assertEq(prevAssetBal - postAssetBal, depositAmount, "Incorrect amount of asset tokens transferred");
		assertEq(assetToken.balanceOf(address(stabilityMOM)), depositAmount, "StabilityMOM did not receive correct amount of asset tokens");
		assertGt(postSystemBal, prevSystemBal, "No system coins were minted");
		
		// Assuming a 1:10 ratio for asset to system coins
		assertEq(postSystemBal - prevSystemBal, depositAmount * 10, "Incorrect amount of system coins minted");
		
		assertLe(stabilityMOM.getDeposited(), expectedNewCap, "Total deposits should not exceed new cap");
	}
	
	function testDelegateAction() public {
		// Ensure the action is registered
		vm.prank(address(registry));
		stabilityMOM.registerAction(address(mockAction));
		
		// Verify the action is registered
		assertTrue(stabilityMOM.isActionRegistered(1), "Action 1 should be registered");
		
		// Now proceed with the delegation
		vm.prank(address(registry));
		
		uint256[] memory actionIds = new uint256[](1);
		actionIds[0] = 1; // The first registered action should have ID 1
		
		bytes[] memory datas = new bytes[](1);
		datas[0] = abi.encode("test action");
		
		bool[] memory results = stabilityMOM.delegateAction(actionIds, datas);
		
		assertTrue(results[0], "Action execution should succeed");
		
	}
	
	function testReceiveLiquidity() public {
		uint256 amount = 1000 * 1e18; // 1e21 asset tokens
		uint256 expectedMintAmount = amount * 10; // 1e22 system coins
		
		uint256 prevSystemThis = systemCoin.balanceOf(address(this));
		uint256 prevAssetThis = assetToken.balanceOf(address(this));
		uint256 prevSystemMOM = systemCoin.balanceOf(address(stabilityMOM));
		uint256 prevAssetMOM = assetToken.balanceOf(address(stabilityMOM));
		
		stabilityMOM.receiveLiquidity(amount);
		
		uint256 postSystemThis = systemCoin.balanceOf(address(this));
		uint256 postAssetThis = assetToken.balanceOf(address(this));
		uint256 postSystemMOM = systemCoin.balanceOf(address(stabilityMOM));
		uint256 postAssetMOM = assetToken.balanceOf(address(stabilityMOM));
		
		// Check this contract's balances
		assertEq(postSystemThis, prevSystemThis + expectedMintAmount, "Incorrect system coin balance for this contract");
		assertEq(postAssetThis, prevAssetThis - amount, "Incorrect asset balance for this contract");
		
		// Check StabilityMOM's balances
		assertEq(postSystemMOM, prevSystemMOM, "StabilityMOM system coin balance should not change");
		assertEq(postAssetMOM, prevAssetMOM + amount, "Incorrect asset balance for StabilityMOM");
		
		// Additional checks
		assertEq(postSystemThis - prevSystemThis, expectedMintAmount, "Minted amount mismatch");
		assertEq(prevAssetThis - postAssetThis, amount, "Transferred asset amount mismatch");
	}
	
	function testUpdateAllowedAssets() public {
		vm.prank(address(registry));
	
		address[] memory assets = new address[](1);
		assets[0] = address(0x123);
		
		bool[] memory statuses = new bool[](1);
		statuses[0] = true;
		
		stabilityMOM.updateAllowedAssets(assets, statuses);
		
		assertTrue(stabilityMOM.allowedAssets(address(0x123)));
	}
}
