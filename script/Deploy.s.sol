// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import '@script/Contracts.s.sol';
import '@script/Registry.s.sol';
import '@script/Params.s.sol';

import {Script} from 'forge-std/Script.sol';
import {Common} from '@script/Common.s.sol';
import {GoerliParams} from '@script/GoerliParams.s.sol';
import {MainnetParams} from '@script/MainnetParams.s.sol';

abstract contract Deploy is Common, Script {
  function setupEnvironment() public virtual {}
  function setupPostEnvironment() public virtual {}

  function run() public {
    deployer = vm.addr(_deployerPk);
    vm.startBroadcast(deployer);

    // Deploy oracle factories used to setup the environment
    deployOracleFactories();

    // Environment may be different for each network
    setupEnvironment();

    // Common deployment routine for all networks
    deployContracts();
    deployTaxModule();
    _setupContracts();

    deployGlobalSettlement();
    _setupGlobalSettlement();

    // PID Controller contracts
    deployPIDController();
    _setupPIDController();

    // Rewarded Actions contracts
    deployJobContracts();
    _setupJobContracts();

    // Deploy collateral contracts
    for (uint256 _i; _i < collateralTypes.length; _i++) {
      bytes32 _cType = collateralTypes[_i];

      if (_cType == ETH_A) deployEthCollateralContracts();
      else deployCollateralContracts(_cType);
      _setupCollateral(_cType);
    }

    // Deploy contracts related to the SafeManager usecase
    deployProxyContracts(address(safeEngine));

    // Deploy and setup contracts that rely on deployed environment
    setupPostEnvironment();

    if (delegate == address(0)) {
      _revokeAllTo(governor);
    } else if (delegate == deployer) {
      _delegateAllTo(governor);
    } else {
      _delegateAllTo(delegate);
      _revokeAllTo(governor);
    }

    vm.stopBroadcast();
  }
}

contract DeployMainnet is MainnetParams, Deploy {
  function setUp() public virtual {
    _deployerPk = uint256(vm.envBytes32('OP_MAINNET_DEPLOYER_PK'));
    chainId = 10;
  }

  function setupEnvironment() public virtual override updateParams {
    // Setup oracle feeds
    IBaseOracle _ethUSDPriceFeed = chainlinkRelayerFactory.deployChainlinkRelayer(OP_CHAINLINK_ETH_USD_FEED, 1 hours);
    IBaseOracle _wstethETHPriceFeed =
      chainlinkRelayerFactory.deployChainlinkRelayer(OP_CHAINLINK_WSTETH_ETH_FEED, 1 hours);

    IBaseOracle _wstethUSDPriceFeed = denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _wstethETHPriceFeed,
      _denominationPriceSource: _ethUSDPriceFeed,
      _inverted: false
    });

    systemCoinOracle = new HardcodedOracle('HAI / USD', HAI_INITIAL_PRICE); // 1 HAI = 1 USD
    delayedOracle[WETH] = delayedOracleFactory.deployDelayedOracle(_ethUSDPriceFeed, 1 hours);
    delayedOracle[WSTETH] = delayedOracleFactory.deployDelayedOracle(_wstethUSDPriceFeed, 1 hours);

    collateral[WETH] = IERC20Metadata(OP_WETH);
    collateral[WSTETH] = IERC20Metadata(OP_WSTETH);

    collateralTypes.push(WETH);
    collateralTypes.push(WSTETH);
  }

  function setupPostEnvironment() public virtual override updateParams {}
}

contract DeployGoerli is GoerliParams, Deploy {
  function setUp() public virtual {
    _deployerPk = uint256(vm.envBytes32('SEPOLIA_DEPLOYER_PK'));
    chainId = 11_155_111;
  }

  function setupEnvironment() public virtual override updateParams {
    // Setup oracle feeds

    // HAI
    systemCoinOracle = new HardcodedOracle('ZAI / USD', HAI_INITIAL_PRICE); // 1 ZAI = 1 USD

    bytes32 BCT = bytes32('BCT');
    bytes32 FGB = bytes32('FGB');
    bytes32 REI = bytes32('REI');

    // Test tokens
    collateral[BCT] = new MintableERC20('Base Carbon Tonne', 'BCT', 18);
    collateral[FGB] = new MintableERC20('Fungible Green Bond', 'FGB', 18);
    collateral[REI] = new MintableERC20('Renewable Energy Index', 'REI', 18);

    // ETH Live Price Feed
    IBaseOracle _EthUSDPriceFeed =
      chainlinkRelayerFactory.deployChainlinkRelayer(SEPOLIA_CHAINLINK_ETH_USD_FEED, 1 hours); // live feed

    HardcodedOracle _BctEthPriceFeed = new HardcodedOracle('BCT / ETH', SEPOLIA_BCT_ETH_PRICE_FEED); // denominated feed

    IBaseOracle _BctUsdPriceFeed = denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _BctEthPriceFeed,
      _denominationPriceSource: _EthUSDPriceFeed,
      _inverted: false
    });

    // STN: denominated feed (1000 STN = 1 wBTC)
    IBaseOracle _fgbEthOracle = new HardcodedOracle('FGB / ETH', SEPOLIA_FGB_ETH_PRICE_FEED);

    IBaseOracle _fgbUsdOracle = denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _fgbEthOracle,
      _denominationPriceSource: _EthUSDPriceFeed,
      _inverted: false
    });

    IBaseOracle _reiEthOracle = new HardcodedOracle('REI / ETH', SEPOLIA_REI_ETH_PRICE_FEED);

    IBaseOracle _reiOracle = denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _reiEthOracle,
      _denominationPriceSource: _EthUSDPriceFeed,
      _inverted: false
    });

    delayedOracle[WETH] = delayedOracleFactory.deployDelayedOracle(_EthUSDPriceFeed, 1 hours);
    delayedOracle[BCT] = delayedOracleFactory.deployDelayedOracle(_BctUsdPriceFeed, 1 hours);
    delayedOracle[FGB] = delayedOracleFactory.deployDelayedOracle(_fgbUsdOracle, 1 hours);
    delayedOracle[REI] = delayedOracleFactory.deployDelayedOracle(_reiOracle, 1 hours);

    // Setup collateral types
    collateralTypes.push(BCT);
    collateralTypes.push(FGB);
    collateralTypes.push(REI);
  }

  function setupPostEnvironment() public virtual override updateParams {
    // Setup deviated oracle
    systemCoinOracle = new DeviatedOracle({
      _symbol: 'ZAI/USD',
      _oracleRelayer: address(oracleRelayer),
      _deviation: SEPOLIA_ZAI_BCT_PRICE_DEVIATION
    });

    oracleRelayer.modifyParameters('systemCoinOracle', abi.encode(systemCoinOracle));
  }
}

// forge script script/Deploy.s.sol:DeployGoerli -f sepolia --broadcast --verify -vvvvv
