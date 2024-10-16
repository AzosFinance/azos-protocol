// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Contracts.s.sol';
import '@script/Params.s.sol';
import '@script/Registry.s.sol';

import {Script} from 'forge-std/Script.sol';
import {Common} from '@script/Common.s.sol';
import {TestnetParams} from '@script/TestnetParams.s.sol';
import {MainnetParams} from '@script/MainnetParams.s.sol';
import {ClaimableERC20} from "../src/contracts/for-test/ClaimableERC20.sol";

abstract contract Deploy is Common, Script {
  function setupEnvironment() public virtual {}
  function setupPostEnvironment() public virtual {}

  function run() public {
    deployer = vm.addr(_deployerPk);
    vm.startBroadcast(deployer);

    // Deploy tokens used to setup the environment
    deployTokens();

    // Deploy governance contracts
    deployGovernance();

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

      deployCollateralContracts(_cType);
      _setupCollateral(_cType);
    }

    // Deploy contracts related to the SafeManager usecase
    deployProxyContracts(address(safeEngine));

    // Deploy and setup contracts that rely on deployed environment
    setupPostEnvironment();

    // Deploy Merkle tree claim contract and mint protocol tokens to it
    // deployTokenDistributor();

    if (delegate == address(0)) {
      _revokeDeployerToAll(governor);
    } else if (delegate == deployer) {
      _delegateToAll(governor);
    } else {
      _delegateToAll(delegate);
      _revokeDeployerToAll(governor);
    }

    vm.stopBroadcast();
  }
}

contract DeployMainnet is MainnetParams, Deploy {
  function setUp() public virtual {
    _deployerPk = uint256(vm.envBytes32('OP_MAINNET_DEPLOYER_PK'));
  }

  // #todo setup the oracles and the Uniswap contract addresses
  function setupEnvironment() public virtual override updateParams {
    // Deploy oracle factories
    chainlinkRelayerFactory = new ChainlinkRelayerFactory(OP_CHAINLINK_SEQUENCER_UPTIME_FEED);
    uniV3RelayerFactory = new UniV3RelayerFactory(UNISWAP_V3_FACTORY);
    denominatedOracleFactory = new DenominatedOracleFactory();
    delayedOracleFactory = new DelayedOracleFactory();

    // Setup oracle feeds
    IBaseOracle _ethUSDPriceFeed = chainlinkRelayerFactory.deployChainlinkRelayer(OP_CHAINLINK_ETH_USD_FEED, 1 hours);
    IBaseOracle _wstethETHPriceFeed =
      chainlinkRelayerFactory.deployChainlinkRelayer(OP_CHAINLINK_WSTETH_ETH_FEED, 1 hours);
    IBaseOracle _opUSDPriceFeed = chainlinkRelayerFactory.deployChainlinkRelayer(OP_CHAINLINK_OP_USD_FEED, 1 hours);

    IBaseOracle _wstethUSDPriceFeed = denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _wstethETHPriceFeed,
      _denominationPriceSource: _ethUSDPriceFeed,
      _inverted: false
    });

    delayedOracle[WETH] = delayedOracleFactory.deployDelayedOracle(_ethUSDPriceFeed, 1 hours);
    delayedOracle[WSTETH] = delayedOracleFactory.deployDelayedOracle(_wstethUSDPriceFeed, 1 hours);
    delayedOracle[OP] = delayedOracleFactory.deployDelayedOracle(_opUSDPriceFeed, 1 hours);

    collateral[WETH] = IERC20Metadata(OP_WETH);
    collateral[WSTETH] = IERC20Metadata(OP_WSTETH);
    collateral[OP] = IERC20Metadata(OP_OPTIMISM);

    collateralTypes.push(WETH);
    collateralTypes.push(WSTETH);
    collateralTypes.push(OP);

    // NOTE: Deploying the PID Controller turned off until governance action
    systemCoinOracle = new HardcodedOracle('ZAI / USD', ZAI_USD_INITIAL_PRICE); // 1 ZAI = 1 USD
  }

  function setupPostEnvironment() public virtual override updateParams {
    // Deploy ZAI/WETH UniV3 pool (uninitialized)
    IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool({
      tokenA: address(systemCoin),
      tokenB: address(collateral[WETH]),
      fee: ZAI_POOL_FEE_TIER
    });

    // Setup ZAI/WETH oracle feed
    IBaseOracle _zaiWethOracle = uniV3RelayerFactory.deployUniV3Relayer({
      _baseToken: address(systemCoin),
      _quoteToken: address(collateral[WETH]),
      _feeTier: ZAI_POOL_FEE_TIER,
      _quotePeriod: 1 days
    });

    // Setup ZAI/USD oracle feed
    denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _zaiWethOracle,
      _denominationPriceSource: delayedOracle[WETH].priceSource(),
      _inverted: false
    });
  }
}

contract DeployTestnet is TestnetParams, Deploy {
  function setUp() public virtual {
    _deployerPk = uint256(vm.envBytes32('BASE_SEPOLIA_DEPLOYER_PK'));
  }

  function setupEnvironment() public virtual override updateParams {
    delegate = 0xd9Bc04Fb848e0bF3EfCFc7e43039cb37F281E4B3; // EOA

    // Deploy oracle factories
    denominatedOracleFactory = new DenominatedOracleFactory();
    delayedOracleFactory = new DelayedOracleFactory();

    // Setup oracle feeds

    // ZAI
    systemCoinOracle = new HardcodedOracle('ZAI / USD', ZAI_USD_INITIAL_PRICE); // 1 ZAI = 1 USD

    // Test tokens
    collateral[GTC_ETH] = new ClaimableERC20('Gitcoin Ethereum', 'GTCETH', 18, 1);
    collateral[CHAR] = new ClaimableERC20('Biochar Credits', 'CHAR', 18, 16);
    collateral[KLIMA] = new ClaimableERC20('Klima', 'KLIMA', 18, 1500);
    collateral[GLOUSD] = new ClaimableERC20('Glo Dollar', 'GLOUSD', 18, 2300);
    collateral[CELO] = new ClaimableERC20('Celo', 'CELO', 18, 3000);

    // Hardcoded feeds for new collateral tokens
    IBaseOracle _gtcEthUsdOracle = new HardcodedOracle('GTCETH / USD', 2600e18);
    IBaseOracle _charUsdOracle = new HardcodedOracle('CHAR / USD', 168.71e18);
    IBaseOracle _klimaUsdOracle = new HardcodedOracle('KLIMA / USD', 1.67e18);
    IBaseOracle _gloUsdOracle = new HardcodedOracle('GLOUSD / USD', 1e18);
    IBaseOracle _celoUsdOracle = new HardcodedOracle('CELO / USD', 0.78e18);

    // Deploy delayed oracles for new collateral tokens
    delayedOracle[GTC_ETH] = delayedOracleFactory.deployDelayedOracle(_gtcEthUsdOracle, 1 hours);
    delayedOracle[CHAR] = delayedOracleFactory.deployDelayedOracle(_charUsdOracle, 1 hours);
    delayedOracle[KLIMA] = delayedOracleFactory.deployDelayedOracle(_klimaUsdOracle, 1 hours);
    delayedOracle[GLOUSD] = delayedOracleFactory.deployDelayedOracle(_gloUsdOracle, 1 hours);
    delayedOracle[CELO] = delayedOracleFactory.deployDelayedOracle(_celoUsdOracle, 1 hours);

    // Setup collateral types
    collateralTypes.push(GTC_ETH);
    collateralTypes.push(CHAR);
    collateralTypes.push(KLIMA);
    collateralTypes.push(GLOUSD);
    collateralTypes.push(CELO);
  }

  function setupPostEnvironment() public virtual override updateParams {
    // Setup deviated oracle
    systemCoinOracle = new DeviatedOracle({
      _symbol: 'ZAI / USD',
      _oracleRelayer: address(oracleRelayer),
      _deviation: OP_SEPOLIA_ZAI_PRICE_DEVIATION
    });

    oracleRelayer.modifyParameters('systemCoinOracle', abi.encode(systemCoinOracle));
  }
}
