// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import 'ds-test/test.sol';

import {SAFEEngine} from '@contracts/SAFEEngine.sol';
import {IncreasingDiscountCollateralAuctionHouse} from '@contracts/CollateralAuctionHouse.sol';
import {OracleRelayer} from '@contracts/OracleRelayer.sol';

import {Math, WAD, RAY, RAD} from '@libraries/Math.sol';

abstract contract Hevm {
  function warp(uint256) public virtual;
}

contract Guy {
  IncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse;

  constructor(IncreasingDiscountCollateralAuctionHouse increasingDiscountCollateralAuctionHouse_) {
    increasingDiscountCollateralAuctionHouse = increasingDiscountCollateralAuctionHouse_;
  }

  function approveSAFEModification(address safe) public {
    address safeEngine = address(increasingDiscountCollateralAuctionHouse.safeEngine());
    SAFEEngine(safeEngine).approveSAFEModification(safe);
  }

  function buyCollateral_increasingDiscount(uint256 id, uint256 wad) public {
    increasingDiscountCollateralAuctionHouse.buyCollateral(id, wad);
  }

  function try_buyCollateral_increasingDiscount(uint256 id, uint256 wad) public returns (bool ok) {
    string memory sig = 'buyCollateral(uint256,uint256)';
    (ok,) = address(increasingDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id, wad));
  }

  function try_increasingDiscount_terminateAuctionPrematurely(uint256 id) public returns (bool ok) {
    string memory sig = 'terminateAuctionPrematurely(uint256)';
    (ok,) = address(increasingDiscountCollateralAuctionHouse).call(abi.encodeWithSignature(sig, id));
  }
}

contract Gal {}

contract RevertableMedian {
  function getResultWithValidity() external pure returns (bytes32, bool) {
    revert();
  }
}

contract Feed {
  address public priceSource;
  uint256 public priceFeedValue;
  bool public hasValidValue;

  constructor(bytes32 initPrice, bool initHas) {
    priceFeedValue = uint256(initPrice);
    hasValidValue = initHas;
  }

  function set_val(uint256 newPrice) external {
    priceFeedValue = newPrice;
  }

  function set_price_source(address priceSource_) external {
    priceSource = priceSource_;
  }

  function set_has(bool newHas) external {
    hasValidValue = newHas;
  }

  function getResultWithValidity() external view returns (uint256, bool) {
    return (priceFeedValue, hasValidValue);
  }
}

contract PartiallyImplementedFeed {
  uint256 public priceFeedValue;
  bool public hasValidValue;

  constructor(bytes32 initPrice, bool initHas) {
    priceFeedValue = uint256(initPrice);
    hasValidValue = initHas;
  }

  function set_val(uint256 newPrice) external {
    priceFeedValue = newPrice;
  }

  function set_has(bool newHas) external {
    hasValidValue = newHas;
  }

  function getResultWithValidity() external view returns (uint256, bool) {
    return (priceFeedValue, hasValidValue);
  }
}

contract DummyLiquidationEngine {
  uint256 public currentOnAuctionSystemCoins;

  constructor(uint256 rad) {
    currentOnAuctionSystemCoins = rad;
  }

  function removeCoinsFromAuction(uint256 rad) public {
    currentOnAuctionSystemCoins -= rad;
  }
}

contract SingleIncreasingDiscountCollateralAuctionHouseTest is DSTest {
  using Math for uint256;

  Hevm hevm;

  DummyLiquidationEngine liquidationEngine;
  SAFEEngine safeEngine;
  IncreasingDiscountCollateralAuctionHouse collateralAuctionHouse;
  OracleRelayer oracleRelayer;
  Feed collateralFSM;
  Feed collateralMedian;
  Feed systemCoinMedian;

  address ali;
  address bob;
  address auctionIncomeRecipient;
  address safeAuctioned = address(0xacab);

  function setUp() public {
    hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    hevm.warp(604_411_200);

    safeEngine = new SAFEEngine();

    safeEngine.initializeCollateralType('collateralType');

    liquidationEngine = new DummyLiquidationEngine(rad(1000 ether));
    collateralAuctionHouse =
      new IncreasingDiscountCollateralAuctionHouse(address(safeEngine), address(liquidationEngine), 'collateralType');

    oracleRelayer = new OracleRelayer(address(safeEngine));
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(5 * RAY));
    collateralAuctionHouse.modifyParameters('oracleRelayer', address(oracleRelayer));

    collateralFSM = new Feed(bytes32(uint256(0)), true);
    collateralAuctionHouse.modifyParameters('collateralFSM', address(collateralFSM));

    collateralMedian = new Feed(bytes32(uint256(0)), true);
    systemCoinMedian = new Feed(bytes32(uint256(0)), true);

    collateralFSM.set_price_source(address(collateralMedian));

    ali = address(new Guy(collateralAuctionHouse));
    bob = address(new Guy(collateralAuctionHouse));
    auctionIncomeRecipient = address(new Gal());

    Guy(ali).approveSAFEModification(address(collateralAuctionHouse));
    Guy(bob).approveSAFEModification(address(collateralAuctionHouse));
    safeEngine.approveSAFEModification(address(collateralAuctionHouse));

    safeEngine.modifyCollateralBalance('collateralType', address(this), 1000 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 ether));
    safeEngine.createUnbackedDebt(address(0), bob, rad(200 ether));
  }

  // --- Math ---
  function rad(uint256 wad) internal pure returns (uint256 z) {
    z = wad * 10 ** 27;
  }

  // General tests
  function test_modifyParameters() public {
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.9e18);
    collateralAuctionHouse.modifyParameters('minDiscount', 0.91e18);
    collateralAuctionHouse.modifyParameters('minimumBid', 100 * WAD);
    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', RAY - 100);
    collateralAuctionHouse.modifyParameters(
      'maxDiscountUpdateRateTimeline', uint256(uint48(int48(-1))) - block.timestamp - 1
    );
    collateralAuctionHouse.modifyParameters('lowerCollateralMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperCollateralMedianDeviation', 0.9e18);
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    assertEq(collateralAuctionHouse.minDiscount(), 0.91e18);
    assertEq(collateralAuctionHouse.maxDiscount(), 0.9e18);
    assertEq(collateralAuctionHouse.lowerCollateralMedianDeviation(), 0.95e18);
    assertEq(collateralAuctionHouse.upperCollateralMedianDeviation(), 0.9e18);
    assertEq(collateralAuctionHouse.lowerSystemCoinMedianDeviation(), 0.95e18);
    assertEq(collateralAuctionHouse.upperSystemCoinMedianDeviation(), 0.9e18);
    assertEq(collateralAuctionHouse.perSecondDiscountUpdateRate(), RAY - 100);
    assertEq(collateralAuctionHouse.maxDiscountUpdateRateTimeline(), uint256(uint48(int48(-1))) - block.timestamp - 1);
    assertEq(collateralAuctionHouse.minimumBid(), 100 * WAD);
    assertEq(uint256(collateralAuctionHouse.totalAuctionLength()), uint256(uint48(int48(-1))));
  }

  function testFail_set_partially_implemented_collateralFSM() public {
    PartiallyImplementedFeed partiallyImplementedCollateralFSM = new PartiallyImplementedFeed(bytes32(uint256(0)), true);
    collateralAuctionHouse.modifyParameters('collateralFSM', address(partiallyImplementedCollateralFSM));
  }

  function testFail_no_min_discount() public {
    collateralAuctionHouse.modifyParameters('minDiscount', 1 ether);
  }

  function testFail_max_discount_lower_than_min() public {
    collateralAuctionHouse.modifyParameters('maxDiscount', 1 ether - 1);
  }

  function test_getSystemCoinFloorDeviatedPrice() public {
    collateralAuctionHouse.modifyParameters('minSystemCoinMedianDeviation', 0.9e18);

    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 1e18);
    assertEq(
      collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()),
      oracleRelayer.redemptionPrice()
    );

    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    assertEq(
      collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()),
      oracleRelayer.redemptionPrice()
    );

    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.9e18);
    assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), 4.5e27);

    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.89e18);
    assertEq(collateralAuctionHouse.getSystemCoinFloorDeviatedPrice(oracleRelayer.redemptionPrice()), 4.45e27);
  }

  function test_getSystemCoinCeilingDeviatedPrice() public {
    collateralAuctionHouse.modifyParameters('minSystemCoinMedianDeviation', 0.9e18);

    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 1e18);
    assertEq(
      collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()),
      oracleRelayer.redemptionPrice()
    );

    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.95e18);
    assertEq(
      collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()),
      oracleRelayer.redemptionPrice()
    );

    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);
    assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), 5.5e27);

    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.89e18);
    assertEq(collateralAuctionHouse.getSystemCoinCeilingDeviatedPrice(oracleRelayer.redemptionPrice()), 5.55e27);
  }

  function test_startAuction() public {
    collateralAuctionHouse.startAuction({
      amountToSell: 100 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });
  }

  function testFail_buyCollateral_inexistent_auction() public {
    // can't buyCollateral on non-existent
    collateralAuctionHouse.buyCollateral(42, 5 * WAD);
  }

  function testFail_buyCollateral_null_bid() public {
    collateralAuctionHouse.startAuction({
      amountToSell: 100 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });
    // can't buy collateral on non-existent
    collateralAuctionHouse.buyCollateral(1, 0);
  }

  function testFail_faulty_collateral_fsm_price() public {
    Feed faultyFeed = new Feed(bytes32(uint256(1)), false);
    collateralAuctionHouse.modifyParameters('collateralFSM', address(faultyFeed));
    collateralAuctionHouse.startAuction({
      amountToSell: 100 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });
    collateralAuctionHouse.buyCollateral(1, 5 * WAD);
  }

  // Tests with a setup that's similar to a fixed discount auction
  function test_buy_some_collateral() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 25 * WAD);
    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(975 ether));

    (
      uint256 amountToSell,
      uint256 amountToRaise,
      uint256 currentDiscount,
      uint256 maxDiscount,
      uint256 perSecondDiscountUpdateRate,
      uint256 latestDiscountUpdateTime,
      uint48 discountIncreaseDeadline,
      address forgoneCollateralReceiver,
      address incomeRecipient
    ) = collateralAuctionHouse.bids(id);

    assertEq(amountToRaise, 25 * RAD);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(currentDiscount, collateralAuctionHouse.minDiscount());
    assertEq(maxDiscount, collateralAuctionHouse.maxDiscount());
    assertEq(perSecondDiscountUpdateRate, collateralAuctionHouse.perSecondDiscountUpdateRate());
    assertEq(latestDiscountUpdateTime, block.timestamp);
    assertEq(discountIncreaseDeadline, block.timestamp + collateralAuctionHouse.maxDiscountUpdateRateTimeline());
    assertEq(forgoneCollateralReceiver, address(safeAuctioned));
    assertEq(incomeRecipient, auctionIncomeRecipient);

    assertTrue(canBidThisAmount);
    assertEq(adjustedBid, 25 * WAD);
    assertEq(safeEngine.coinBalance(incomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_buy_all_collateral() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(2 * RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    assertEq(
      collateralAuctionHouse.getDiscountedCollateralPrice(200 ether, 0, oracleRelayer.redemptionPrice(), 0.95e18),
      95 ether
    );

    (uint256 collateralBought, uint256 collateralBoughtAdjustedBid) =
      collateralAuctionHouse.getCollateralBought(id, 50 * WAD);

    assertEq(collateralBought, 526_315_789_473_684_210);
    assertEq(collateralBoughtAdjustedBid, 50 * WAD);

    (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 50 * WAD);
    Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertTrue(canBidThisAmount);
    assertEq(adjustedBid, 50 * WAD);
    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 526_315_789_473_684_210
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 1 ether - 526_315_789_473_684_210);
  }

  function testFail_start_tiny_collateral_auction() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(2 * RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    collateralAuctionHouse.startAuction({
      amountToSell: 100,
      amountToRaise: 50,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });
  }

  function test_buyCollateral_small_market_price() public {
    collateralFSM.set_val(0.01 ether);
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(2 * RAY));
    (uint256 colMedianPrice, bool colMedianValidity) = collateralMedian.getResultWithValidity();
    assertEq(colMedianPrice, 0);
    assertTrue(colMedianValidity);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    (bool canBidThisAmount, uint256 adjustedBid) = collateralAuctionHouse.getAdjustedBid(id, 5 * WAD);
    Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertTrue(canBidThisAmount);
    assertEq(adjustedBid, 5 * WAD);
    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 5 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 1 ether);
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function test_big_discount_buy() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.1e18);
    collateralAuctionHouse.modifyParameters('minDiscount', 0.1e18);
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });
    Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 1_000_000_000_000_000_000
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function test_small_discount_buy() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralAuctionHouse.modifyParameters('minDiscount', 0.99e18);
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.99e18);
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });
    Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 252_525_252_525_252_525
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 1 ether - 252_525_252_525_252_525);
  }

  function test_collateral_median_and_collateral_fsm_equal() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_collateral_median_higher_than_collateral_fsm_floor() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(181 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 145_391_102_064_553_649);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 145_391_102_064_553_649
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 145_391_102_064_553_649
    );
  }

  function test_collateral_median_lower_than_collateral_fsm_ceiling() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(209 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 125_912_868_295_139_763);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 125_912_868_295_139_763
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 125_912_868_295_139_763
    );
  }

  function test_collateral_median_higher_than_collateral_fsm_ceiling() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(500 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 125_313_283_208_020_050);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 125_313_283_208_020_050
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 125_313_283_208_020_050
    );
  }

  function test_collateral_median_lower_than_collateral_fsm_floor() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(1 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 146_198_830_409_356_725);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 146_198_830_409_356_725
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 146_198_830_409_356_725
    );
  }

  function test_collateral_median_lower_than_collateral_fsm_buy_all() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(1 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 292_397_660_818_713_450
    );
  }

  function test_collateral_median_reverts() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    RevertableMedian revertMedian = new RevertableMedian();
    collateralFSM.set_price_source(address(revertMedian));
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_system_coin_median_and_redemption_equal() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(1 ether);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_system_coin_median_higher_than_redemption_floor() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(0.975e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 128_289_473_684_210_526);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 128_289_473_684_210_526
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 128_289_473_684_210_526
    );
  }

  function test_system_coin_median_lower_than_redemption_ceiling() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(1.05e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 138_157_894_736_842_105);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 138_157_894_736_842_105
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 138_157_894_736_842_105
    );
  }

  function test_system_coin_median_higher_than_redemption_ceiling() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(1.15e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 144_736_842_105_263_157);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 144_736_842_105_263_157
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 144_736_842_105_263_157
    );
  }

  function test_system_coin_median_lower_than_redemption_floor() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(0.9e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 125_000_000_000_000_000);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 125_000_000_000_000_000
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 125_000_000_000_000_000
    );
  }

  function test_system_coin_median_lower_than_redemption_buy_all() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(0.9e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 50 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 250_000_000_000_000_000
    );
  }

  function test_system_coin_median_reverts() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    RevertableMedian revertMedian = new RevertableMedian();

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(revertMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_system_coin_lower_collateral_median_higher() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    systemCoinMedian.set_val(0.9e18);

    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(220 ether);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 119_047_619_047_619_047);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 119_047_619_047_619_047
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 119_047_619_047_619_047
    );
  }

  function test_system_coin_higher_collateral_median_lower() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    systemCoinMedian.set_val(1.1e18);

    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(180 ether);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 160_818_713_450_292_397);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 160_818_713_450_292_397
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 160_818_713_450_292_397
    );
  }

  function test_system_coin_lower_collateral_median_lower() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    systemCoinMedian.set_val(0.9e18);

    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(180 ether);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 138_888_888_888_888_888);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 138_888_888_888_888_888
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 138_888_888_888_888_888
    );
  }

  function test_system_coin_higher_collateral_median_higher() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    systemCoinMedian.set_val(1.1e18);

    collateralFSM.set_val(200 ether);
    collateralMedian.set_val(210 ether);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 137_844_611_528_822_055);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 137_844_611_528_822_055
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 137_844_611_528_822_055
    );
  }

  function test_min_system_coin_deviation_exceeds_lower_deviation() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(0.95e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('minSystemCoinMedianDeviation', 0.94e18);
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_min_system_coin_deviation_exceeds_higher_deviation() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    systemCoinMedian.set_val(1.05e18);

    collateralAuctionHouse.modifyParameters('systemCoinOracle', address(systemCoinMedian));
    collateralAuctionHouse.modifyParameters('minSystemCoinMedianDeviation', 0.89e18);
    collateralAuctionHouse.modifyParameters('lowerSystemCoinMedianDeviation', 0.95e18);
    collateralAuctionHouse.modifyParameters('upperSystemCoinMedianDeviation', 0.9e18);

    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether - 131_578_947_368_421_052);
    assertEq(amountToRaise, 25 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether - 131_578_947_368_421_052
    );
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 131_578_947_368_421_052
    );
  }

  function test_consecutive_small_bids() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    for (uint256 i = 0; i < 10; i++) {
      Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
    }

    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid,
      1 ether - 736_842_105_263_157_900
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 1 ether - 263_157_894_736_842_100);
  }

  function test_settle_auction() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(2 * RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    hevm.warp(block.timestamp + collateralAuctionHouse.totalAuctionLength() + 1);
    collateralAuctionHouse.settleAuction(id);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(1000 ether));

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 1 ether);
    assertEq(amountToRaise, 50 * RAD);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 0);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 1 ether);
    assertEq(safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 0);
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function testFail_terminate_inexistent() public {
    collateralAuctionHouse.terminateAuctionPrematurely(1);
  }

  function test_terminateAuctionPrematurely() public {
    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(2 * RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 25 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(975 ether));
    collateralAuctionHouse.terminateAuctionPrematurely(1);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

    (uint256 amountToSell, uint256 amountToRaise,,,,,,,) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 25 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(safeEngine.tokenCollateral('collateralType', address(this)), 999_736_842_105_263_157_895);
    assertEq(uint256(999_736_842_105_263_157_895).add(263_157_894_736_842_105), 1000 ether);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid, 263_157_894_736_842_105
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  // Custom tests for the increasing discount implementation
  function test_small_discount_change_rate_bid_right_away() public {
    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', 999_998_607_628_240_588_157_433_861); // -0.5% per hour
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.93e18);

    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

    (
      uint256 amountToSell,
      uint256 amountToRaise,
      uint256 currentDiscount,
      ,
      uint256 perSecondDiscountUpdateRate,
      uint256 latestDiscountUpdateTime,
      ,
      ,
    ) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 742_105_263_157_894_737);
    assertEq(amountToRaise, RAY * WAD);
    assertEq(currentDiscount, collateralAuctionHouse.minDiscount());
    assertEq(perSecondDiscountUpdateRate, 999_998_607_628_240_588_157_433_861);
    assertEq(latestDiscountUpdateTime, block.timestamp);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 742_105_263_157_894_737);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid,
      1 ether - 742_105_263_157_894_737
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function test_small_discount_change_rate_bid_after_half_rate_timeline() public {
    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', 999_998_607_628_240_588_157_433_861); // -0.5% per hour
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.93e18);

    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    hevm.warp(block.timestamp + 30 minutes);
    Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

    (
      uint256 amountToSell,
      uint256 amountToRaise,
      uint256 currentDiscount,
      ,
      uint256 perSecondDiscountUpdateRate,
      uint256 latestDiscountUpdateTime,
      ,
      ,
    ) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 741_458_098_434_345_369);
    assertEq(amountToRaise, RAY * WAD);
    assertEq(currentDiscount, 947_622_023_804_850_158);
    assertEq(perSecondDiscountUpdateRate, 999_998_607_628_240_588_157_433_861);
    assertEq(latestDiscountUpdateTime, block.timestamp);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 741_458_098_434_345_369);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid,
      1 ether - 741_458_098_434_345_369
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function test_small_discount_change_rate_bid_end_rate_timeline() public {
    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', 999_998_607_628_240_588_157_433_861); // -0.5% per hour
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.93e18);

    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    hevm.warp(block.timestamp + 1 hours);
    Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

    (
      uint256 amountToSell,
      uint256 amountToRaise,
      uint256 currentDiscount,
      ,
      uint256 perSecondDiscountUpdateRate,
      uint256 latestDiscountUpdateTime,
      ,
      ,
    ) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 736_559_139_784_946_237);
    assertEq(amountToRaise, RAY * WAD);
    assertEq(currentDiscount, 930_000_000_000_000_000);
    assertEq(perSecondDiscountUpdateRate, 999_998_607_628_240_588_157_433_861);
    assertEq(latestDiscountUpdateTime, block.timestamp);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 736_559_139_784_946_237);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid,
      1 ether - 736_559_139_784_946_237
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function test_small_discount_change_rate_bid_long_after_rate_timeline() public {
    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', 999_998_607_628_240_588_157_433_861); // -0.5% per hour
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.93e18);

    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    hevm.warp(block.timestamp + 3650 days);
    Guy(ali).buyCollateral_increasingDiscount(id, 49 * WAD);
    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(951 ether));

    (
      uint256 amountToSell,
      uint256 amountToRaise,
      uint256 currentDiscount,
      ,
      uint256 perSecondDiscountUpdateRate,
      uint256 latestDiscountUpdateTime,
      ,
      ,
    ) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 736_559_139_784_946_237);
    assertEq(amountToRaise, RAY * WAD);
    assertEq(currentDiscount, 930_000_000_000_000_000);
    assertEq(perSecondDiscountUpdateRate, 999_998_607_628_240_588_157_433_861);
    assertEq(latestDiscountUpdateTime, block.timestamp);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 49 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 736_559_139_784_946_237);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid,
      1 ether - 736_559_139_784_946_237
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 0);
  }

  function test_bid_multi_times_at_different_timestamps() public {
    collateralAuctionHouse.modifyParameters('perSecondDiscountUpdateRate', 999_998_607_628_240_588_157_433_861); // -0.5% per hour
    collateralAuctionHouse.modifyParameters('maxDiscount', 0.93e18);

    oracleRelayer.modifyParameters('redemptionPrice', abi.encode(RAY));
    collateralFSM.set_val(200 ether);
    safeEngine.createUnbackedDebt(address(0), ali, rad(200 * RAD - 200 ether));

    uint256 collateralAmountPreBid = safeEngine.tokenCollateral('collateralType', address(ali));

    uint256 id = collateralAuctionHouse.startAuction({
      amountToSell: 1 ether,
      amountToRaise: 50 * RAD,
      forgoneCollateralReceiver: safeAuctioned,
      auctionIncomeRecipient: auctionIncomeRecipient,
      initialBid: 0
    });

    for (uint256 i = 0; i < 10; i++) {
      hevm.warp(block.timestamp + 1 minutes);
      Guy(ali).buyCollateral_increasingDiscount(id, 5 * WAD);
    }

    assertEq(liquidationEngine.currentOnAuctionSystemCoins(), rad(950 ether));

    (
      uint256 amountToSell,
      uint256 amountToRaise,
      uint256 currentDiscount,
      ,
      uint256 perSecondDiscountUpdateRate,
      uint256 latestDiscountUpdateTime,
      ,
      ,
    ) = collateralAuctionHouse.bids(id);
    assertEq(amountToSell, 0);
    assertEq(amountToRaise, 0);
    assertEq(currentDiscount, 0);
    assertEq(perSecondDiscountUpdateRate, 0);
    assertEq(latestDiscountUpdateTime, 0);

    assertEq(safeEngine.coinBalance(auctionIncomeRecipient), 50 * RAD);
    assertEq(safeEngine.tokenCollateral('collateralType', address(collateralAuctionHouse)), 0);
    assertEq(
      safeEngine.tokenCollateral('collateralType', address(ali)) - collateralAmountPreBid,
      1 ether - 736_721_153_320_545_015
    );
    assertEq(safeEngine.tokenCollateral('collateralType', address(safeAuctioned)), 736_721_153_320_545_015);
  }
}
