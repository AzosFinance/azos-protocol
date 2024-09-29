// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Contracts.s.sol';
import {TestnetParams, WETH, OP, WBTC, STONES, TOTEM} from '@script/TestnetParams.s.sol';
import {OP_WETH, OP_OPTIMISM} from '@script/Registry.s.sol';

abstract contract TestnetDeployment is Contracts, TestnetParams {
  // NOTE: The last significant change in the Testnet deployment, to be used in the test scenarios
  uint256 constant SEPOLIA_DEPLOYMENT_BLOCK = 14_646_568;

  /**
   * @notice All the addresses that were deployed in the Testnet deployment, in order of creation
   * @dev    This is used to import the deployed contracts to the test scripts
   */
  constructor() {
    // --- collateral types ---
    collateralTypes.push(WETH);
    collateralTypes.push(OP);
    collateralTypes.push(WBTC);
    collateralTypes.push(STONES);
    collateralTypes.push(TOTEM);

    // --- ERC20s ---
    collateral[WETH] = IERC20Metadata(OP_WETH);
    collateral[OP] = IERC20Metadata(OP_OPTIMISM);
    collateral[WBTC] = IERC20Metadata(0xE6ff79DfcE1AC82AB0f420feabef7fA0B6113913);
    collateral[STONES] = IERC20Metadata(0x0976e648859425757142856303760c76d5fA3742);
    collateral[TOTEM] = IERC20Metadata(0x32d1e9Edb0f5332c6A7B7aa2C50134270DB618E6);

    systemCoin = SystemCoin(0xbcfEeAfb457854b69b428E3aD773Cfa632B34CBB);
    protocolToken = ProtocolToken(0x20e16208900aAcF61060583ee627078beF7aE4Cf);

    safeEngine = SAFEEngine(0xEbA0bB5dc4E7404d04E93f5D0bb3eCc9E62FEe3B);
    oracleRelayer = OracleRelayer(0x3191d2F4203EA6435ec7beB853Bb99E1C66b08FE);
    surplusAuctionHouse = SurplusAuctionHouse(0x9a1D951C2afce7788b4dB0245492d20F3a417BD5);
    debtAuctionHouse = DebtAuctionHouse(0xcA71B40BEca54d0EE2cAf0E9Ca7B8b539B2D43ff);
    accountingEngine = AccountingEngine(0x90BC9f1b6885F5D55CA24f6DBC25665575d8230a);
    liquidationEngine = LiquidationEngine(0xCB2F8FECEAA0E32ad328f99e2B1A568a612BD9E1);
    coinJoin = CoinJoin(0x95162301B89dA409EBd68398fde0096a9B4a0f13);
    taxCollector = TaxCollector(0x843fa2A6393b1177df5BC1d31CFEF4cB85E7553e);
    stabilityFeeTreasury = StabilityFeeTreasury(0xA06fc6E6c51473b698A9334A32186629E92761a3);

    pidController = PIDController(0xD5d7dBEDD80449E2bf557FC354A7CF62cFb07d2e);
    pidRateSetter = PIDRateSetter(0x7a6d6035d7e3509D6dc54B49621050A91Dd6B86C);

    globalSettlement = GlobalSettlement(0xF206f53D66dcDD22Eea80a7A3Bd3F48651284aCa);
    postSettlementSurplusAuctionHouse = PostSettlementSurplusAuctionHouse(0xA17afb06B80eFcF600E0573110713C5069C727c7);
    settlementSurplusAuctioneer = SettlementSurplusAuctioneer(0x8b744081b77CE8F5396401936Ed1Ae8224ea897e);

    // --- factories ---
    chainlinkRelayerFactory = ChainlinkRelayerFactory(address(0)); // not deployable in OP Sepolia
    uniV3RelayerFactory = UniV3RelayerFactory(address(0)); // not deployable in OP Sepolia
    denominatedOracleFactory = DenominatedOracleFactory(0x7460DE739613291119CD39C1fd0f7690A2B3fBc5);
    delayedOracleFactory = DelayedOracleFactory(0x2D80179ac931edC025746074505c4f93F7E5D687);
    collateralJoinFactory = CollateralJoinFactory(0x96a4eE2a938E8Fe22380fA1b19B190AC338fb1Fa);
    collateralAuctionHouseFactory = CollateralAuctionHouseFactory(0xfFF2dfE073813BF85615b02F21411f032cad99f8);

    // --- per token contracts ---
    collateralJoin[WETH] = CollateralJoin(0x0CC62FF2582485a71b5d556F454D0cEA167d9520);
    collateralAuctionHouse[WETH] = CollateralAuctionHouse(0xD63373c3BC20F23386009e4aeac56F7f132E16aB);

    collateralJoin[OP] = CollateralJoin(0x2d57b9205957484839D830A38d7d7e1bd6d506F6); // ignore for subgraph testing
    collateralAuctionHouse[OP] = CollateralAuctionHouse(0x13d0d98a0e7973B034E12e239aD6BBc29E3d9Ec8); // ignore for subgraph testing

    collateralJoin[WBTC] = CollateralJoin(0x8b53AD3842FBe724971c5E9500149Ae2E45B42E0);
    collateralAuctionHouse[WBTC] = CollateralAuctionHouse(0x8f789370D9cd98206D204Bf2bB90Af5219A08e39);

    collateralJoin[STONES] = CollateralJoin(0x75f6DCAD5f005F9ff2073e7C6E18E97a4A6861A5);
    collateralAuctionHouse[STONES] = CollateralAuctionHouse(0xcAE8A1218cc01EFE2F3fD2D87EA44d559EaEed1B);

    collateralJoin[TOTEM] = CollateralJoin(0xD96e4142C4e3Af50cEF3143C36B33b663139835b);
    collateralAuctionHouse[TOTEM] = CollateralAuctionHouse(0xa2DF3dB7b0A8a7C6f0128253437F5948AFFbCe14);

    // --- jobs ---
    accountingJob = AccountingJob(0xB9a09bbb5186B9a4A8e1FE4f8A37E9C3e608e7fb);
    liquidationJob = LiquidationJob(0xBE7784BE85b077c717fBb615a5FF500adFf46bAE);
    oracleJob = OracleJob(0xa668C53a49d50B2d3a5691C20Bac21c6F6dfaa23);

    // --- proxies ---
    proxyFactory = AzosProxyFactory(0xDd19D0Bf1AF992A811303d9bBC32544ae058a95e);
    safeManager = AzosSafeManager(0x5F697158D6B9A06ad048b43C44D5c611eD179960);

    basicActions = BasicActions(0xE55f91f49fa3103EF9a3d931bF898bA4eA1Eab17);
    debtBidActions = DebtBidActions(0xAc6f08c2208612260911C0B05Cdf07C1436D2268);
    surplusBidActions = SurplusBidActions(0xf50381476f3d572A7C2d741A1C34d5f74a7c14F7);
    collateralBidActions = CollateralBidActions(0x94049905c4dd088F053defc0Eb63E95328fB1E9d);
    postSettlementSurplusBidActions = PostSettlementSurplusBidActions(0x7C5335895cbd3aC96Ae6C80332f6297e370D56ad);
    globalSettlementActions = GlobalSettlementActions(0xeB3bbDe482a314fCBae878d94694fa08281ABFea);
    rewardedActions = RewardedActions(0x5A4faBf474b572cD4189B03cE97235FC4d4636e6);

    // --- oracles ---
    systemCoinOracle = IBaseOracle(0xbD96dDD370E30a0F0C4318aE21EA9DdCD5DBB863); // hardcoded oracle in testnet
    delayedOracle[WETH] = IDelayedOracle(0xEaC8c0f0fDba7e16f3d2704507a7BD8E79839cBf);
    delayedOracle[OP] = IDelayedOracle(0x9cD9256f91aC6fe823D9A9F415147AF0C6ADE3F4); // ignore for subgraph testing
    delayedOracle[WBTC] = IDelayedOracle(0x3bb0321AAc4d40cea8f6b1939CA696a06940Fd6C);
    delayedOracle[STONES] = IDelayedOracle(0x4f10A8E08460336933F804123D10a5D7D61AeAC9);
    delayedOracle[TOTEM] = IDelayedOracle(0x34a6405d42BFc95799CA8CC7b9037Ea618457998);

    // --- governance ---
    azosGovernor = AzosGovernor(payable(0xAf04b922Ba9762B1de61334d3d1cfDf0c1A3DcB0));
    timelock = TimelockController(payable(0x77B522Ac7bd1Feeb1783199Dc753784a4C51634e));
    azosDelegatee = AzosDelegatee(0x50649bcA8f69eaF28a0563c688F71a4ee1666264);

    tokenDistributor = TokenDistributor(0x5684Ea6cf4A323F410a1Eb25B4A6ec8D8a93Cf24); // ignore for subgraph testing

    // --- utils ---
    governor = address(timelock);
  }
}
