// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import 'forge-std/Test.sol';
import '../../src/contracts/for-test/ClaimableERC20.sol';

contract ClaimableERC20Test is Test {
	ClaimableERC20 public token;
	address public deployer = address(0x1);
	address public alice = address(0x2);
	address public bob = address(0x3);
	uint8 public constant DECIMALS = 18;
	uint256 public constant CLAIM_AMOUNT = 10 ether;
	uint256 public constant CLAIM_PERIOD = 13 hours;
	uint256 public constant INITIAL_MINT_AMOUNT = 2_000_000 ether;
	
	function setUp() public {
		vm.prank(deployer);
		token = new ClaimableERC20('Claimable Token', 'CLM', DECIMALS, CLAIM_AMOUNT, CLAIM_PERIOD);
		vm.label(deployer, 'Deployer');
		vm.label(alice, 'Alice');
		vm.label(bob, 'Bob');
	}
	
	function testInitialState() public {
		assertEq(token.name(), 'Claimable Token');
		assertEq(token.symbol(), 'CLM');
		assertEq(token.decimals(), DECIMALS);
		assertEq(token.claimAmount(), CLAIM_AMOUNT);
		assertEq(token.claimPeriod(), CLAIM_PERIOD);
		assertEq(token.balanceOf(deployer), INITIAL_MINT_AMOUNT);
	}
	
	function testInitialMint() public {
		assertEq(token.balanceOf(deployer), INITIAL_MINT_AMOUNT);
		assertEq(token.totalSupply(), INITIAL_MINT_AMOUNT);
	}
	
	function testCanClaimInitially() public {
		assertTrue(token.canClaim(alice));
		assertTrue(token.canClaim(bob));
	}
	
	function testClaim() public {
		vm.prank(alice);
		token.claim();
		
		assertEq(token.balanceOf(alice), CLAIM_AMOUNT);
		assertEq(token.lastClaimTimestamp(alice), block.timestamp);
		assertEq(token.totalSupply(), (INITIAL_MINT_AMOUNT + CLAIM_AMOUNT));
	}
	
	function testCannotClaimTwice() public {
		vm.startPrank(alice);
		
		token.claim();
		assertFalse(token.canClaim(alice));
		vm.expectRevert('Claim period has not elapsed');
		token.claim();
		
		vm.stopPrank();
	}
	
	function testCanClaimAfterPeriod() public {
		vm.startPrank(alice);
		
		token.claim();
		assertFalse(token.canClaim(alice));
		
		vm.warp(block.timestamp + CLAIM_PERIOD);
		assertTrue(token.canClaim(alice));
		token.claim();
		
		assertEq(token.balanceOf(alice), 2 * CLAIM_AMOUNT);
		
		vm.stopPrank();
	}
	
	function testGetTimeUntilNextClaim() public {
		assertEq(token.getTimeUntilNextClaim(alice), 0);
		
		vm.prank(alice);
		token.claim();
		
		assertEq(token.getTimeUntilNextClaim(alice), CLAIM_PERIOD);
		
		vm.warp(block.timestamp + CLAIM_PERIOD - 1 hours);
		assertEq(token.getTimeUntilNextClaim(alice), 1 hours);
		
		vm.warp(block.timestamp + 2 hours);
		assertEq(token.getTimeUntilNextClaim(alice), 0);
	}
	
	function testMultipleUsersClaim() public {
		vm.prank(alice);
		token.claim();
		
		vm.prank(bob);
		token.claim();
		
		assertEq(token.balanceOf(alice), CLAIM_AMOUNT);
		assertEq(token.balanceOf(bob), CLAIM_AMOUNT);
		
		vm.warp(block.timestamp + CLAIM_PERIOD);
		
		vm.prank(alice);
		token.claim();
		
		assertEq(token.balanceOf(alice), 2 * CLAIM_AMOUNT);
		assertEq(token.balanceOf(bob), CLAIM_AMOUNT);
	}
	
	function testTotalSupplyAfterClaims() public {
		uint256 initialSupply = token.totalSupply();
		
		vm.prank(alice);
		token.claim();
		
		vm.prank(bob);
		token.claim();
		
		assertEq(token.totalSupply(), initialSupply + 2 * CLAIM_AMOUNT);
	}
}
