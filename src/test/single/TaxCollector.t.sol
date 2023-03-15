pragma solidity 0.6.7;
pragma experimental ABIEncoderV2;

import 'ds-test/test.sol';

import {TaxCollector} from '../../contracts/TaxCollector.sol';
import {SAFEEngine} from '../../contracts/SAFEEngine.sol';

abstract contract Hevm {
  function warp(uint256) public virtual;
}

abstract contract SAFEEngineLike {
  function collateralTypes(bytes32)
    public
    view
    virtual
    returns (
      uint256 debtAmount,
      uint256 accumulatedRate,
      uint256 safetyPrice,
      uint256 debtCeiling,
      uint256 debtFloor,
      uint256 liquidationPrice
    );
}

contract SingleTaxCollectorTest is DSTest {
  Hevm hevm;
  TaxCollector taxCollector;
  SAFEEngine safeEngine;

  function ray(uint256 wad_) internal pure returns (uint256) {
    return wad_ * 10 ** 9;
  }

  function rad(uint256 wad_) internal pure returns (uint256) {
    return wad_ * 10 ** 27;
  }

  function wad(uint256 rad_) internal pure returns (uint256) {
    return rad_ / 10 ** 27;
  }

  function wad(int256 rad_) internal pure returns (uint256) {
    return uint256(rad_ / 10 ** 27);
  }

  function updateTime(bytes32 collateralType) internal view returns (uint256) {
    (uint256 stabilityFee, uint256 updateTime_) = taxCollector.collateralTypes(collateralType);
    stabilityFee;
    return updateTime_;
  }

  function debtAmount(bytes32 collateralType) internal view returns (uint256 debtAmountV) {
    (debtAmountV,,,,,) = SAFEEngineLike(address(safeEngine)).collateralTypes(collateralType);
  }

  function accumulatedRate(bytes32 collateralType) internal view returns (uint256 accumulatedRateV) {
    (, accumulatedRateV,,,,) = SAFEEngineLike(address(safeEngine)).collateralTypes(collateralType);
  }

  function debtCeiling(bytes32 collateralType) internal view returns (uint256 debtCeilingV) {
    (,,, debtCeilingV,,) = SAFEEngineLike(address(safeEngine)).collateralTypes(collateralType);
  }

  address ali = address(bytes20('ali'));
  address bob = address(bytes20('bob'));
  address char = address(bytes20('char'));

  function setUp() public {
    hevm = Hevm(0x7109709ECfa91a80626fF3989D68f67F5b1DD12D);
    hevm.warp(604_411_200);

    safeEngine = new SAFEEngine();
    taxCollector = new TaxCollector(address(safeEngine));
    safeEngine.addAuthorization(address(taxCollector));
    safeEngine.initializeCollateralType('i');

    draw('i', 100 ether);
  }

  function draw(bytes32 collateralType, uint256 coin) internal {
    safeEngine.modifyParameters('globalDebtCeiling', safeEngine.globalDebtCeiling() + rad(coin));
    safeEngine.modifyParameters(collateralType, 'debtCeiling', debtCeiling(collateralType) + rad(coin));
    safeEngine.modifyParameters(collateralType, 'safetyPrice', 10 ** 27 * 10_000 ether);
    address self = address(this);
    safeEngine.modifyCollateralBalance(collateralType, self, 10 ** 27 * 1 ether);
    safeEngine.modifySAFECollateralization(collateralType, self, self, self, int256(1 ether), int256(coin));
  }

  function test_collect_tax_setup() public {
    hevm.warp(0);
    assertEq(uint256(now), 0);
    hevm.warp(1);
    assertEq(uint256(now), 1);
    hevm.warp(2);
    assertEq(uint256(now), 2);
    assertEq(debtAmount('i'), 100 ether);
  }

  function test_collect_tax_updates_updateTime() public {
    taxCollector.initializeCollateralType('i');
    assertEq(updateTime('i'), now);

    taxCollector.modifyParameters('i', 'stabilityFee', 10 ** 27);
    taxCollector.taxSingle('i');
    assertEq(updateTime('i'), now);
    hevm.warp(now + 1);
    assertEq(updateTime('i'), now - 1);
    taxCollector.taxSingle('i');
    assertEq(updateTime('i'), now);
    hevm.warp(now + 1 days);
    taxCollector.taxSingle('i');
    assertEq(updateTime('i'), now);
  }

  function test_collect_tax_modifyParameters() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 10 ** 27);
    taxCollector.taxSingle('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_000_564_701_133_626_865_910_626); // 5% / day
  }

  function test_collect_tax_0d() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_000_564_701_133_626_865_910_626); // 5% / day
    assertEq(safeEngine.coinBalance(ali), rad(0 ether));
    taxCollector.taxSingle('i');
    assertEq(safeEngine.coinBalance(ali), rad(0 ether));
  }

  function test_collect_tax_1d() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_000_564_701_133_626_865_910_626); // 5% / day
    hevm.warp(now + 1 days);
    assertEq(wad(safeEngine.coinBalance(ali)), 0 ether);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 5 ether);
  }

  function test_collect_tax_2d() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_000_564_701_133_626_865_910_626); // 5% / day

    hevm.warp(now + 2 days);
    assertEq(wad(safeEngine.coinBalance(ali)), 0 ether);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 10.25 ether);
  }

  function test_collect_tax_3d() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_000_564_701_133_626_865_910_626); // 5% / day
    hevm.warp(now + 3 days);
    assertEq(wad(safeEngine.coinBalance(ali)), 0 ether);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 15.7625 ether);
  }

  function test_collect_tax_negative_3d() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 999_999_706_969_857_929_985_428_567); // -2.5% / day
    hevm.warp(now + 3 days);
    assertEq(wad(safeEngine.coinBalance(address(this))), 100 ether);
    safeEngine.transferInternalCoins(address(this), ali, rad(100 ether));
    assertEq(wad(safeEngine.coinBalance(ali)), 100 ether);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 92.6859375 ether);
  }

  function test_collect_tax_multi() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_000_564_701_133_626_865_910_626); // 5% / day
    hevm.warp(now + 1 days);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 5 ether);
    taxCollector.modifyParameters('i', 'stabilityFee', 1_000_001_103_127_689_513_476_993_127); // 10% / day
    hevm.warp(now + 1 days);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 15.5 ether);
    assertEq(wad(safeEngine.globalDebt()), 115.5 ether);
    assertEq(accumulatedRate('i') / 10 ** 9, 1.155 ether);
  }

  function test_collect_tax_global_stability_fee() public {
    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000); // 5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 1_000_000_000_000_000_000_000_000_000); // 0% / second
    taxCollector.modifyParameters('globalStabilityFee', uint256(50_000_000_000_000_000_000_000_000)); // 5% / second
    hevm.warp(now + 1);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 10 ether);
  }

  function test_collect_tax_all_positive() public {
    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000); // 5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 1_030_000_000_000_000_000_000_000_000); // 3% / second
    taxCollector.modifyParameters('globalStabilityFee', uint256(50_000_000_000_000_000_000_000_000)); // 5% / second

    hevm.warp(now + 1);
    taxCollector.taxMany(0, taxCollector.collateralListLength() - 1);

    assertEq(wad(safeEngine.coinBalance(ali)), 18 ether);

    (, uint256 updatedTime) = taxCollector.collateralTypes('i');
    assertEq(updatedTime, now);
    (, updatedTime) = taxCollector.collateralTypes('j');
    assertEq(updatedTime, now);

    assertTrue(taxCollector.collectedManyTax(0, 1));
  }

  function test_collect_tax_all_some_negative() public {
    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);
    taxCollector.modifyParameters('j', 'stabilityFee', 900_000_000_000_000_000_000_000_000);

    hevm.warp(now + 10);
    taxCollector.taxSingle('i');
    assertEq(wad(safeEngine.coinBalance(ali)), 62_889_462_677_744_140_625);

    taxCollector.taxSingle('j');
    assertEq(wad(safeEngine.coinBalance(ali)), 0);

    (, uint256 updatedTime) = taxCollector.collateralTypes('i');
    assertEq(updatedTime, now);
    (, updatedTime) = taxCollector.collateralTypes('j');
    assertEq(updatedTime, now);

    assertTrue(taxCollector.collectedManyTax(0, 1));
  }

  function testFail_add_same_tax_receiver_twice() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 10);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('i', 2, ray(1 ether), address(this));
  }

  function testFail_cut_at_hundred() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 10);
    taxCollector.modifyParameters('i', 0, ray(100 ether), address(this));
  }

  function testFail_add_over_maxSecondaryReceivers() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 1);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('i', 2, ray(1 ether), ali);
  }

  function testFail_modify_cut_total_over_hundred() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 1);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('i', 1, ray(100.1 ether), address(this));
  }

  function testFail_remove_past_node() public {
    // Add
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    // Remove
    taxCollector.modifyParameters('i', 1, 0, address(this));
    taxCollector.modifyParameters('i', 1, 0, address(this));
  }

  function testFail_tax_receiver_primaryTaxReceiver() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 1);
    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('i', 1, ray(1 ether), ali);
  }

  function testFail_tax_receiver_null() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 1);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(0));
  }

  function test_add_tax_secondaryTaxReceivers() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    assertEq(taxCollector.secondaryReceiverAllotedTax('i'), ray(1 ether));
    assertEq(taxCollector.latestSecondaryReceiver(), 1);
    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(this));
    (uint256 canTakeBackTax, uint256 taxPercentage) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(canTakeBackTax, 0);
    assertEq(taxPercentage, ray(1 ether));
    assertEq(taxCollector.latestSecondaryReceiver(), 1);
  }

  function test_modify_tax_receiver_cut() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 1);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('i', 1, ray(99.9 ether), address(this));
    uint256 Cut = taxCollector.secondaryReceiverAllotedTax('i');
    assertEq(Cut, ray(99.9 ether));
    (, uint256 cut) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(cut, ray(99.9 ether));
  }

  function test_remove_some_tax_secondaryTaxReceivers() public {
    // Add
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('i', 2, ray(98 ether), ali);
    assertEq(taxCollector.secondaryReceiverAllotedTax('i'), ray(99 ether));
    assertEq(taxCollector.latestSecondaryReceiver(), 2);
    assertEq(taxCollector.usedSecondaryReceiver(ali), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(ali), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(2), ali);
    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(this));
    (uint256 take, uint256 cut) = taxCollector.secondaryTaxReceivers('i', 2);
    assertEq(take, 0);
    assertEq(cut, ray(98 ether));
    assertEq(taxCollector.latestSecondaryReceiver(), 2);
    // Remove
    taxCollector.modifyParameters('i', 1, 0, address(this));
    assertEq(taxCollector.secondaryReceiverAllotedTax('i'), ray(98 ether));
    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 0);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 0);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(0));
    (take, cut) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(take, 0);
    assertEq(cut, 0);
    assertEq(taxCollector.latestSecondaryReceiver(), 2);
    assertEq(taxCollector.usedSecondaryReceiver(ali), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(ali), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(2), ali);
  }

  function test_remove_all_secondaryTaxReceivers() public {
    // Add
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('i', 2, ray(98 ether), ali);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(this));
    assertEq(taxCollector.secondaryReceiverAccounts(2), ali);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(ali), 1);
    // Remove
    taxCollector.modifyParameters('i', 2, 0, ali);
    taxCollector.modifyParameters('i', 1, 0, address(this));
    uint256 Cut = taxCollector.secondaryReceiverAllotedTax('i');
    assertEq(Cut, 0);
    assertEq(taxCollector.usedSecondaryReceiver(ali), 0);
    assertEq(taxCollector.usedSecondaryReceiver(address(0)), 0);
    assertEq(taxCollector.secondaryReceiverRevenueSources(ali), 0);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 0);
    assertEq(taxCollector.secondaryReceiverAccounts(2), address(0));
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(0));
    (uint256 take, uint256 cut) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(take, 0);
    assertEq(cut, 0);
    assertEq(taxCollector.latestSecondaryReceiver(), 0);
  }

  function test_add_remove_add_secondaryTaxReceivers() public {
    // Add
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    assertTrue(taxCollector.isSecondaryReceiver(1));
    // Remove
    taxCollector.modifyParameters('i', 1, 0, address(this));
    assertTrue(!taxCollector.isSecondaryReceiver(1));
    // Add again
    taxCollector.modifyParameters('i', 2, ray(1 ether), address(this));
    assertEq(taxCollector.secondaryReceiverAllotedTax('i'), ray(1 ether));
    assertEq(taxCollector.latestSecondaryReceiver(), 2);
    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(2), address(this));
    assertEq(taxCollector.secondaryReceiversAmount(), 1);
    assertTrue(taxCollector.isSecondaryReceiver(2));
    (uint256 take, uint256 cut) = taxCollector.secondaryTaxReceivers('i', 2);
    assertEq(take, 0);
    assertEq(cut, ray(1 ether));
    // Remove again
    taxCollector.modifyParameters('i', 2, 0, address(this));
    assertEq(taxCollector.secondaryReceiverAllotedTax('i'), 0);
    assertEq(taxCollector.latestSecondaryReceiver(), 0);
    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 0);
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 0);
    assertEq(taxCollector.secondaryReceiverAccounts(2), address(0));
    assertTrue(!taxCollector.isSecondaryReceiver(2));
    (take, cut) = taxCollector.secondaryTaxReceivers('i', 2);
    assertEq(take, 0);
    assertEq(cut, 0);
  }

  function test_multi_collateral_types_receivers() public {
    taxCollector.modifyParameters('maxSecondaryReceivers', 1);

    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);
    taxCollector.initializeCollateralType('j');

    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    taxCollector.modifyParameters('j', 1, ray(1 ether), address(0));

    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(this));
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 2);
    assertEq(taxCollector.latestSecondaryReceiver(), 1);

    taxCollector.modifyParameters('i', 1, 0, address(0));

    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 1);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(this));
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 1);
    assertEq(taxCollector.latestSecondaryReceiver(), 1);

    taxCollector.modifyParameters('j', 1, 0, address(0));

    assertEq(taxCollector.usedSecondaryReceiver(address(this)), 0);
    assertEq(taxCollector.secondaryReceiverAccounts(1), address(0));
    assertEq(taxCollector.secondaryReceiverRevenueSources(address(this)), 0);
    assertEq(taxCollector.latestSecondaryReceiver(), 0);
  }

  function test_toggle_receiver_take() public {
    // Add
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(1 ether), address(this));
    // Toggle
    taxCollector.modifyParameters('i', 1, 1);
    (uint256 take,) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(take, 1);

    taxCollector.modifyParameters('i', 1, 5);
    (take,) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(take, 5);

    taxCollector.modifyParameters('i', 1, 0);
    (take,) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(take, 0);
  }

  function test_add_secondaryTaxReceivers_single_collateral_type_collect_tax_positive() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(40 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(45 ether), char);

    assertEq(taxCollector.latestSecondaryReceiver(), 2);
    hevm.warp(now + 10);
    (, int256 currentRates) = taxCollector.taxSingleOutcome('i');
    taxCollector.taxSingle('i');
    assertEq(taxCollector.latestSecondaryReceiver(), 2);

    assertEq(wad(safeEngine.coinBalance(ali)), 9_433_419_401_661_621_093);
    assertEq(wad(safeEngine.coinBalance(bob)), 25_155_785_071_097_656_250);
    assertEq(wad(safeEngine.coinBalance(char)), 28_300_258_204_984_863_281);

    assertEq(wad(safeEngine.coinBalance(ali)) * ray(100 ether) / uint256(currentRates), 1_499_999_999_999_999_999_880);
    assertEq(wad(safeEngine.coinBalance(bob)) * ray(100 ether) / uint256(currentRates), 4_000_000_000_000_000_000_000);
    assertEq(wad(safeEngine.coinBalance(char)) * ray(100 ether) / uint256(currentRates), 4_499_999_999_999_999_999_960);
  }

  function testFail_tax_when_safe_engine_is_disabled() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(40 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(45 ether), char);

    safeEngine.disableContract();
    hevm.warp(now + 10);
    taxCollector.taxSingle('i');
  }

  function test_add_secondaryTaxReceivers_multi_collateral_types_collect_tax_positive() public {
    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);

    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('j', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    taxCollector.modifyParameters('i', 1, ray(40 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(45 ether), char);

    hevm.warp(now + 10);
    taxCollector.taxMany(0, taxCollector.collateralListLength() - 1);

    assertEq(wad(safeEngine.coinBalance(ali)), 72_322_882_079_405_761_718);
    assertEq(wad(safeEngine.coinBalance(bob)), 25_155_785_071_097_656_250);
    assertEq(wad(safeEngine.coinBalance(char)), 28_300_258_204_984_863_281);

    taxCollector.modifyParameters('j', 1, ray(25 ether), bob);
    taxCollector.modifyParameters('j', 2, ray(33 ether), char);

    hevm.warp(now + 10);
    taxCollector.taxMany(0, taxCollector.collateralListLength() - 1);

    assertEq(wad(safeEngine.coinBalance(ali)), 130_713_857_546_323_549_197);
    assertEq(wad(safeEngine.coinBalance(bob)), 91_741_985_164_951_273_550);
    assertEq(wad(safeEngine.coinBalance(char)), 108_203_698_317_609_204_041);

    assertEq(taxCollector.secondaryReceiverAllotedTax('i'), ray(85 ether));
    assertEq(taxCollector.latestSecondaryReceiver(), 2);
    assertEq(taxCollector.usedSecondaryReceiver(bob), 1);
    assertEq(taxCollector.usedSecondaryReceiver(char), 1);
    assertEq(taxCollector.secondaryReceiverRevenueSources(bob), 2);
    assertEq(taxCollector.secondaryReceiverRevenueSources(char), 2);
    assertEq(taxCollector.secondaryReceiverAccounts(1), bob);
    assertEq(taxCollector.secondaryReceiverAccounts(2), char);
    assertEq(taxCollector.secondaryReceiversAmount(), 2);
    assertTrue(taxCollector.isSecondaryReceiver(1));
    assertTrue(taxCollector.isSecondaryReceiver(2));

    (uint256 take, uint256 cut) = taxCollector.secondaryTaxReceivers('i', 1);
    assertEq(take, 0);
    assertEq(cut, ray(40 ether));

    (take, cut) = taxCollector.secondaryTaxReceivers('i', 2);
    assertEq(take, 0);
    assertEq(cut, ray(45 ether));

    (take, cut) = taxCollector.secondaryTaxReceivers('j', 1);
    assertEq(take, 0);
    assertEq(cut, ray(25 ether));

    (take, cut) = taxCollector.secondaryTaxReceivers('j', 2);
    assertEq(take, 0);
    assertEq(cut, ray(33 ether));
  }

  function test_add_secondaryTaxReceivers_single_collateral_type_toggle_collect_tax_negative() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(5 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(10 ether), char);
    taxCollector.modifyParameters('i', 1, 1);
    taxCollector.modifyParameters('i', 2, 1);

    hevm.warp(now + 5);
    taxCollector.taxSingle('i');

    assertEq(wad(safeEngine.coinBalance(ali)), 23_483_932_812_500_000_000);
    assertEq(wad(safeEngine.coinBalance(bob)), 1_381_407_812_500_000_000);
    assertEq(wad(safeEngine.coinBalance(char)), 2_762_815_625_000_000_000);

    taxCollector.modifyParameters('i', 'stabilityFee', 900_000_000_000_000_000_000_000_000);
    taxCollector.modifyParameters('i', 1, ray(10 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(20 ether), char);

    hevm.warp(now + 5);
    taxCollector.taxSingle('i');

    assertEq(wad(safeEngine.coinBalance(ali)), 0);
    assertEq(wad(safeEngine.coinBalance(bob)), 0);
    assertEq(wad(safeEngine.coinBalance(char)), 0);
  }

  function test_add_secondaryTaxReceivers_multi_collateral_types_toggle_collect_tax_negative() public {
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('j', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(5 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(10 ether), char);
    taxCollector.modifyParameters('i', 1, 1);
    taxCollector.modifyParameters('i', 2, 1);

    hevm.warp(now + 5);
    taxCollector.taxMany(0, taxCollector.collateralListLength() - 1);

    taxCollector.modifyParameters('i', 'stabilityFee', 900_000_000_000_000_000_000_000_000);
    taxCollector.modifyParameters('j', 'stabilityFee', 900_000_000_000_000_000_000_000_000);
    taxCollector.modifyParameters('i', 1, ray(10 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(20 ether), char);
    taxCollector.modifyParameters('j', 1, ray(10 ether), bob);
    taxCollector.modifyParameters('j', 2, ray(20 ether), char);

    hevm.warp(now + 5);
    taxCollector.taxMany(0, taxCollector.collateralListLength() - 1);

    assertEq(wad(safeEngine.coinBalance(ali)), 0);
    assertEq(wad(safeEngine.coinBalance(bob)), 0);
    assertEq(wad(safeEngine.coinBalance(char)), 0);
  }

  function test_add_secondaryTaxReceivers_no_toggle_collect_tax_negative() public {
    // Setup
    taxCollector.initializeCollateralType('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000);

    taxCollector.modifyParameters('primaryTaxReceiver', ali);
    taxCollector.modifyParameters('maxSecondaryReceivers', 2);
    taxCollector.modifyParameters('i', 1, ray(5 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(10 ether), char);

    hevm.warp(now + 5);
    taxCollector.taxSingle('i');

    assertEq(wad(safeEngine.coinBalance(ali)), 23_483_932_812_500_000_000);
    assertEq(wad(safeEngine.coinBalance(bob)), 1_381_407_812_500_000_000);
    assertEq(wad(safeEngine.coinBalance(char)), 2_762_815_625_000_000_000);

    taxCollector.modifyParameters('i', 'stabilityFee', 900_000_000_000_000_000_000_000_000);
    taxCollector.modifyParameters('i', 1, ray(10 ether), bob);
    taxCollector.modifyParameters('i', 2, ray(20 ether), char);

    hevm.warp(now + 5);
    taxCollector.taxSingle('i');

    assertEq(wad(safeEngine.coinBalance(ali)), 0);
    assertEq(wad(safeEngine.coinBalance(bob)), 1_381_407_812_500_000_000);
    assertEq(wad(safeEngine.coinBalance(char)), 2_762_815_625_000_000_000);
  }

  function test_collectedManyTax() public {
    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000); // 5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 1_000_000_000_000_000_000_000_000_000); // 0% / second
    taxCollector.modifyParameters('globalStabilityFee', uint256(50_000_000_000_000_000_000_000_000)); // 5% / second

    hevm.warp(now + 1);
    assertTrue(!taxCollector.collectedManyTax(0, 1));

    taxCollector.taxSingle('i');
    assertTrue(taxCollector.collectedManyTax(0, 0));
    assertTrue(!taxCollector.collectedManyTax(0, 1));
  }

  function test_modify_stabilityFee() public {
    taxCollector.initializeCollateralType('i');
    hevm.warp(now + 1);
    taxCollector.taxSingle('i');
    taxCollector.modifyParameters('i', 'stabilityFee', 1);
  }

  function testFail_modify_stabilityFee() public {
    taxCollector.initializeCollateralType('i');
    hevm.warp(now + 1);
    taxCollector.modifyParameters('i', 'stabilityFee', 1);
  }

  function test_taxManyOutcome_all_untaxed_positive_rates() public {
    safeEngine.initializeCollateralType('j');
    draw('i', 100 ether);
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000); // 5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 1_030_000_000_000_000_000_000_000_000); // 3% / second
    taxCollector.modifyParameters('globalStabilityFee', uint256(50_000_000_000_000_000_000_000_000)); // 5% / second

    hevm.warp(now + 1);
    (bool ok, int256 rad) = taxCollector.taxManyOutcome(0, 1);
    assertTrue(ok);
    assertEq(uint256(rad), 28 * 10 ** 45);
  }

  function test_taxManyOutcome_some_untaxed_positive_rates() public {
    safeEngine.initializeCollateralType('j');
    draw('i', 100 ether);
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000); // 5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 1_030_000_000_000_000_000_000_000_000); // 3% / second
    taxCollector.modifyParameters('globalStabilityFee', uint256(50_000_000_000_000_000_000_000_000)); // 5% / second

    hevm.warp(now + 1);
    taxCollector.taxSingle('i');
    (bool ok, int256 rad) = taxCollector.taxManyOutcome(0, 1);
    assertTrue(ok);
    assertEq(uint256(rad), 8 * 10 ** 45);
  }

  function test_taxManyOutcome_all_untaxed_negative_rates() public {
    safeEngine.initializeCollateralType('j');
    draw('i', 100 ether);
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 950_000_000_000_000_000_000_000_000); // -5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 930_000_000_000_000_000_000_000_000); // -3% / second

    hevm.warp(now + 1);
    (bool ok, int256 rad) = taxCollector.taxManyOutcome(0, 1);
    assertTrue(!ok);
    assertEq(rad, -17 * 10 ** 45);
  }

  function test_taxManyOutcome_all_untaxed_mixed_rates() public {
    safeEngine.initializeCollateralType('j');
    draw('j', 100 ether);

    taxCollector.initializeCollateralType('i');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    taxCollector.modifyParameters('i', 'stabilityFee', 950_000_000_000_000_000_000_000_000); // -5% / second
    taxCollector.modifyParameters('j', 'stabilityFee', 1_050_000_000_000_000_000_000_000_000); // 5% / second

    hevm.warp(now + 1);
    (bool ok, int256 rad) = taxCollector.taxManyOutcome(0, 1);
    assertTrue(ok);
    assertEq(rad, 0);
  }

  function test_negative_tax_accumulated_goes_negative() public {
    safeEngine.initializeCollateralType('j');
    taxCollector.initializeCollateralType('j');
    taxCollector.modifyParameters('primaryTaxReceiver', ali);

    draw('j', 100 ether);
    safeEngine.transferInternalCoins(address(this), ali, safeEngine.coinBalance(address(this)));
    assertEq(wad(safeEngine.coinBalance(ali)), 200 ether);

    taxCollector.modifyParameters('j', 'stabilityFee', 999_999_706_969_857_929_985_428_567); // -2.5% / day

    hevm.warp(now + 3 days);
    taxCollector.taxSingle('j');
    assertEq(wad(safeEngine.coinBalance(ali)), 192.6859375 ether);

    (, uint256 accumulatedRate,,,,) = safeEngine.collateralTypes('j');
    assertEq(accumulatedRate, 926_859_375_000_000_000_000_022_885);
  }
}