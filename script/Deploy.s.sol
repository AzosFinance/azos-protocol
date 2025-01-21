// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Contracts.s.sol';
import '@script/Params.s.sol';
import '@script/Registry.s.sol';

import {Script} from 'forge-std/Script.sol';
import {Common} from '@script/Common.s.sol';
import {TestnetParams} from '@script/TestnetParams.s.sol';
import {MainnetParams} from '@script/MainnetParams.s.sol';
import {ClaimableERC20} from '../src/contracts/for-test/ClaimableERC20.sol';
import {console}     from "forge-std/console.sol";
import {MultiClaimer} from '../src/contracts/for-test/MultiClaimer.sol';
import {DIARelayerV2} from '../src/contracts/oracles/DIARelayerV2.sol';

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

    // Deploy Azos Protocol MOMs
    deployAzosProtocolMOMs(SWAP_ROUTER, AERO_ROUTER);

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
    delegate = 0xd9Bc04Fb848e0bF3EfCFc7e43039cb37F281E4B3; // Deployer EOA Public Key

    // Deploy oracle factories
    denominatedOracleFactory = new DenominatedOracleFactory();
    delayedOracleFactory = new DelayedOracleFactory();

    // First deploy our ClaimableERC20 tokens
    ClaimableERC20 gtcEthToken = new ClaimableERC20(
        'Gitcoin Ethereum',
        'GTC-ETH',
        18,
        0.5 ether, // claim amount
        24 hours // claim period
    );

    ClaimableERC20 klimaToken = new ClaimableERC20(
        'Klima DAO',
        'KLIMA',
        18,
        1555 ether, // claim amount
        24 hours // claim period
    );

    ClaimableERC20 celoToken = new ClaimableERC20(
        'Celo',
        'CELO',
        18,
        1616 ether, // claim amount
        24 hours // claim period
    );

    ClaimableERC20 usdgloToken = new ClaimableERC20(
        'Glo Dollar',
        'USDGLO',
        18,
        1000 ether, // claim amount
        24 hours // claim period
    );

    ClaimableERC20 charToken = new ClaimableERC20(
        'Biochar Credits',
        'CHAR',
        18,
        7 ether, // claim amount
        24 hours // claim period
    );

    // Update collateral mappings with our newly deployed tokens
    collateral[GTC_ETH] = IERC20Metadata(address(gtcEthToken));
    collateral[KLIMA] = IERC20Metadata(address(klimaToken));
    collateral[CELO] = IERC20Metadata(address(celoToken));
    collateral[USDGLO] = IERC20Metadata(address(usdgloToken));
    collateral[CHAR] = IERC20Metadata(address(charToken));

        // Clear any delegatee mappings since these tokens don't support delegation
    delegatee[GTC_ETH] = address(0);
    delegatee[KLIMA] = address(0);
    delegatee[CELO] = address(0);
    delegatee[USDGLO] = address(0);
    delegatee[CHAR] = address(0);

    // Deploy MultiClaimer for easy claiming of all tokens
    address[] memory tokenAddresses = new address[](5);
    tokenAddresses[0] = address(gtcEthToken);
    tokenAddresses[1] = address(klimaToken);
    tokenAddresses[2] = address(celoToken);
    tokenAddresses[3] = address(usdgloToken);
    tokenAddresses[4] = address(charToken);
    
    MultiClaimer multiClaimer = new MultiClaimer(tokenAddresses);

      // Setup oracle system with DIA Oracle V2
    address diaOracleV2 = 0x83b56E80e47698BBc0d97828C1d8b1D509Ab6B4b;
    
    // Create base price feeds
    IBaseOracle _ethUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'ETH/USD',
        1 hours
    );

    IBaseOracle _daiUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'DAI/USD',
        1 hours
    );

    IBaseOracle _klimaUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'KLIMA/USD',
        1 hours
    );

    IBaseOracle _celoUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'CELO/USD',
        1 hours
    );


    // For USDGLO, we'll use the DAI price as a reference
    IBaseOracle _usdgloUsdOracle = _daiUsdOracle; // Using DAI price for USDGLO

    // Deploy delayed oracles for each token
    delayedOracle[GTC_ETH] = delayedOracleFactory.deployDelayedOracle(_ethUsdOracle, 1 hours);
    delayedOracle[KLIMA] = delayedOracleFactory.deployDelayedOracle(_klimaUsdOracle, 1 hours);
    delayedOracle[CELO] = delayedOracleFactory.deployDelayedOracle(_celoUsdOracle, 1 hours);
    delayedOracle[USDGLO] = delayedOracleFactory.deployDelayedOracle(_usdgloUsdOracle, 1 hours);
    delayedOracle[CHAR] = delayedOracleFactory.deployDelayedOracle(_celoUsdOracle, 1 hours); // Using CELO price for CHAR temporarily

  // Setup collateral types
    collateralTypes.push(GTC_ETH);
    collateralTypes.push(CHAR);
    collateralTypes.push(KLIMA);
    collateralTypes.push(USDGLO);
    collateralTypes.push(CELO);

    systemCoinOracle = new HardcodedOracle('ZAI / USD', ZAI_USD_INITIAL_PRICE); // 1 ZAI = 1 USD

    
  }

  function setupPostEnvironment() public virtual override updateParams {
    // Setup deviated oracle
    systemCoinOracle = new DeviatedOracle({
      _symbol: 'ZAI / USD',
      _oracleRelayer: address(oracleRelayer),
      _deviation: BASE_SEPOLIA_ZAI_PRICE_DEVIATION
    });

    oracleRelayer.modifyParameters('systemCoinOracle', abi.encode(systemCoinOracle));
  }
}
