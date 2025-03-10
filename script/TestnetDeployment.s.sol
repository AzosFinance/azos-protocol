// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Contracts.s.sol';
import {TestnetParams, GTC_ETH, KLIMA, CELO, USDGLO, CHAR} from '@script/TestnetParams.s.sol';
import {OP_WETH, OP_OPTIMISM} from '@script/Registry.s.sol';
import {DIARelayerV2} from '@contracts/oracles/DIARelayerV2.sol';
import {SystemCoinSuperToken} from '@contracts/superfluid/SystemCoinSuperToken.sol';

abstract contract TestnetDeployment is Contracts, TestnetParams {
  // NOTE: The last significant change in the Testnet deployment
  uint256 constant SEPOLIA_DEPLOYMENT_BLOCK = 20922409;

  /**
   * @notice All the addresses that were deployed in the Testnet deployment, in order of creation
   * @dev    This is used to import the deployed contracts to the test scripts
   */
  constructor() {
    // #todo update collateral types to be correct
    // --- collateral types ---
    collateralTypes.push(GTC_ETH);
    collateralTypes.push(KLIMA);
    collateralTypes.push(CELO);
    collateralTypes.push(USDGLO);
    collateralTypes.push(CHAR);

    delegatee[GTC_ETH] = address(0);
    delegatee[KLIMA] = address(0);
    delegatee[CELO] = address(0);
    delegatee[USDGLO] = address(0);
    delegatee[CHAR] = address(0);

    // --- ERC20s ---
    // #todo change our collateral assignments
    collateral[GTC_ETH] = new ClaimableERC20('GTC ETH LP', 'GTC-ETH', 18);
    collateral[KLIMA] = new ClaimableERC20('Klima DAO', 'KLIMA', 18);
    collateral[CELO] = new ClaimableERC20('Celo', 'CELO', 18);
    collateral[USDGLO] = new ClaimableERC20('USD Globe', 'USDGLO', 18);
    collateral[CHAR] = new ClaimableERC20('BioChar', 'CHAR', 18);


    systemCoin = SystemCoin(0xe33afdd2e789b7993e6bb7b244d101fed92d218c);
    protocolToken = ProtocolToken(0x53856c5a4aca77aa553b60ee407941ca8788d22c);

    safeEngine = SAFEEngine(0x8224f255734b79da91bfd93ffa1d8bb5a84ae0d0);
    oracleRelayer = OracleRelayer(0xaCa53C12d8F9C65888E40489f876ec23186E97a3);
    surplusAuctionHouse = SurplusAuctionHouse(0x12a5232c1ec706620c0996d7187c6b198bfe58e4);
    debtAuctionHouse = DebtAuctionHouse(0x0a5269044596fc7207a4c19942705155a79df104);
    accountingEngine = AccountingEngine(0x6bcad9adda6c32177f8c94638bd233fca4ac91c9);
    liquidationEngine = LiquidationEngine(0x05ab9130e31160c30303be2efc79fb9f91192e7a);
    coinJoin = CoinJoin(0xbd64a50ac427eca7f796b8d5bf4ffae7fb60ef4e);
    taxCollector = TaxCollector(0xe3cb3ad09567953a4660ad76b8c7c18172fa5fd5);
    stabilityFeeTreasury = StabilityFeeTreasury(0x44705e53d03c1ccd45f37a13398735e6f6338604);

    pidController = PIDController(0x75549b384e15dfe8d4cc2db85f8ce1d35b983a6f);
    pidRateSetter = PIDRateSetter(0x7ebaaf4757e456f02ffeba4354bc0066059de931);

    globalSettlement = GlobalSettlement(0x3140acdbee5cfba17d2df1cc631e2a62d9a65017);
    postSettlementSurplusAuctionHouse = PostSettlementSurplusAuctionHouse(0x1c3aa7542652fe9a7ad986eaa3ba1f090072d9ae);
    settlementSurplusAuctioneer = SettlementSurplusAuctioneer(0x053ebaba4b8b5b34818b99aa4cb793ab664dc698);

    // --- factories ---
    chainlinkRelayerFactory = ChainlinkRelayerFactory(address(0));
    uniV3RelayerFactory = UniV3RelayerFactory(address(0));
    denominatedOracleFactory = DenominatedOracleFactory(0x81f209348aadda71974b281987fc7c3e16bfda39);
    delayedOracleFactory = DelayedOracleFactory(0x1752cc7f18ce3632d3426d0696c5daa8f2a858c8);
    collateralJoinFactory = CollateralJoinFactory(0x790cd47b222411786f6748e35d36b047239d40af);
    collateralAuctionHouseFactory = CollateralAuctionHouseFactory(0x8af289ee0a0ddb8761ab01493f720b3d3d046b2d);

    // --- per token contracts ---
    collateralJoin[GTC_ETH] = CollateralJoin(0x9Aa924b0269F65E580a58657782121D837Cd6b35);
    collateralAuctionHouse[GTC_ETH] = CollateralAuctionHouse(0x5Bb1ffD07200Bfc6a5c015F0d66C3cdff411c4c6);

    collateralJoin[KLIMA] = CollateralJoin(0x7fAc30eDc88cBbFC5fcb190C8edFde786f283826);
    collateralAuctionHouse[KLIMA] = CollateralAuctionHouse(0x2CB56a1f539754f1888e20675A49707bD51fa0e9);

    collateralJoin[CELO] = CollateralJoin(0x0bC451e51820E03Db75D75aE3CA3561B145E698E);
    collateralAuctionHouse[CELO] = CollateralAuctionHouse(0x75c23c6eb61Ec449A734821982F277dB6D20C535);

    collateralJoin[USDGLO] = CollateralJoin(0xaF6884D876B246e18016014939C161d6Ac3Bf6D8);
    collateralAuctionHouse[USDGLO] = CollateralAuctionHouse(0x3450a50d6E5Fa3b8E67512F93aB265aa7D7C157b);

    collateralJoin[CHAR] = CollateralJoin(0x10132623445A579fF44a40219387ba557597F2e9);
    collateralAuctionHouse[CHAR] = CollateralAuctionHouse(0xBaA561e1d6703E767A3Ee8d15108CA70AcB29288);

    // --- jobs ---
    accountingJob = AccountingJob(0xa02720868542b6b785c8a8992c724b99404f3ea8);
    liquidationJob = LiquidationJob(0xb0dd97c51aaf2e59d68a94232fdd1642428bddd6);
    oracleJob = OracleJob(0xfffa5113924905ad0412a216296084879662d45f);

    // --- proxies ---
    proxyFactory = AzosProxyFactory(0x2d2e75ea6f0fe844f1c10a644354d40859a8136e);
    safeManager = AzosSafeManager(0x70280e68cf5c5d174ed65b6a507dbe9395153d4e);

    basicActions = BasicActions(0xad0cb5bb7e5be7fb7d2d0f804be091fa6884d3d1);
    debtBidActions = DebtBidActions(0x8e932b0cf737df23b498da361f5617186d14f6ea);
    surplusBidActions = SurplusBidActions(0x3b43b2f5d74b38c0b62e05b75a7b6ea689cfc669);
    collateralBidActions = CollateralBidActions(0x3f2d4ee03392f5c198faf28c24dea948e1e02d8d);
    postSettlementSurplusBidActions = PostSettlementSurplusBidActions(0x55ae86a9b5042cd6929ac53919bbb48025a9f73e);
    globalSettlementActions = GlobalSettlementActions(0x705f7f65c6506becdd116e01ac89b52dac1734cf);
    rewardedActions = RewardedActions(0xefccafe80b9d37a49a9577691d2c6e4d6baa7f4e);

    // --- oracles ---
    // #todo change the oracles to the correct ones for our collateral
    systemCoinOracle = IBaseOracle(0xb2fad96c00a932f7313752a835e441be411243aa); // hardcoded oracle in testnet
    delayedOracle[GTC_ETH] = IDelayedOracle(0x539d0874d22a240dfa7bfc241f6f65b7895c0b10);
    delayedOracle[KLIMA] = IDelayedOracle(0xc41603e5e8b1f7ac17400a272654013464cc21a7); // ignore for subgraph testing
    delayedOracle[CELO] = IDelayedOracle(0xb0c91b4b0758cc81f21cbb54a3f567191f0f70eb);
    delayedOracle[USDGLO] = IDelayedOracle(0x1ad9b4b4e262ca65c7e58b6dd7c293feed71ec07);
    delayedOracle[CHAR] = IDelayedOracle(0x9cD9256f91aC6fe823D9A9F415147AF0C6ADE3F4);

    // --- governance ---
    azosGovernor = AzosGovernor(payable(0xcc4d008fad468bc6c1020858cd8e88fcab27f060));
    timelock = TimelockController(payable(0xd43c22aA8F55e4F77460F8De1fDffc54e6e167a1));
    azosDelegatee = AzosDelegatee(0x849792f1cd28a6f5e804463b1901d2c40cb8fe4b);

    // tokenDistributor = TokenDistributor(0x5684Ea6cf4A323F410a1Eb25B4A6ec8D8a93Cf24); // ignore for subgraph testing

    // --- utils ---
    governor = address(timelock);

    // --- Superfluid Integration ---
    // This will be populated after deployment
    systemCoinSuperToken = SystemCoinSuperToken(address(0));
  }
}
