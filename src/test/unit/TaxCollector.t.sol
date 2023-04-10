// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TaxCollectorForTest, ITaxCollector} from '@contracts/for-test/TaxCollectorForTest.sol';
import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {IAuthorizable} from '@interfaces/IAuthorizable.sol';
import {Math, RAY} from '@libraries/Math.sol';
import {LinkedList} from '@libraries/LinkedList.sol';
import {HaiTest, stdStorage, StdStorage} from '@test/utils/HaiTest.t.sol';

abstract contract Base is HaiTest {
  using Math for uint256;
  using stdStorage for StdStorage;

  address deployer = label('deployer');
  address user = label('user');

  ISAFEEngine safeEngine = ISAFEEngine(mockContract('SafeEngine'));

  TaxCollectorForTest taxCollector;

  uint256 constant WHOLE_TAX_CUT = 100e27; // RAY

  // SafeEngine storage
  uint256 coinBalance = RAY;
  uint256 debtAmount = 1e25;
  uint256 lastAccumulatedRate = 1e20;

  // TaxCollector storage
  address primaryTaxReceiver = newAddress();
  address secondaryReceiverAccountA = newAddress();
  address secondaryReceiverAccountB = newAddress();
  address secondaryReceiverAccountC = newAddress();
  address secondaryReceiverAccountD = newAddress();
  uint256 latestSecondaryReceiver = 3;
  uint256 oldestSecondaryReceiver = 1;
  uint256 secondaryReceiverAllotedTax = WHOLE_TAX_CUT / 2;
  uint256 taxPercentage = WHOLE_TAX_CUT / 4;
  uint256 canTakeBackTax = 1;
  uint256 globalStabilityFee = 1e15;
  uint256 stabilityFee = 1e10;
  uint256 updateTime = block.timestamp - 100;

  // Input parameters
  bytes32 collateralTypeA = 'collateralTypeA';
  bytes32 collateralTypeB = 'collateralTypeB';
  bytes32 collateralTypeC = 'collateralTypeC';
  address receiver = newAddress();
  uint256 receiverListPosition = uint160(newAddress());

  function setUp() public virtual {
    vm.prank(deployer);
    taxCollector = new TaxCollectorForTest(address(safeEngine));
    label(address(taxCollector), 'TaxCollector');
  }

  function setUpTaxManyOutcome() public {
    setUpTaxSingleOutcome(collateralTypeA);
    setUpTaxSingleOutcome(collateralTypeB);
    setUpTaxSingleOutcome(collateralTypeC);

    // SafeEngine storage
    _mockCoinBalance(primaryTaxReceiver, coinBalance);

    // TaxCollector storage
    _mockPrimaryTaxReceiver(primaryTaxReceiver);
    _mockCollateralList(0, 'collateralType');
    _mockCollateralList(1, collateralTypeA);
    _mockCollateralList(2, collateralTypeB);
    _mockCollateralList(3, collateralTypeC);
  }

  function setUpTaxSingleOutcome(bytes32 _collateralType) public {
    // SafeEngine storage
    _mockCollateralType(_collateralType, debtAmount, lastAccumulatedRate, 0, 0, 0, 0);

    // TaxCollector storage
    _mockCollateralType(_collateralType, stabilityFee, updateTime);
    _mockGlobalStabilityFee(globalStabilityFee);
  }

  function setUpTaxMany() public {
    setUpTaxManyOutcome();

    setUpSplitTaxIncome(collateralTypeA);
    setUpSplitTaxIncome(collateralTypeB);
    setUpSplitTaxIncome(collateralTypeC);
  }

  function setUpTaxSingle(bytes32 _collateralType) public {
    setUpTaxSingleOutcome(_collateralType);

    setUpSplitTaxIncome(_collateralType);
  }

  function setUpSplitTaxIncome(bytes32 _collateralType) public {
    vm.assume(latestSecondaryReceiver <= receiverListPosition);

    setUpDistributeTax(_collateralType);

    // SafeEngine storage
    _mockCoinBalance(secondaryReceiverAccountA, coinBalance);
    _mockCoinBalance(secondaryReceiverAccountB, coinBalance);
    _mockCoinBalance(secondaryReceiverAccountC, coinBalance);
    _mockCoinBalance(secondaryReceiverAccountD, coinBalance);

    // TaxCollector storage
    _mockSecondaryReceiverAccount(latestSecondaryReceiver, secondaryReceiverAccountA);
    _mockSecondaryReceiverAccount(latestSecondaryReceiver - 1, secondaryReceiverAccountB);
    _mockSecondaryReceiverAccount(oldestSecondaryReceiver, secondaryReceiverAccountC);
    _mockSecondaryReceiverAccount(0, secondaryReceiverAccountD);
    _mockSecondaryTaxReceiver(_collateralType, latestSecondaryReceiver, canTakeBackTax, taxPercentage);
    _mockSecondaryTaxReceiver(_collateralType, latestSecondaryReceiver - 1, canTakeBackTax, 0);
    _mockSecondaryTaxReceiver(_collateralType, oldestSecondaryReceiver, canTakeBackTax, taxPercentage);
    _mockSecondaryTaxReceiver(_collateralType, 0, canTakeBackTax, taxPercentage);
    _mockLatestSecondaryReceiver(latestSecondaryReceiver);
  }

  function setUpDistributeTax(bytes32 _collateralType) public {
    // SafeEngine storage
    _mockCoinBalance(primaryTaxReceiver, coinBalance);
    _mockCoinBalance(receiver, coinBalance);

    // TaxCollector storage
    _mockSecondaryReceiverAllotedTax(_collateralType, secondaryReceiverAllotedTax);
    _mockSecondaryTaxReceiver(_collateralType, receiverListPosition, canTakeBackTax, taxPercentage);
    _mockPrimaryTaxReceiver(primaryTaxReceiver);
  }

  function _mockCoinBalance(address _receiverAccount, uint256 _coinBalance) internal {
    vm.mockCall(
      address(safeEngine), abi.encodeCall(safeEngine.coinBalance, (_receiverAccount)), abi.encode(_coinBalance)
    );
  }

  function _mockCollateralType(
    bytes32 _collateralType,
    uint256 _debtAmount,
    uint256 _accumulatedRate,
    uint256 _safetyPrice,
    uint256 _debtCeiling,
    uint256 _debtFloor,
    uint256 _liquidationPrice
  ) internal {
    vm.mockCall(
      address(safeEngine),
      abi.encodeCall(safeEngine.collateralTypes, (_collateralType)),
      abi.encode(_debtAmount, _accumulatedRate, _safetyPrice, _debtCeiling, _debtFloor, _liquidationPrice)
    );
  }

  function _mockCollateralType(bytes32 _collateralType, uint256 _stabilityFee, uint256 _updateTime) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.collateralTypes.selector).with_key(_collateralType).depth(
      0
    ).checked_write(_stabilityFee);
    stdstore.target(address(taxCollector)).sig(ITaxCollector.collateralTypes.selector).with_key(_collateralType).depth(
      1
    ).checked_write(_updateTime);
  }

  function _mockSecondaryReceiverAllotedTax(bytes32 _collateralType, uint256 _secondaryReceiverAllotedTax) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.secondaryReceiverAllotedTax.selector).with_key(
      _collateralType
    ).checked_write(_secondaryReceiverAllotedTax);
  }

  function _mockSecondaryReceiverAccount(uint256 _position, address _receiverAccount) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.secondaryReceiverAccounts.selector).with_key(_position)
      .checked_write(_receiverAccount);
  }

  function _mockSecondaryTaxReceiver(
    bytes32 _collateralType,
    uint256 _position,
    uint256 _canTakeBackTax,
    uint256 _taxPercentage
  ) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.secondaryTaxReceivers.selector).with_key(_collateralType)
      .with_key(_position).depth(0).checked_write(_canTakeBackTax);
    stdstore.target(address(taxCollector)).sig(ITaxCollector.secondaryTaxReceivers.selector).with_key(_collateralType)
      .with_key(_position).depth(1).checked_write(_taxPercentage);
  }

  function _mockPrimaryTaxReceiver(address _primaryTaxReceiver) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.primaryTaxReceiver.selector).checked_write(
      _primaryTaxReceiver
    );
  }

  function _mockGlobalStabilityFee(uint256 _globalStabilityFee) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.globalStabilityFee.selector).checked_write(
      _globalStabilityFee
    );
  }

  function _mockLatestSecondaryReceiver(uint256 _latestSecondaryReceiver) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.latestSecondaryReceiver.selector).checked_write(
      _latestSecondaryReceiver
    );
  }

  function _mockCollateralList(uint256 _position, bytes32 _collateralType) internal {
    stdstore.target(address(taxCollector)).sig(ITaxCollector.collateralList.selector).with_key(_position).checked_write(
      _collateralType
    );
  }

  function _assumeCurrentTaxCut(
    uint256 _debtAmount,
    int256 _deltaRate,
    bool _isPrimaryTaxReceiver,
    bool _isAbsorbable
  ) internal returns (int256 _currentTaxCut) {
    if (_isPrimaryTaxReceiver) {
      receiver = primaryTaxReceiver;
      if (!_isAbsorbable) {
        vm.assume(
          _deltaRate <= -int256(WHOLE_TAX_CUT / secondaryReceiverAllotedTax) && _deltaRate >= -int256(WHOLE_TAX_CUT)
        );
        _currentTaxCut = (WHOLE_TAX_CUT - secondaryReceiverAllotedTax).mul(_deltaRate) / int256(WHOLE_TAX_CUT);
        vm.assume(_debtAmount <= coinBalance);
        vm.assume(-int256(coinBalance) > _debtAmount.mul(_currentTaxCut));
        _currentTaxCut = -int256(coinBalance) / int256(_debtAmount);
      } else {
        vm.assume(
          _deltaRate <= -int256(WHOLE_TAX_CUT / secondaryReceiverAllotedTax) && _deltaRate >= -int256(WHOLE_TAX_CUT)
            || _deltaRate >= int256(WHOLE_TAX_CUT / secondaryReceiverAllotedTax) && _deltaRate <= int256(WHOLE_TAX_CUT)
        );
        _currentTaxCut = (WHOLE_TAX_CUT - secondaryReceiverAllotedTax).mul(_deltaRate) / int256(WHOLE_TAX_CUT);
        vm.assume(_debtAmount == 0);
      }
    } else {
      if (!_isAbsorbable) {
        vm.assume(_deltaRate <= -int256(WHOLE_TAX_CUT / taxPercentage) && _deltaRate >= -int256(WHOLE_TAX_CUT));
        _currentTaxCut = int256(taxPercentage) * _deltaRate / int256(WHOLE_TAX_CUT);
        vm.assume(_debtAmount <= coinBalance);
        vm.assume(-int256(coinBalance) > _debtAmount.mul(_currentTaxCut));
        _currentTaxCut = -int256(coinBalance) / int256(_debtAmount);
      } else {
        vm.assume(
          _deltaRate <= -int256(WHOLE_TAX_CUT / taxPercentage) && _deltaRate >= -int256(WHOLE_TAX_CUT)
            || _deltaRate >= int256(WHOLE_TAX_CUT / taxPercentage) && _deltaRate <= int256(WHOLE_TAX_CUT)
        );
        _currentTaxCut = int256(taxPercentage) * _deltaRate / int256(WHOLE_TAX_CUT);
        vm.assume(_debtAmount <= WHOLE_TAX_CUT && -int256(coinBalance) <= _debtAmount.mul(_currentTaxCut));
      }
    }
  }
}

contract Unit_TaxCollector_Constructor is Base {
  function test_Set_SafeEngine(address _safeEngine) public {
    taxCollector = new TaxCollectorForTest(_safeEngine);

    assertEq(address(taxCollector.safeEngine()), _safeEngine);
  }
}

contract Unit_TaxCollector_InitializeCollateralType is Base {
  using stdStorage for StdStorage;

  event InitializeCollateralType(bytes32 _collateralType);

  function setUp() public override {
    Base.setUp();

    vm.startPrank(deployer);
  }

  function test_Revert_Unauthorized(bytes32 _collateralType) public {
    vm.expectRevert(IAuthorizable.Unauthorized.selector);

    vm.stopPrank();
    vm.prank(user);
    taxCollector.initializeCollateralType(_collateralType);
  }

  function test_Revert_CollateralTypeAlreadyInit(bytes32 _collateralType) public {
    _mockCollateralType(_collateralType, RAY, 0);

    vm.expectRevert('TaxCollector/collateral-type-already-init');

    taxCollector.initializeCollateralType(_collateralType);
  }

  function test_Set_CollateralTypeStabilityFee(bytes32 _collateralType) public {
    taxCollector.initializeCollateralType(_collateralType);

    (uint256 _stabilityFee,) = taxCollector.collateralTypes(_collateralType);

    assertEq(_stabilityFee, RAY);
  }

  function test_Set_CollateralTypeUpdateTime(bytes32 _collateralType) public {
    taxCollector.initializeCollateralType(_collateralType);

    (, uint256 _updateTime) = taxCollector.collateralTypes(_collateralType);

    assertEq(_updateTime, block.timestamp);
  }

  function test_Set_CollateralList(bytes32 _collateralType) public {
    taxCollector.initializeCollateralType(_collateralType);

    assertEq(taxCollector.collateralList(0), _collateralType);
  }

  function test_Emit_InitializeCollateralType(bytes32 _collateralType) public {
    expectEmitNoIndex();
    emit InitializeCollateralType(_collateralType);

    taxCollector.initializeCollateralType(_collateralType);
  }
}

contract Unit_TaxCollector_CollectedManyTax is Base {
  using stdStorage for StdStorage;

  function setUp() public override {
    Base.setUp();

    Base.setUpTaxManyOutcome();
  }

  function test_Revert_InvalidIndexes_0(uint256 _start, uint256 _end) public {
    vm.assume(_start > _end);

    vm.expectRevert('TaxCollector/invalid-indexes');

    taxCollector.collectedManyTax(_start, _end);
  }

  function test_Revert_InvalidIndexes_1(uint256 _start, uint256 _end) public {
    vm.assume(_start <= _end);
    vm.assume(_end >= taxCollector.collateralListLength());

    vm.expectRevert('TaxCollector/invalid-indexes');

    taxCollector.collectedManyTax(_start, _end);
  }

  function test_Return_Ok_False() public {
    bool _ok = taxCollector.collectedManyTax(1, 3);

    assertEq(_ok, false);
  }

  function test_Return_Ok_True(uint256 _updateTime) public {
    vm.assume(_updateTime >= block.timestamp);

    _mockCollateralType(collateralTypeA, stabilityFee, _updateTime);
    _mockCollateralType(collateralTypeB, stabilityFee, _updateTime);
    _mockCollateralType(collateralTypeC, stabilityFee, _updateTime);

    bool _ok = taxCollector.collectedManyTax(1, 3);

    assertEq(_ok, true);
  }
}

contract Unit_TaxCollector_TaxManyOutcome is Base {
  using Math for uint256;
  using stdStorage for StdStorage;

  function setUp() public override {
    Base.setUp();

    Base.setUpTaxManyOutcome();
  }

  function test_Revert_InvalidIndexes_0(uint256 _start, uint256 _end) public {
    vm.assume(_start > _end);

    vm.expectRevert('TaxCollector/invalid-indexes');

    taxCollector.taxManyOutcome(_start, _end);
  }

  function test_Revert_InvalidIndexes_1(uint256 _start, uint256 _end) public {
    vm.assume(_start <= _end);
    vm.assume(_end >= taxCollector.collateralListLength());

    vm.expectRevert('TaxCollector/invalid-indexes');

    taxCollector.taxManyOutcome(_start, _end);
  }

  function test_Return_Ok_False() public {
    (bool _ok,) = taxCollector.taxManyOutcome(1, 3);

    assertEq(_ok, false);
  }

  function test_Return_Ok_True_0(uint256 _coinBalance) public {
    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);
    int256 _rad = debtAmount.mul(_deltaRate) * 3;

    vm.assume(notOverflowWhenInt256(_coinBalance) && -int256(_coinBalance) <= _rad);

    _mockCoinBalance(primaryTaxReceiver, _coinBalance);

    (bool _ok,) = taxCollector.taxManyOutcome(1, 3);

    assertEq(_ok, true);
  }

  function test_Return_Ok_True_1(uint256 _lastAccumulatedRate) public {
    (uint256 _newlyAccumulatedRate,) = taxCollector.taxSingleOutcome(collateralTypeA);

    vm.assume(_lastAccumulatedRate <= _newlyAccumulatedRate);

    _mockCollateralType(collateralTypeA, debtAmount, _lastAccumulatedRate, 0, 0, 0, 0);
    _mockCollateralType(collateralTypeB, debtAmount, _lastAccumulatedRate, 0, 0, 0, 0);
    _mockCollateralType(collateralTypeC, debtAmount, _lastAccumulatedRate, 0, 0, 0, 0);

    (bool _ok,) = taxCollector.taxManyOutcome(1, 3);

    assertEq(_ok, true);
  }

  function test_Return_Rad(uint256 _updateTime) public {
    vm.assume(_updateTime >= block.timestamp);

    _mockCollateralType(collateralTypeB, stabilityFee, _updateTime);

    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);
    int256 _expectedRad = debtAmount.mul(_deltaRate) * 2;

    (, int256 _rad) = taxCollector.taxManyOutcome(1, 3);

    assertEq(_rad, _expectedRad);
  }
}

contract Unit_TaxCollector_TaxSingleOutcome is Base {
  using Math for uint256;

  function setUp() public override {
    Base.setUp();

    Base.setUpTaxSingleOutcome(collateralTypeA);
  }

  function test_Return_NewlyAccumulatedRate() public {
    uint256 _expectedNewlyAccumulatedRate =
      (globalStabilityFee + stabilityFee).rpow(block.timestamp - updateTime).rmul(lastAccumulatedRate);

    (uint256 _newlyAccumulatedRate,) = taxCollector.taxSingleOutcome(collateralTypeA);

    assertEq(_newlyAccumulatedRate, _expectedNewlyAccumulatedRate);
  }

  function test_Return_DeltaRate() public {
    uint256 _newlyAccumulatedRate =
      (globalStabilityFee + stabilityFee).rpow(block.timestamp - updateTime).rmul(lastAccumulatedRate);
    int256 _expectedDeltaRate = _newlyAccumulatedRate.sub(lastAccumulatedRate);

    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);

    assertEq(_deltaRate, _expectedDeltaRate);
  }
}

contract Unit_TaxCollector_TaxMany is Base {
  event CollectTax(bytes32 indexed _collateralType, uint256 _latestAccumulatedRate, int256 _deltaRate);

  function setUp() public override {
    Base.setUp();

    Base.setUpTaxMany();
  }

  function test_Revert_InvalidIndexes_0(uint256 _start, uint256 _end) public {
    vm.assume(_start > _end);

    vm.expectRevert('TaxCollector/invalid-indexes');

    taxCollector.taxMany(_start, _end);
  }

  function test_Revert_InvalidIndexes_1(uint256 _start, uint256 _end) public {
    vm.assume(_start <= _end);
    vm.assume(_end >= taxCollector.collateralListLength());

    vm.expectRevert('TaxCollector/invalid-indexes');

    taxCollector.taxMany(_start, _end);
  }

  function test_Emit_CollectTax() public {
    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);

    vm.expectEmit(true, false, false, true);
    emit CollectTax(collateralTypeA, lastAccumulatedRate, _deltaRate);
    vm.expectEmit(true, false, false, true);
    emit CollectTax(collateralTypeB, lastAccumulatedRate, _deltaRate);
    vm.expectEmit(true, false, false, true);
    emit CollectTax(collateralTypeC, lastAccumulatedRate, _deltaRate);

    taxCollector.taxMany(1, 3);
  }
}

contract Unit_TaxCollector_TaxSingle is Base {
  using stdStorage for StdStorage;

  event CollectTax(bytes32 indexed _collateralType, uint256 _latestAccumulatedRate, int256 _deltaRate);
  event DistributeTax(bytes32 indexed _collateralType, address indexed _target, int256 _taxCut);

  function setUp() public override {
    Base.setUp();

    Base.setUpTaxSingle(collateralTypeA);
  }

  function test_Return_AlreadyLatestAccumulatedRate(uint256 _updateTime) public {
    vm.assume(block.timestamp <= _updateTime);

    _mockCollateralType(collateralTypeA, stabilityFee, _updateTime);

    assertEq(taxCollector.taxSingle(collateralTypeA), lastAccumulatedRate);
  }

  function testFail_AlreadyLatestAccumulatedRate() public {
    _mockCollateralType(collateralTypeA, stabilityFee, block.timestamp);

    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);

    vm.expectEmit(true, false, false, true);
    emit CollectTax(collateralTypeA, lastAccumulatedRate, _deltaRate);

    taxCollector.taxSingle(collateralTypeA);
  }

  function test_Emit_DistributeTax() public {
    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);
    int256 _currentTaxCut = _assumeCurrentTaxCut(debtAmount, _deltaRate, false, false);

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, secondaryReceiverAccountA, _currentTaxCut);
    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, secondaryReceiverAccountC, _currentTaxCut);
    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, primaryTaxReceiver, _currentTaxCut);

    taxCollector.taxSingle(collateralTypeA);
  }

  function test_Set_CollateralTypeUpdateTime() public {
    taxCollector.taxSingle(collateralTypeA);

    (, uint256 _updateTime) = taxCollector.collateralTypes(collateralTypeA);

    assertEq(_updateTime, block.timestamp);
  }

  function test_Emit_CollectTax() public {
    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);

    vm.expectEmit(true, false, false, true);
    emit CollectTax(collateralTypeA, lastAccumulatedRate, _deltaRate);

    taxCollector.taxSingle(collateralTypeA);
  }

  function test_Return_LatestAccumulatedRate() public {
    assertEq(taxCollector.taxSingle(collateralTypeA), lastAccumulatedRate);
  }
}

contract Unit_TaxCollector_SplitTaxIncome is Base {
  event DistributeTax(bytes32 indexed _collateralType, address indexed _target, int256 _taxCut);

  function setUp() public override {
    Base.setUp();

    Base.setUpSplitTaxIncome(collateralTypeA);
  }

  function test_Emit_DistributeTax(uint256 _debtAmount, int256 _deltaRate) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, false, false);

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, secondaryReceiverAccountA, _currentTaxCut);
    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, secondaryReceiverAccountC, _currentTaxCut);
    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, primaryTaxReceiver, _currentTaxCut);

    taxCollector.splitTaxIncome(collateralTypeA, _debtAmount, _deltaRate);
  }

  function testFail_FullTaxReceiverList(uint256 _debtAmount, int256 _deltaRate) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, false, false);

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, secondaryReceiverAccountD, _currentTaxCut);

    taxCollector.splitTaxIncome(collateralTypeA, _debtAmount, _deltaRate);
  }

  function testFail_ShouldNotDistributeTax(uint256 _debtAmount, int256 _deltaRate) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, false, false);

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, secondaryReceiverAccountB, _currentTaxCut);

    taxCollector.splitTaxIncome(collateralTypeA, _debtAmount, _deltaRate);
  }
}

contract Unit_TaxCollector_DistributeTax is Base {
  using stdStorage for StdStorage;

  event DistributeTax(bytes32 indexed _collateralType, address indexed _target, int256 _taxCut);

  function setUp() public override {
    Base.setUp();

    Base.setUpDistributeTax(collateralTypeA);
  }

  function test_Revert_CoinBalanceDoesNotFitIntoInt256(
    bytes32 _collateralType,
    address _receiver,
    uint256 _receiverListPosition,
    uint256 _debtAmount,
    int256 _deltaRate,
    uint256 _coinBalance
  ) public {
    vm.assume(!notOverflowWhenInt256(_coinBalance));

    _mockCoinBalance(_receiver, _coinBalance);

    vm.expectRevert('TaxCollector/coin-balance-does-not-fit-into-int256');

    taxCollector.distributeTax(_collateralType, _receiver, _receiverListPosition, _debtAmount, _deltaRate);
  }

  function test_Call_SafeEngine_UpdateAccumulatedRate(
    uint256 _debtAmount,
    int256 _deltaRate,
    bool _isPrimaryTaxReceiver,
    bool _isAbsorbable
  ) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, _isPrimaryTaxReceiver, _isAbsorbable);

    vm.expectCall(
      address(safeEngine), abi.encodeCall(safeEngine.updateAccumulatedRate, (collateralTypeA, receiver, _currentTaxCut))
    );

    taxCollector.distributeTax(collateralTypeA, receiver, receiverListPosition, _debtAmount, _deltaRate);
  }

  function test_Emit_DistributeTax(
    uint256 _debtAmount,
    int256 _deltaRate,
    bool _isPrimaryTaxReceiver,
    bool _isAbsorbable
  ) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, _isPrimaryTaxReceiver, _isAbsorbable);

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, receiver, _currentTaxCut);

    taxCollector.distributeTax(collateralTypeA, receiver, receiverListPosition, _debtAmount, _deltaRate);
  }

  function testFail_ZeroTaxCut(uint256 _debtAmount) public {
    int256 _deltaRate = 0;
    int256 _currentTaxCut = 0;

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, receiver, _currentTaxCut);

    taxCollector.distributeTax(collateralTypeA, receiver, receiverListPosition, _debtAmount, _deltaRate);
  }

  function testFail_CanNotTakeBackTax(uint256 _debtAmount, int256 _deltaRate) public {
    _mockSecondaryTaxReceiver(collateralTypeA, receiverListPosition, 0, taxPercentage);

    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, false, false);

    vm.expectEmit(true, true, false, true);
    emit DistributeTax(collateralTypeA, receiver, _currentTaxCut);

    taxCollector.distributeTax(collateralTypeA, receiver, receiverListPosition, _debtAmount, _deltaRate);
  }
}