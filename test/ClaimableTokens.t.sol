// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Test} from 'forge-std/Test.sol';
import {ClaimableERC20} from '../src/contracts/for-test/ClaimableERC20.sol';
import {MultiClaimer} from '../src/contracts/for-test/MultiClaimer.sol';

contract ClaimableTokensTest is Test {
    uint256 constant DECIMALS = 18;
    uint256 constant ONE = 10**DECIMALS;
    uint256 constant HALF = 5 * 10**(DECIMALS-1);  // 0.5
    uint256 constant ONE_POINT_FIVE = 15 * 10**(DECIMALS-1);  // 1.5
    uint256 constant MICRO = 10**12;  // 0.000001

    ClaimableERC20 public token1;
    ClaimableERC20 public token2;
    MultiClaimer public multiClaimer;
    address public user1;
    address public user2;

    function setUp() public {
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        // Deploy tokens with decimal amounts
        token1 = new ClaimableERC20(
            'Test Token 1',
            'TT1',
            18,
            HALF, // 0.5 tokens per claim
            1 hours
        );

        token2 = new ClaimableERC20(
            'Test Token 2',
            'TT2',
            18,
            ONE_POINT_FIVE, // 1.5 tokens per claim
            1 hours
        );

        // Setup MultiClaimer
        address[] memory tokens = new address[](2);
        tokens[0] = address(token1);
        tokens[1] = address(token2);
        multiClaimer = new MultiClaimer(tokens);

        // Set up MultiClaimer permissions
        token1.setMultiClaimer(address(multiClaimer));
        token2.setMultiClaimer(address(multiClaimer));
    }

    function test_ClaimAmounts() public {
        // Check initial balances
        assertEq(token1.balanceOf(user1), 0);
        assertEq(token2.balanceOf(user1), 0);

        // Claim from first token
        vm.prank(user1);
        token1.claim();

        // Verify claimed amount (0.5 tokens)
        assertEq(token1.balanceOf(user1), HALF);

        // Claim from second token
        vm.prank(user1);
        token2.claim();

        // Verify claimed amount (1.5 tokens)
        assertEq(token2.balanceOf(user1), ONE_POINT_FIVE);
    }

    function test_ClaimPeriod() public {
        // First claim
        vm.prank(user1);
        token1.claim();
        assertEq(token1.balanceOf(user1), HALF);

        // Try to claim again immediately (should fail)
        vm.prank(user1);
        vm.expectRevert("Claim period has not elapsed");
        token1.claim();

        // Wait for claim period
        vm.warp(block.timestamp + 1 hours);

        // Claim again (should succeed)
        vm.prank(user1);
        token1.claim();
        assertEq(token1.balanceOf(user1), ONE); // 0.5 + 0.5 = 1.0 tokens
    }

    function test_MultiClaim() public {
        // Verify initial state
        address[] memory claimable = multiClaimer.getClaimableTokens(user1);
        assertEq(claimable.length, 2); // Both tokens should be claimable

        // Perform multi-claim
        vm.prank(user1);
        multiClaimer.claimAll();

        // Verify claims
        assertEq(token1.balanceOf(user1), HALF);
        assertEq(token2.balanceOf(user1), ONE_POINT_FIVE);

        // Verify no tokens are immediately claimable
        claimable = multiClaimer.getClaimableTokens(user1);
        assertEq(claimable.length, 0);

        // Wait for claim period
        vm.warp(block.timestamp + 1 hours);

        // Verify tokens are claimable again
        claimable = multiClaimer.getClaimableTokens(user1);
        assertEq(claimable.length, 2);
    }

    function test_SmallDecimalAmounts() public {
        // Deploy token with very small claim amount
        ClaimableERC20 microToken = new ClaimableERC20(
            'Micro Token',
            'MICRO',
            18,
            MICRO, // 0.000001 tokens per claim
            1 hours
        );

        vm.prank(user1);
        microToken.claim();

        // Verify exact small amount
        assertEq(microToken.balanceOf(user1), MICRO);
    }

    function test_MultipleUsers() public {
        // User 1 claims
        vm.prank(user1);
        token1.claim();
        assertEq(token1.balanceOf(user1), HALF);

        // User 2 claims
        vm.prank(user2);
        token1.claim();
        assertEq(token1.balanceOf(user2), HALF);

        // Verify independent claim periods
        vm.warp(block.timestamp + 1 hours);

        // User 1 claims again
        vm.prank(user1);
        token1.claim();
        assertEq(token1.balanceOf(user1), ONE);

        // User 2 claims again
        vm.prank(user2);
        token1.claim();
        assertEq(token1.balanceOf(user2), ONE);
    }
} 