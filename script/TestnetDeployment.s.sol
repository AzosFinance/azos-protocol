// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Contracts.s.sol';
import {TestnetParams, GTC_ETH, KLIMA, CELO, USDGLO, CHAR} from '@script/TestnetParams.s.sol';
import {OP_WETH, OP_OPTIMISM} from '@script/Registry.s.sol';
import {DIARelayerV2} from '@contracts/oracles/DIARelayerV2.sol';

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


    systemCoin = SystemCoin(0xd73899cd6b799b188fb1b4d051da16e8885ec6c0);
    protocolToken = ProtocolToken(0xb011a9514b5b7cb51a6ed9b85311ea3639f573ae);

    safeEngine = SAFEEngine(0x7a339D2b14c7eEeC82740e4a7906f6b160036b22);
    oracleRelayer = OracleRelayer(0x36d8d7ad66f51ac2F10FFDF9D46a7e99287b8C3e);
    surplusAuctionHouse = SurplusAuctionHouse(0xc1dA6c17F1a4933e6048BB8de2D9Bac132C0DA55);
    debtAuctionHouse = DebtAuctionHouse(0xfdb4e3Db4aBc4A33bd70d6A7EF1F00eA4F4E95C4);
    accountingEngine = AccountingEngine(0x998CBe4bC59cA67F844E6aa1Cc9834Bb271E0C1e);
    liquidationEngine = LiquidationEngine(0x6028828e1871fb688597f531A0f2786ec9Cb9dec);
    coinJoin = CoinJoin(0xfa42d729816c72edb495eeea4fe0bd9f2dda9a9d);
    taxCollector = TaxCollector(0xac84da68a0230678b41305aa679b5db3460bd0ec);
    stabilityFeeTreasury = StabilityFeeTreasury(0x97051f334fedeb80708ad197c0364534df0f916e);

    pidController = PIDController(0xD5d7dBEDD80449E2bf557FC354A7CF62cFb07d2e);
    pidRateSetter = PIDRateSetter(0x7a6d6035d7e3509D6dc54B49621050A91Dd6B86C);

    globalSettlement = GlobalSettlement(0x99917c63d94069e255f4e8b43697ba7c89d2cb58);
    postSettlementSurplusAuctionHouse = PostSettlementSurplusAuctionHouse(0xA17afb06B80eFcF600E0573110713C5069C727c7);
    settlementSurplusAuctioneer = SettlementSurplusAuctioneer(0x8b744081b77CE8F5396401936Ed1Ae8224ea897e);

    // --- factories ---
    chainlinkRelayerFactory = ChainlinkRelayerFactory(address(0));
    uniV3RelayerFactory = UniV3RelayerFactory(address(0));
    denominatedOracleFactory = DenominatedOracleFactory(0x7460DE739613291119CD39C1fd0f7690A2B3fBc5);
    delayedOracleFactory = DelayedOracleFactory(0x2D80179ac931edC025746074505c4f93F7E5D687);
    collateralJoinFactory = CollateralJoinFactory(0x96a4eE2a938E8Fe22380fA1b19B190AC338fb1Fa);
    collateralAuctionHouseFactory = CollateralAuctionHouseFactory(0xfFF2dfE073813BF85615b02F21411f032cad99f8);

    // --- per token contracts ---
    // #todo set collateral join for new collateral types
    collateralJoin[GTC_ETH] = CollateralJoin(0x0CC62FF2582485a71b5d556F454D0cEA167d9520);
    collateralAuctionHouse[GTC_ETH] = CollateralAuctionHouse(0xD63373c3BC20F23386009e4aeac56F7f132E16aB);

    collateralJoin[KLIMA] = CollateralJoin(0x2d57b9205957484839D830A38d7d7e1bd6d506F6);
    collateralAuctionHouse[KLIMA] = CollateralAuctionHouse(0x13d0d98a0e7973B034E12e239aD6BBc29E3d9Ec8);

    collateralJoin[CELO] = CollateralJoin(0x8b53AD3842FBe724971c5E9500149Ae2E45B42E0);
    collateralAuctionHouse[CELO] = CollateralAuctionHouse(0x8f789370D9cd98206D204Bf2bB90Af5219A08e39);

    collateralJoin[USDGLO] = CollateralJoin(0x75f6DCAD5f005F9ff2073e7C6E18E97a4A6861A5);
    collateralAuctionHouse[USDGLO] = CollateralAuctionHouse(0xcAE8A1218cc01EFE2F3fD2D87EA44d559EaEed1B);

    collateralJoin[CHAR] = CollateralJoin(0xD96e4142C4e3Af50cEF3143C36B33b663139835b);
    collateralAuctionHouse[CHAR] = CollateralAuctionHouse(0xa2DF3dB7b0A8a7C6f0128253437F5948AFFbCe14);

    // --- jobs ---
    accountingJob = AccountingJob(0xB9a09bbb5186B9a4A8e1FE4f8A37E9C3e608e7fb);
    liquidationJob = LiquidationJob(0xBE7784BE85b077c717fBb615a5FF500adFf46bAE);
    oracleJob = OracleJob(0xa668C53a49d50B2d3a5691C20Bac21c6F6dfaa23);

    // --- proxies ---
    proxyFactory = AzosProxyFactory(0xb202c36501a3cee3d4d686e076a7b5dd2cf472d0);
    safeManager = AzosSafeManager(0x8e6cfdfc5574e48966a5f1f595a8e96a3b9db820);

    basicActions = BasicActions(0x3e3015fa438b7c9efa51f0af8d1c71035d24f0f0);
    debtBidActions = DebtBidActions(0xe2ceab5b999b21f0171862dae333f205c24185be);
    surplusBidActions = SurplusBidActions(0x3bb2940cb32e0528cfeb6cf56eda8a9d18e35e67);
    collateralBidActions = CollateralBidActions(0x94049905c4dd088F053defc0Eb63E95328fB1E9d);
    postSettlementSurplusBidActions = PostSettlementSurplusBidActions(0x7C5335895cbd3aC96Ae6C80332f6297e370D56ad);
    globalSettlementActions = GlobalSettlementActions(0x752588F0d92aB7EC9Cf036630394819e26b320AD);
    rewardedActions = RewardedActions(0x5A4faBf474b572cD4189B03cE97235FC4d4636e6);

    // --- oracles ---
    // #todo change the oracles to the correct ones for our collateral
    systemCoinOracle = IBaseOracle(0xbD96dDD370E30a0F0C4318aE21EA9DdCD5DBB863); // hardcoded oracle in testnet
    delayedOracle[GTC_ETH] = IDelayedOracle(0xEaC8c0f0fDba7e16f3d2704507a7BD8E79839cBf);
    delayedOracle[KLIMA] = IDelayedOracle(0x9cD9256f91aC6fe823D9A9F415147AF0C6ADE3F4); // ignore for subgraph testing
    delayedOracle[CELO] = IDelayedOracle(0x3bb0321AAc4d40cea8f6b1939CA696a06940Fd6C);
    delayedOracle[USDGLO] = IDelayedOracle(0x4f10A8E08460336933F804123D10a5D7D61AeAC9);
    delayedOracle[CHAR] = IDelayedOracle(0x34a6405d42BFc95799CA8CC7b9037Ea618457998);

    // --- governance ---
    azosGovernor = AzosGovernor(payable(0x0d98ec32cb06323f909a32ce7289420435d0215a));
    timelock = TimelockController(payable(0xd43c22aA8F55e4F77460F8De1fDffc54e6e167a1));
    azosDelegatee = AzosDelegatee(0xc1d0f313dcec0679b2c3c8d53ac2f741f83e3712);

    tokenDistributor = TokenDistributor(0x5684Ea6cf4A323F410a1Eb25B4A6ec8D8a93Cf24); // ignore for subgraph testing

    // --- utils ---
    governor = address(timelock);
  }
}
