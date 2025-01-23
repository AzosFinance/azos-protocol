// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from 'forge-std/Test.sol';
import {FertilityMOM} from '@azos/FertilityMOM.sol';
import {MOMRegistry} from '@azos/MOMRegistry.sol';
import {IMOMRegistry} from '@azos/interfaces/IMOMRegistry.sol';
import {MockERC20} from '@mock/MockERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {ProtocolToken} from '@contracts/tokens/ProtocolToken.sol';
import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';
import {IFertilityMOM} from '@azos/interfaces/IFertilityMOM.sol';

contract FertilityMOMTest is Test {
    // --- Events to test ---
    event Deposit(address indexed token, uint256 amount, uint256 zaiMinted, address indexed actor);
    event TreasuryWithdraw(address indexed token, uint256 amount, address indexed actor);
    event TreasuryUpdated(address indexed newTreasury, address indexed actor);
    event AllowedAssetsUpdated(address indexed asset, bool status, address indexed actor);
    event DepositCapUpdated(uint256 newCap, address indexed actor);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed actor);
    event AssetPaused(address indexed asset);
    event MinDepositAmountUpdated(uint256 amount);

    FertilityMOM public fertilityMOM;
    MOMRegistry public registry;
    SystemCoin public systemCoin;
    ProtocolToken public protocolToken;
    MockERC20 public stabilityToken;
    address public governor;
    address public pauser;
    address public treasury;
    address public user;
    
    uint256 constant INITIAL_DEPOSIT_CAP = 1000000 * 1e18;
    
    function setUp() public {
        governor = address(this);
        pauser = makeAddr("pauser");
        treasury = makeAddr("treasury");
        user = makeAddr("user");
        
        // Deploy tokens
        systemCoin = new SystemCoin('Zai Test', 'ZAI');
        protocolToken = new ProtocolToken('Azos Test', 'AZOS');
        stabilityToken = new MockERC20('Stability Token', 'STAB', 18);
        
        // Deploy MOMRegistry
        registry = new MOMRegistry(
            address(systemCoin),
            address(protocolToken),
            address(0), // oracle relayer not needed for this test
            governor
        );
        
        fertilityMOM = new FertilityMOM(
            IMOMRegistry(address(registry)),
            IERC20Metadata(address(stabilityToken)),
            treasury,
            pauser,
            INITIAL_DEPOSIT_CAP
        );
        
        // Authorize registry on tokens
        systemCoin.addAuthorization(address(registry));
        protocolToken.addAuthorization(address(registry));
        
        // Authorize FertilityMOM to mint SystemCoin
        systemCoin.addAuthorization(address(fertilityMOM));
        
        // Register FertilityMOM in the registry
        registry.registerMOM(address(fertilityMOM), type(uint256).max, type(uint256).max, true);
        
        // Add authorization through registry for test contract
        vm.prank(address(registry));
        fertilityMOM.addAuthorization(address(this));
    }

    // --- Constructor Tests ---
    function testConstructorSuccess() public {
        assertEq(address(fertilityMOM.treasury()), treasury);
        assertTrue(fertilityMOM.allowedAssets(address(stabilityToken)));
        assertEq(fertilityMOM.getDepositCap(), INITIAL_DEPOSIT_CAP);
    }

    function testConstructorZeroTreasury() public {
        vm.expectRevert(IFertilityMOM.InvalidTreasury.selector);
        new FertilityMOM(
            IMOMRegistry(address(registry)),
            IERC20Metadata(address(stabilityToken)),
            address(0),
            pauser,
            INITIAL_DEPOSIT_CAP
        );
    }

    function testConstructorZeroAsset() public {
        vm.expectRevert(IFertilityMOM.InvalidAmount.selector);
        new FertilityMOM(
            IMOMRegistry(address(registry)),
            IERC20Metadata(address(0)),
            treasury,
            pauser,
            INITIAL_DEPOSIT_CAP
        );
    }

    function testConstructorZeroCap() public {
        vm.expectRevert(IFertilityMOM.InvalidAmount.selector);
        new FertilityMOM(
            IMOMRegistry(address(registry)),
            IERC20Metadata(address(stabilityToken)),
            treasury,
            pauser,
            0
        );
    }

    // --- Deposit Tests ---
    function testDepositSuccess() public {
        uint256 amount = 1000 * 1e18;
        _setupUserWithTokens(amount);
        vm.prank(user);
        stabilityToken.approve(address(registry), amount);
        vm.startPrank(address(registry));
        vm.expectEmit(true, false, false, true);
        emit Deposit(address(stabilityToken), amount, amount, user);
        bytes memory data = abi.encode(
            address(stabilityToken),
            amount,
            user
        );
        fertilityMOM.action(data);
        vm.stopPrank();
        assertEq(systemCoin.balanceOf(user), amount);
        assertEq(stabilityToken.balanceOf(address(fertilityMOM)), amount);
        assertEq(fertilityMOM.getDeposited(), amount);
    }

    function testDepositUnallowedToken() public {
        MockERC20 unallowedToken = new MockERC20('Unallowed', 'NOPE', 18);
        uint256 depositAmount = 1000 * 1e18;
        
        vm.startPrank(address(registry));
        bytes memory depositData = abi.encode(
            address(unallowedToken),
            depositAmount,
            user
        );
        
        vm.expectRevert(IFertilityMOM.AssetNotAllowed.selector);
        fertilityMOM.action(depositData);
        vm.stopPrank();
    }

    function testDepositExceedsCap() public {
        uint256 depositAmount = INITIAL_DEPOSIT_CAP + 1;
        _setupUserWithTokens(depositAmount);
        
        vm.startPrank(address(registry));
        bytes memory depositData = abi.encode(
            address(stabilityToken),
            depositAmount,
            user
        );
        
        vm.expectRevert(IFertilityMOM.DepositCapExceeded.selector);
        fertilityMOM.action(depositData);
        vm.stopPrank();
    }

    function testDepositZeroAmount() public {
        vm.startPrank(address(registry));
        bytes memory depositData = abi.encode(
            address(stabilityToken),
            0,
            user
        );
        
        vm.expectRevert(IFertilityMOM.InvalidAmount.selector);
        fertilityMOM.action(depositData);
        vm.stopPrank();
    }

    function testDepositWithInvalidDecimals() public {
        // Deploy token with different decimals
        MockERC20 token6Dec = new MockERC20("6Dec", "SIX", 6);
        // Test deposit with decimal mismatch
    }

    // --- Treasury Operations Tests ---
    function testWithdrawToTreasurySuccess() public {
        uint256 amount = 1000 * 1e18;
        _setupUserWithTokens(amount);
        
        // First deposit
        vm.prank(address(registry));
        bytes memory depositData = abi.encode(
            address(stabilityToken),
            amount,
            true
        );
        fertilityMOM.action(depositData);
        
        vm.startPrank(address(this));
        // Then withdraw to treasury
        vm.expectEmit(true, false, false, true);
        emit TreasuryWithdraw(address(stabilityToken), amount, address(this));
        
        fertilityMOM.withdrawToTreasury(address(stabilityToken), amount);
        vm.stopPrank();
        
        assertEq(stabilityToken.balanceOf(treasury), amount);
    }

    function testWithdrawToTreasuryUnallowedToken() public {
        vm.expectRevert(IFertilityMOM.AssetNotAllowed.selector);
        fertilityMOM.withdrawToTreasury(address(0x123), 1000);
    }

    function testWithdrawToTreasuryInsufficientBalance() public {
        vm.expectRevert(IFertilityMOM.InsufficientBalance.selector);
        fertilityMOM.withdrawToTreasury(address(stabilityToken), 1000);
    }

    // --- Administration Tests ---
    function testUpdateTreasurySuccess() public {
        address newTreasury = makeAddr("newTreasury");
        
        vm.expectEmit(true, false, false, true);
        emit TreasuryUpdated(newTreasury, address(this));
        
        fertilityMOM.updateTreasury(newTreasury);
        assertEq(fertilityMOM.treasury(), newTreasury);
    }

    function testUpdateTreasuryZeroAddress() public {
        vm.expectRevert(IFertilityMOM.InvalidTreasury.selector);
        fertilityMOM.updateTreasury(address(0));
    }

    function testUpdateAllowedAssetsSuccess() public {
        address[] memory assets = new address[](1);
        bool[] memory statuses = new bool[](1);
        assets[0] = makeAddr("newToken");
        statuses[0] = true;
        
        vm.expectEmit(true, false, false, true, address(fertilityMOM));
        emit AllowedAssetsUpdated(assets[0], true, address(this));
        
        fertilityMOM.updateAllowedAssets(assets, statuses);
        assertTrue(fertilityMOM.allowedAssets(assets[0]));
    }

    function testUpdateAllowedAssetsArrayMismatch() public {
        address[] memory assets = new address[](2);
        bool[] memory statuses = new bool[](1);
        
        vm.expectRevert(IFertilityMOM.ArrayLengthMismatch.selector);
        fertilityMOM.updateAllowedAssets(assets, statuses);
    }

    function testUpdateDepositCapSuccess() public {
        uint256 newCap = 2000000 * 1e18;
        
        vm.expectEmit(true, false, false, true);
        emit DepositCapUpdated(newCap, address(this));
        
        fertilityMOM.updateDepositCap(newCap);
        assertEq(fertilityMOM.getDepositCap(), newCap);
    }

    function testUpdateDepositCapZero() public {
        vm.expectRevert(IFertilityMOM.InvalidAmount.selector);
        fertilityMOM.updateDepositCap(0);
    }

    // --- Helper Functions ---
    function _setupUserWithTokens(uint256 amount) internal {
        // Mint tokens to user and registry
        stabilityToken.mint(user, amount);
        stabilityToken.mint(address(registry), amount);
        
        // User approvals
        vm.startPrank(user);
        stabilityToken.approve(address(registry), amount);
        systemCoin.approve(address(registry), amount);
        vm.stopPrank();
        
        // Registry approvals
        vm.startPrank(address(registry));
        stabilityToken.approve(address(fertilityMOM), amount);
        systemCoin.approve(address(fertilityMOM), amount);
        vm.stopPrank();
    }

    function testEmergencyWithdraw() public {
        uint256 amount = 1000 * 1e18;
        _setupUserWithTokens(amount);
        vm.startPrank(address(registry));
        bytes memory depositData = abi.encode(
            address(stabilityToken),
            amount,
            user
        );
        fertilityMOM.action(depositData);
        vm.stopPrank();

        vm.startPrank(address(this));
        fertilityMOM.pause();  // Need to pause first
        vm.expectEmit(true, false, false, true);
        emit EmergencyWithdraw(address(stabilityToken), amount, address(this));
        fertilityMOM.emergencyWithdraw(address(stabilityToken), amount);
        vm.stopPrank();
    }

    function testConcurrentDeposits() public {
        address user1 = makeAddr("user1");
        address user2 = makeAddr("user2");
        uint256 amount = 1000 * 1e18;
        
        // Setup both users with tokens
        stabilityToken.mint(user1, amount);
        stabilityToken.mint(user2, amount);
        stabilityToken.mint(address(registry), amount * 2);  // Registry needs enough for both users
        
        vm.startPrank(user1);
        stabilityToken.approve(address(registry), amount);
        systemCoin.approve(address(registry), amount);
        vm.stopPrank();
        
        vm.startPrank(user2);
        stabilityToken.approve(address(registry), amount);
        systemCoin.approve(address(registry), amount);
        vm.stopPrank();
        
        // Registry approvals
        vm.startPrank(address(registry));
        stabilityToken.approve(address(fertilityMOM), amount * 2);
        systemCoin.approve(address(fertilityMOM), amount * 2);
        vm.stopPrank();
        
        // User1 deposits
        vm.prank(address(registry));
        bytes memory depositData1 = abi.encode(
            address(stabilityToken),
            amount,
            user1
        );
        fertilityMOM.action(depositData1);
        
        // User2 deposits
        vm.prank(address(registry));
        bytes memory depositData2 = abi.encode(
            address(stabilityToken),
            amount,
            user2
        );
        fertilityMOM.action(depositData2);
        
        // Verify total deposits
        assertEq(fertilityMOM.getDeposited(), 2 * amount);
        assertEq(systemCoin.balanceOf(user2), amount);
        assertEq(systemCoin.balanceOf(user1), amount);
    }
} 