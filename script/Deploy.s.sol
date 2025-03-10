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
import {console2} from 'forge-std/console2.sol';
import {MultiClaimer} from '../src/contracts/for-test/MultiClaimer.sol';
import {DIARelayerV2} from '../src/contracts/oracles/DIARelayerV2.sol';
import {SystemCoinSuperToken} from '../src/contracts/superfluid/SystemCoinSuperToken.sol';
import {ISuperfluid} from '@superfluid-finance/ethereum-contracts/contracts/interfaces/ISuperfluid.sol';

abstract contract Deploy is Common, Script {
  function setupEnvironment() public virtual {}
  function setupPostEnvironment() public virtual {}

  // Add SystemCoin SuperToken
  SystemCoinSuperToken public systemCoinSuperToken;

  function logDeployment(string memory contractName, address contractAddress) internal view {
    // Convert to checksum address
    console2.log(string.concat(contractName, ': ', vm.toString(contractAddress)));
  }

  function run() public {
    deployer = vm.addr(_deployerPk);
    vm.startBroadcast(deployer);

    console2.log('\n=== Core Contracts ===');
    // Deploy tokens used to setup the environment
    deployTokens();
    logDeployment('SystemCoin', address(systemCoin));
    logDeployment('ProtocolToken', address(protocolToken));

    // Deploy governance contracts
    deployGovernance();
    logDeployment('AzosGovernor', address(azosGovernor));
    logDeployment('Timelock', address(timelock));
    logDeployment('AzosDelegatee', address(azosDelegatee));

    console2.log('\n=== Factory Contracts ===');
    // Deploy oracle factories
    denominatedOracleFactory = new DenominatedOracleFactory();
    logDeployment('DenominatedOracleFactory', address(denominatedOracleFactory));
    
    delayedOracleFactory = new DelayedOracleFactory();
    logDeployment('DelayedOracleFactory', address(delayedOracleFactory));

    // Add Superfluid integration if host address is set
    if (address(BASE_SEPOLIA_SUPERFLUID_HOST) != address(0)) {
      console2.log('\n=== Superfluid Integration ===');
      // Deploy SystemCoin SuperToken (AZUSDx)
      systemCoinSuperToken = new SystemCoinSuperToken(address(systemCoin));
      systemCoinSuperToken.initialize('Super AZUSD', 'AZUSDx');
      logDeployment('SystemCoinSuperToken (AZUSDx)', address(systemCoinSuperToken));
    }

    console2.log('\n=== Oracle Contracts ===');
    // Setup oracle system
    address diaOracleV2 = 0x83b56E80e47698BBc0d97828C1d8b1D509Ab6B4b;
    logDeployment('DIA Oracle V2', diaOracleV2);

    // Create base price feeds
    IBaseOracle _ethUsdOracle = new DIARelayerV2(diaOracleV2, 'ETH/USD', 2 hours);
    logDeployment('ETH/USD Oracle', address(_ethUsdOracle));

    // ... similar logging for other oracles ...

    // Create delayed oracles
    delayedOracle[GTC_ETH] = delayedOracleFactory.deployDelayedOracle(_ethUsdOracle, 1 hours);
    logDeployment('GTC_ETH Delayed Oracle', address(delayedOracle[GTC_ETH]));

    // ... similar logging for other delayed oracles ...

    console2.log('\n=== Collateral Contracts ===');
    for (uint256 _i; _i < collateralTypes.length; _i++) {
        bytes32 _cType = collateralTypes[_i];
        logDeployment(
            string.concat(string(abi.encodePacked(_cType)), ' CollateralJoin'),
            address(collateralJoin[_cType])
        );
        logDeployment(
            string.concat(string(abi.encodePacked(_cType)), ' CollateralAuctionHouse'),
            address(collateralAuctionHouse[_cType])
        );
    }

    console2.log('\n=== Job Contracts ===');
    logDeployment('AccountingJob', address(accountingJob));
    logDeployment('LiquidationJob', address(liquidationJob));
    logDeployment('OracleJob', address(oracleJob));

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
      console2.log('Deployed collateral contract for ', string(abi.encodePacked(_cType)));
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

    // Final deployment summary
    console2.log('\n=== Deployment Summary ===');
    console2.log('Copy these addresses to TestnetDeployment.s.sol:\n');
    
    console2.log('// --- Core Contracts ---');
    console2.log('systemCoin = SystemCoin(', vm.toString(address(systemCoin)), ');');
    console2.log('protocolToken = ProtocolToken(', vm.toString(address(protocolToken)), ');');
    console2.log('safeEngine = SAFEEngine(', vm.toString(address(safeEngine)), ');');
    console2.log('oracleRelayer = OracleRelayer(', vm.toString(address(oracleRelayer)), ');');
    console2.log('surplusAuctionHouse = SurplusAuctionHouse(', vm.toString(address(surplusAuctionHouse)), ');');
    console2.log('debtAuctionHouse = DebtAuctionHouse(', vm.toString(address(debtAuctionHouse)), ');');
    console2.log('accountingEngine = AccountingEngine(', vm.toString(address(accountingEngine)), ');');
    console2.log('liquidationEngine = LiquidationEngine(', vm.toString(address(liquidationEngine)), ');');
    console2.log('coinJoin = CoinJoin(', vm.toString(address(coinJoin)), ');');
    console2.log('taxCollector = TaxCollector(', vm.toString(address(taxCollector)), ');');
    console2.log('stabilityFeeTreasury = StabilityFeeTreasury(', vm.toString(address(stabilityFeeTreasury)), ');');

    console2.log('\n// --- PID Contracts ---');
    console2.log('pidController = PIDController(', vm.toString(address(pidController)), ');');
    console2.log('pidRateSetter = PIDRateSetter(', vm.toString(address(pidRateSetter)), ');');

    console2.log('\n// --- Settlement Contracts ---');
    console2.log('globalSettlement = GlobalSettlement(', vm.toString(address(globalSettlement)), ');');
    console2.log('postSettlementSurplusAuctionHouse = PostSettlementSurplusAuctionHouse(', vm.toString(address(postSettlementSurplusAuctionHouse)), ');');
    console2.log('settlementSurplusAuctioneer = SettlementSurplusAuctioneer(', vm.toString(address(settlementSurplusAuctioneer)), ');');

    console2.log('\n// --- Factory Contracts ---');
    console2.log('chainlinkRelayerFactory = ChainlinkRelayerFactory(', vm.toString(address(chainlinkRelayerFactory)), ');');
    console2.log('uniV3RelayerFactory = UniV3RelayerFactory(', vm.toString(address(uniV3RelayerFactory)), ');');
    console2.log('denominatedOracleFactory = DenominatedOracleFactory(', vm.toString(address(denominatedOracleFactory)), ');');
    console2.log('delayedOracleFactory = DelayedOracleFactory(', vm.toString(address(delayedOracleFactory)), ');');
    console2.log('collateralJoinFactory = CollateralJoinFactory(', vm.toString(address(collateralJoinFactory)), ');');
    console2.log('collateralAuctionHouseFactory = CollateralAuctionHouseFactory(', vm.toString(address(collateralAuctionHouseFactory)), ');');

    console2.log('\n// --- Collateral Contracts ---');
    for (uint256 _i; _i < collateralTypes.length; _i++) {
        bytes32 _cType = collateralTypes[_i];
        console2.log(
            string.concat('collateralJoin[', string(abi.encodePacked(_cType)), '] = CollateralJoin('),
            vm.toString(address(collateralJoin[_cType])),
            ');'
        );
        console2.log(
            string.concat('collateralAuctionHouse[', string(abi.encodePacked(_cType)), '] = CollateralAuctionHouse('),
            vm.toString(address(collateralAuctionHouse[_cType])),
            ');'
        );
    }

    console2.log('\n// --- Job Contracts ---');
    console2.log('accountingJob = AccountingJob(', vm.toString(address(accountingJob)), ');');
    console2.log('liquidationJob = LiquidationJob(', vm.toString(address(liquidationJob)), ');');
    console2.log('oracleJob = OracleJob(', vm.toString(address(oracleJob)), ');');

    console2.log('\n// --- Proxy Contracts ---');
    console2.log('proxyFactory = AzosProxyFactory(', vm.toString(address(proxyFactory)), ');');
    console2.log('safeManager = AzosSafeManager(', vm.toString(address(safeManager)), ');');

    console2.log('\n// --- Action Contracts ---');
    console2.log('basicActions = BasicActions(', vm.toString(address(basicActions)), ');');
    console2.log('debtBidActions = DebtBidActions(', vm.toString(address(debtBidActions)), ');');
    console2.log('surplusBidActions = SurplusBidActions(', vm.toString(address(surplusBidActions)), ');');
    console2.log('collateralBidActions = CollateralBidActions(', vm.toString(address(collateralBidActions)), ');');
    console2.log('postSettlementSurplusBidActions = PostSettlementSurplusBidActions(', vm.toString(address(postSettlementSurplusBidActions)), ');');
    console2.log('globalSettlementActions = GlobalSettlementActions(', vm.toString(address(globalSettlementActions)), ');');
    console2.log('rewardedActions = RewardedActions(', vm.toString(address(rewardedActions)), ');');

    console2.log('\n// --- Oracle Contracts ---');
    console2.log('systemCoinOracle = IBaseOracle(', vm.toString(address(systemCoinOracle)), ');');
    for (uint256 _i; _i < collateralTypes.length; _i++) {
        bytes32 _cType = collateralTypes[_i];
        console2.log(
            string.concat('delayedOracle[', string(abi.encodePacked(_cType)), '] = IDelayedOracle('),
            vm.toString(address(delayedOracle[_cType])),
            ');'
        );
    }

    console2.log('\n// --- Governance Contracts ---');
    console2.log('azosGovernor = AzosGovernor(payable(', vm.toString(address(azosGovernor)), '));');
    console2.log('timelock = TimelockController(payable(', vm.toString(address(timelock)), '));');
    console2.log('azosDelegatee = AzosDelegatee(', vm.toString(address(azosDelegatee)), ');');
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
    systemCoinOracle = new HardcodedOracle('AZUSD / USD', AZUSD_USD_INITIAL_PRICE); // 1 AZUSD = 1 USD
  }

  function setupPostEnvironment() public virtual override updateParams {
    // Deploy AZUSD/WETH UniV3 pool (uninitialized)
    IUniswapV3Factory(UNISWAP_V3_FACTORY).createPool({
      tokenA: address(systemCoin),
      tokenB: address(collateral[WETH]),
      fee: AZUSD_POOL_FEE_TIER
    });

    // Setup AZUSD/WETH oracle feed
    IBaseOracle _AZUSDWethOracle = uniV3RelayerFactory.deployUniV3Relayer({
      _baseToken: address(systemCoin),
      _quoteToken: address(collateral[WETH]),
      _feeTier: AZUSD_POOL_FEE_TIER,
      _quotePeriod: 1 days
    });

    // Setup AZUSD/USD oracle feed
    denominatedOracleFactory.deployDenominatedOracle({
      _priceSource: _AZUSDWethOracle,
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
    gtcEthToken.setMultiClaimer(address(multiClaimer));
    klimaToken.setMultiClaimer(address(multiClaimer));
    celoToken.setMultiClaimer(address(multiClaimer));
    usdgloToken.setMultiClaimer(address(multiClaimer));
    charToken.setMultiClaimer(address(multiClaimer));
    
    
  
  // Setup collateral types
    collateralTypes.push(GTC_ETH);
    collateralTypes.push(CHAR);
    collateralTypes.push(KLIMA);
    collateralTypes.push(USDGLO);
    collateralTypes.push(CELO);

    systemCoinOracle = new HardcodedOracle('AZUSD / USD', AZUSD_USD_INITIAL_PRICE); // 1 AZUSD = 1 USD

    // Setup oracle system with DIA Oracle V2
    address diaOracleV2 = 0x83b56E80e47698BBc0d97828C1d8b1D509Ab6B4b;
    
    // Create base price feeds
    IBaseOracle _ethUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'ETH/USD',
        2 hours
    );
    console2.log('ETH/USD oracle created at:', address(_ethUsdOracle));

    IBaseOracle _klimaUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'KLIMA/USD',
        2 hours
    );
    console2.log('KLIMA/USD oracle created at:', address(_klimaUsdOracle));

    IBaseOracle _celoUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'CELO/USD',
        24 hours  // Increased validity window
    );
    console2.log('CELO/USD oracle created at:', address(_celoUsdOracle));

    IBaseOracle _usdgloUsdOracle = new DIARelayerV2(
        diaOracleV2,
        'DAI/USD',
        24 hours  // Increased validity window
    );
    console2.log('USDGLO/USD oracle created at:', address(_usdgloUsdOracle));

    // Create hardcoded oracle for CHAR at $163.19
    IBaseOracle _charUsdOracle = new HardcodedOracle('CHAR/USD', 163.19e18);
    console2.log('CHAR/USD oracle created at:', address(_charUsdOracle));

    // Create delayed oracles that wrap the price feeds
    delayedOracle[GTC_ETH] = delayedOracleFactory.deployDelayedOracle(_ethUsdOracle, 1 hours);
    delayedOracle[KLIMA] = delayedOracleFactory.deployDelayedOracle(_klimaUsdOracle, 1 hours);
    delayedOracle[CELO] = delayedOracleFactory.deployDelayedOracle(_celoUsdOracle, 1 hours);
    delayedOracle[USDGLO] = delayedOracleFactory.deployDelayedOracle(_usdgloUsdOracle, 1 hours);
    delayedOracle[CHAR] = delayedOracleFactory.deployDelayedOracle(_charUsdOracle, 1 hours);

    // Verify oracle prices
    console2.log('GTC_ETH price:', delayedOracle[GTC_ETH].priceSource().read());
    console2.log('KLIMA price:', delayedOracle[KLIMA].priceSource().read());
    console2.log('CELO price:', delayedOracle[CELO].priceSource().read());
    console2.log('USDGLO price:', delayedOracle[USDGLO].priceSource().read());
    console2.log('CHAR price:', delayedOracle[CHAR].priceSource().read());
  }

  function setupPostEnvironment() public virtual override updateParams {
    // Setup deviated oracle
    systemCoinOracle = new DeviatedOracle({
      _symbol: 'AZUSD / USD',
      _oracleRelayer: address(oracleRelayer),
      _deviation: BASE_SEPOLIA_AZUSD_PRICE_DEVIATION
    });

    oracleRelayer.modifyParameters('systemCoinOracle', abi.encode(systemCoinOracle));
  }
}
