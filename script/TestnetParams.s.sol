// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import '@script/Params.s.sol';

abstract contract TestnetParams is Contracts, Params {
  // --- Testnet Params ---
  uint256 constant OP_SEPOLIA_ZAI_PRICE_DEVIATION = 0.995e18; // -0.5%
  // #todo setup an admin safe on Base and change this address
  address constant OP_SEPOLIA_ADMIN_SAFE = 0xCAFd432b7EcAfff352D92fcB81c60380d437E99D;

  function _getEnvironmentParams() internal override {
    // Setup delegated collateral joins
    delegatee[OP] = address(azosDelegatee);

    _safeEngineParams = ISAFEEngine.SAFEEngineParams({
      safeDebtCeiling: 1_000_000 * WAD, // WAD
      globalDebtCeiling: 55_000_000 * RAD // initially disabled
    });

    // change the minimum amount of surplus to transfer
    _accountingEngineParams = IAccountingEngine.AccountingEngineParams({
      surplusIsTransferred: 0, // surplus is auctioned
      surplusDelay: 1 days,
      popDebtDelay: 0,
      disableCooldown: 3 days,
      surplusAmount: 42_000 * RAD, // 42k ZAI
      surplusBuffer: 100_000 * RAD, // 100k ZAI
      debtAuctionMintedTokens: 10_000 * WAD, // 10k KITE
      debtAuctionBidSize: 1000 * RAD // 1k ZAI
    });

    _debtAuctionHouseParams = IDebtAuctionHouse.DebtAuctionHouseParams({
      bidDecrease: 1.025e18, // -2.5 %
      amountSoldIncrease: 1.5e18, // +50 %
      bidDuration: 3 hours,
      totalAuctionLength: 2 days
    });

    _surplusAuctionHouseParams = ISurplusAuctionHouse.SurplusAuctionHouseParams({
      bidIncrease: 1.01e18, // +1 %
      bidDuration: 6 hours,
      totalAuctionLength: 1 days,
      bidReceiver: governor,
      recyclingPercentage: 0 // 100% is burned
    });

    _liquidationEngineParams = ILiquidationEngine.LiquidationEngineParams({
      onAuctionSystemCoinLimit: 10_000_000 * RAD, // 10M ZAI
      saviourGasLimit: 10_000_000 // 10M gas
    });

    _stabilityFeeTreasuryParams = IStabilityFeeTreasury.StabilityFeeTreasuryParams({
      treasuryCapacity: 1_000_000 * RAD, // 1M ZAI
      pullFundsMinThreshold: 0, // no threshold
      surplusTransferDelay: 1 days
    });

    _taxCollectorParams = ITaxCollector.TaxCollectorParams({
      primaryTaxReceiver: address(accountingEngine),
      globalStabilityFee: RAY, // no global SF
      maxStabilityFeeRange: RAY - MINUS_0_5_PERCENT_PER_HOUR, // +- 0.5% per hour
      maxSecondaryReceivers: 5
    });

    delete _taxCollectorSecondaryTaxReceiver; // avoid stacking old data on each push

    _taxCollectorSecondaryTaxReceiver.push(
      ITaxCollector.TaxReceiver({
        receiver: address(stabilityFeeTreasury),
        canTakeBackTax: true, // [bool]
        taxPercentage: 0.2e18 // 20%
      })
    );

    _taxCollectorSecondaryTaxReceiver.push(
      ITaxCollector.TaxReceiver({
        receiver: OP_SEPOLIA_ADMIN_SAFE,
        canTakeBackTax: true, // [bool]
        taxPercentage: 0.21e18 // 21%
      })
    );

    // --- PID Params ---

    _oracleRelayerParams = IOracleRelayer.OracleRelayerParams({
      redemptionRateUpperBound: PLUS_950_PERCENT_PER_YEAR, // +950%/yr
      // redemptionRateLowerBound: MINUS_90_PERCENT_PER_YEAR // -90%/yr
      redemptionRateLowerBound: MINUS_90_PERCENT_PER_YEAR_CORRECT // -90%/yr
    });

    _pidControllerParams = IPIDController.PIDControllerParams({
      // perSecondCumulativeLeak: 999_999_711_200_000_000_000_000_000, // HALF_LIFE_30_DAYS
      perSecondCumulativeLeak: 999_999_910_860_706_061_391_497_541, // HALF_LIFE_30_DAYS
      // noiseBarrier: 0.995e18, // 0.5%
      // noiseBarrier: 999_999_999_841_846_100,
      noiseBarrier: WAD, // no noise barrier
      feedbackOutputLowerBound: -int256(RAY - 1), // unbounded
      feedbackOutputUpperBound: RAD, // unbounded
      integralPeriodSize: 1 hours
    });

    _pidControllerGains = IPIDController.ControllerGains({
      kp: int256(PROPORTIONAL_GAIN), // imported from RAI
      ki: int256(INTEGRAL_GAIN) // imported from RAI
    });

    _pidRateSetterParams = IPIDRateSetter.PIDRateSetterParams({updateRateDelay: 1 hours});

    // --- Global Settlement Params ---
    _globalSettlementParams = IGlobalSettlement.GlobalSettlementParams({shutdownCooldown: 3 days});
    _postSettlementSAHParams = IPostSettlementSurplusAuctionHouse.PostSettlementSAHParams({
      bidIncrease: 1.01e18, // +1 %
      bidDuration: 3 hours,
      totalAuctionLength: 1 days
    });

    // --- Collateral Default Params ---
    // #todo check if collateralTypes has only our desired collaterals
    for (uint256 _i; _i < collateralTypes.length; _i++) {
      bytes32 _cType = collateralTypes[_i];

      if (_cType != GLOUSD) {
      _oracleRelayerCParams[_cType] = IOracleRelayer.OracleRelayerCollateralParams({
        oracle: delayedOracle[_cType],
        safetyCRatio: 1.5e27, // 150%
        liquidationCRatio: 1.5e27 // 150%
      });
      }
      else {
        _oracleRelayerCParams[_cType] = IOracleRelayer.OracleRelayerCollateralParams({
          oracle: delayedOracle[_cType],
          safetyCRatio: 1.11e26, // 111%
          liquidationCRatio: 1.11e26 // 111%
        });
      }

      _taxCollectorCParams[_cType] = ITaxCollector.TaxCollectorCollateralParams({
        // NOTE: 42%/yr => 1.42^(1/yr) = 1 + 11,11926e-9
        stabilityFee: RAY + 11.11926e18 // + 42%/yr
      });

      _safeEngineCParams[_cType] = ISAFEEngine.SAFEEngineCollateralParams({
        debtCeiling: 10_000_000 * RAD, // 10M ZAI
        debtFloor: 1 * RAD // 1 ZAI
      });

      _liquidationEngineCParams[_cType] = ILiquidationEngine.LiquidationEngineCollateralParams({
        collateralAuctionHouse: address(collateralAuctionHouse[_cType]),
        liquidationPenalty: 1.1e18, // 10%
        liquidationQuantity: 1000 * RAD // 1000 ZAI
      });

      _collateralAuctionHouseParams[_cType] = ICollateralAuctionHouse.CollateralAuctionHouseParams({
        minimumBid: WAD, // 1 ZAI
        minDiscount: WAD, // no discount
        maxDiscount: 0.9e18, // -10%
        perSecondDiscountUpdateRate: MINUS_0_5_PERCENT_PER_HOUR // RAY
      });
    }

    // --- Collateral Specific Params ---
    // #todo check the WETH params - I don't think we need these... these were special for pre-deployed tokens
    _oracleRelayerCParams[WETH].safetyCRatio = 1.35e27; // 135%
    _oracleRelayerCParams[WETH].liquidationCRatio = 1.35e27; // 135%
    _taxCollectorCParams[WETH].stabilityFee = RAY + 1.54713e18; // + 5%/yr
    _safeEngineCParams[WETH].debtCeiling = 100_000_000 * RAD; // 100M ZAI

    _liquidationEngineCParams[OP].liquidationPenalty = 1.2e18; // 20%
    _collateralAuctionHouseParams[OP].maxDiscount = 0.5e18; // -50%

    // --- Governance Params ---
    _governorParams = IAzosGovernor.AzosGovernorParams({
      votingDelay: 12 hours, // 43_200
      votingPeriod: 36 hours, // 129_600
      proposalThreshold: 5000 * WAD, // 5k KITE
      quorumNumeratorValue: 1, // 1%
      quorumVoteExtension: 1 days, // 86_400
      timelockMinDelay: 1 days // 86_400
    });

    // #todo setup a testnet airdrop root
    _tokenDistributorParams = ITokenDistributor.TokenDistributorParams({
      root: 0x6fc714df6371f577a195c2bfc47da41aa0ea15bba2651df126f3713a232244be,
      totalClaimable: 1_000_000 * WAD, // 1M ZAI
      claimPeriodStart: block.timestamp + 1 days,
      claimPeriodEnd: 1_735_689_599 // 1/1/2025 (GMT+0) - 1s
    });
  }
}
