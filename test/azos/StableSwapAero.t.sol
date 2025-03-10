// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {Test} from 'forge-std/Test.sol';
import {StableSwapAero} from '@azos/stabilityActions/StableSwapAero.sol';
import {MOMRegistry} from '@azos/MOMRegistry.sol';
import {IMOMRegistry} from '@azos/interfaces/IMOMRegistry.sol';
import {MockERC20} from '@mock/MockERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IRouter} from '@azos/interfaces/Aerodrome/IRouter.sol';
import {ProtocolToken} from '@contracts/tokens/ProtocolToken.sol';
import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';

contract StableSwapAeroTest is Test {
    StableSwapAero public stabilityMOM;
    MOMRegistry public registry;
    SystemCoin public systemCoin;
    ProtocolToken public protocolToken;
    MockERC20 public assetToken;
    address public governor;
    address public pauser;
    address public mockRouter;
    address public mockFactory;
    
    uint256 constant INITIAL_DEPOSIT_CAP = 1000000 * 1e18;
    
    function setUp() public {
        governor = address(this);
        pauser = address(0x1);
        mockRouter = address(0x2);
        mockFactory = address(0x3);
        
        // Deploy tokens
        systemCoin = new SystemCoin('AZUSD Test', 'AZUSD');
        protocolToken = new ProtocolToken('Azos Test', 'AZOS');
        assetToken = new MockERC20('Asset Test', 'ASST', 18);
        
        // Deploy MOMRegistry
        registry = new MOMRegistry(
            address(systemCoin),
            address(protocolToken),
            address(0), // oracle relayer not needed for this test
            governor
        );
        
        // Deploy StableSwapAero
        stabilityMOM = new StableSwapAero(
            IRouter(mockRouter),
            mockFactory,
            IMOMRegistry(address(registry)),
            IERC20Metadata(address(assetToken)),
            pauser,
            INITIAL_DEPOSIT_CAP
        );
        
        // Mock redemption price
        vm.mockCall(
            address(0),
            abi.encodeWithSignature('redemptionPrice()'),
            abi.encode(1e27) // 1 RAY
        );
        
        // Authorize registry on tokens
        systemCoin.addAuthorization(address(registry));
        protocolToken.addAuthorization(address(registry));
        
        // Register StabilityMOM in the registry
        registry.registerMOM(address(stabilityMOM), type(uint256).max, type(uint256).max, true);
        
        // Mint tokens for testing
        systemCoin.mint(address(this), 50000000 * 1e18);
        systemCoin.approve(address(stabilityMOM), type(uint256).max);
        
        assetToken.mint(address(this), 50000000 * 1e18);
        assetToken.approve(address(stabilityMOM), type(uint256).max);

        // Set up allowed assets
        address[] memory assets = new address[](2);
        assets[0] = address(assetToken);
        assets[1] = address(systemCoin);
        
        bool[] memory statuses = new bool[](2);
        statuses[0] = true;
        statuses[1] = true;
        
        vm.prank(address(registry));
        stabilityMOM.updateAllowedAssets(assets, statuses);
    }
    
    function testConstructor() public {
        // Check router and factory addresses
        assertEq(address(stabilityMOM.router()), mockRouter, "Router address mismatch");
        assertEq(stabilityMOM.factory(), mockFactory, "Factory address mismatch");
        
        // Check allowed assets
        assertTrue(stabilityMOM.allowedAssets(address(assetToken)), "Asset token should be allowed");
        assertTrue(stabilityMOM.allowedAssets(address(systemCoin)), "System coin should be allowed");
        
        // Check initial equity
        assertEq(stabilityMOM.checkpointEquity(), 0, "Initial equity should be zero");
        
        // Check initial deposit cap
        assertEq(stabilityMOM.getDepositCap(), INITIAL_DEPOSIT_CAP, "Initial deposit cap should be set correctly");
        
        // Check if StabilityMOM is registered in MOMRegistry
        assertTrue(registry.isMOM(address(stabilityMOM)), "StabilityMOM should be registered in MOMRegistry");
    }
    
    function testSwap() public {
        uint256 amountIn = 1000 * 1e18;
        uint256 amountOutMin = 990 * 1e18; // 1% slippage
        
        // Create route
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: address(assetToken),
            to: address(systemCoin),
            stable: true,
            factory: mockFactory
        });
        
        // Create expected output amounts array
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = amountIn;
        amounts[1] = amountOutMin;
        
        // Mock successful swap
        vm.mockCall(
            mockRouter,
            abi.encodeWithSelector(
                IRouter.swapExactTokensForTokens.selector,
                amountIn,
                amountOutMin,
                routes,
                address(stabilityMOM),
                block.timestamp
            ),
            abi.encode(amounts)
        );
        
        // Encode swap data
        bytes memory swapData = abi.encode(
            amountIn,
            amountOutMin,
            routes,
            block.timestamp
        );
        
        // Perform swap through StabilityMOM
        vm.prank(address(registry));
        bool success = stabilityMOM.action(swapData);
        
        assertTrue(success, "Swap should succeed");
    }
    
    function testInvalidRoute() public {
        uint256 amountIn = 1000 * 1e18;
        uint256 amountOutMin = 990 * 1e18;
        
        // Create invalid route (wrong factory)
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: address(assetToken),
            to: address(systemCoin),
            stable: true,
            factory: address(0x9999) // Invalid factory
        });
        
        bytes memory swapData = abi.encode(
            amountIn,
            amountOutMin,
            routes,
            block.timestamp
        );
        
        // Should revert with invalid route
        vm.prank(address(registry));
        vm.expectRevert(abi.encodeWithSignature("InvalidRoute()"));
        stabilityMOM.action(swapData);
    }
    
    function testUnallowedAsset() public {
        MockERC20 unallowedToken = new MockERC20('Unallowed', 'NOPE', 18);
        
        uint256 amountIn = 1000 * 1e18;
        uint256 amountOutMin = 990 * 1e18;
        
        // Create route with unallowed token
        IRouter.Route[] memory routes = new IRouter.Route[](1);
        routes[0] = IRouter.Route({
            from: address(unallowedToken),
            to: address(systemCoin),
            stable: true,
            factory: mockFactory
        });
        
        bytes memory swapData = abi.encode(
            amountIn,
            amountOutMin,
            routes,
            block.timestamp
        );
        
        // Should revert with asset not allowed
        vm.prank(address(registry));
        vm.expectRevert(abi.encodeWithSignature("AssetNotAllowed()"));
        stabilityMOM.action(swapData);
    }
} 