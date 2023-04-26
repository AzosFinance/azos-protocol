// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {TaxCollectorForTest, ITaxCollector} from '@contracts/for-test/TaxCollectorForTest.sol';
import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {IAuthorizable} from '@interfaces/utils/IAuthorizable.sol';
import {Math, RAY} from '@libraries/Math.sol';
import {HaiTest, stdStorage, StdStorage} from '@test/utils/HaiTest.t.sol';

abstract contract Base is HaiTest {
  using Math for uint256;
  using stdStorage for StdStorage;

  address deployer = label('deployer');
  address authorizedAccount = label('authorizedAccount');
  address user = label('user');

  ISAFEEngine mockSafeEngine = ISAFEEngine(mockContract('SafeEngine'));

  TaxCollectorForTest taxCollector;

  uint256 constant WHOLE_TAX_CUT = 100e27; // RAY

  // SafeEngine storage
  uint256 coinBalance = RAY;
  uint256 debtAmount = 1e25;
  uint256 lastAccumulatedRate = 1e20;

  // TaxCollector storage
  bytes32 collateralTypeA = 'collateralTypeA';
  bytes32 collateralTypeB = 'collateralTypeB';
  bytes32 collateralTypeC = 'collateralTypeC';
  uint256 stabilityFee = 1e10;
  uint256 updateTime = block.timestamp - 100;
  uint256 secondaryReceiverAllotedTax = WHOLE_TAX_CUT / 2;
  address secondaryReceiverA = newAddress();
  address secondaryReceiverB = newAddress();
  address secondaryReceiverC = newAddress();
  uint128 taxPercentage = uint128(WHOLE_TAX_CUT / 4);
  bool canTakeBackTax = true;
  address primaryTaxReceiver = newAddress();
  uint256 globalStabilityFee = 1e15;

  // Input parameters
  address receiver;

  function setUp() public virtual {
    vm.startPrank(deployer);

    taxCollector = new TaxCollectorForTest(address(mockSafeEngine));
    label(address(taxCollector), 'TaxCollector');

    taxCollector.addAuthorization(authorizedAccount);

    vm.stopPrank();
  }

  function setUpTaxManyOutcome() public {
    setUpTaxSingleOutcome(collateralTypeA);
    setUpTaxSingleOutcome(collateralTypeB);
    setUpTaxSingleOutcome(collateralTypeC);

    // SafeEngine storage
    _mockCoinBalance(primaryTaxReceiver, coinBalance);

    // TaxCollector storage
    _mockPrimaryTaxReceiver(primaryTaxReceiver);
    _mockCollateralList(collateralTypeA);
    _mockCollateralList(collateralTypeB);
    _mockCollateralList(collateralTypeC);
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
    setUpDistributeTax(_collateralType);

    // SafeEngine storage
    _mockCoinBalance(secondaryReceiverB, coinBalance);
    _mockCoinBalance(secondaryReceiverC, coinBalance);

    // TaxCollector storage
    _mockSecondaryReceiver(secondaryReceiverA);
    _mockSecondaryReceiver(secondaryReceiverB);
    _mockSecondaryReceiver(secondaryReceiverC);
    _mockSecondaryTaxReceiver(_collateralType, secondaryReceiverB, canTakeBackTax, 0);
    _mockSecondaryTaxReceiver(_collateralType, secondaryReceiverC, canTakeBackTax, taxPercentage);
  }

  function setUpDistributeTax(bytes32 _collateralType) public {
    // SafeEngine storage
    _mockCoinBalance(primaryTaxReceiver, coinBalance);
    _mockCoinBalance(secondaryReceiverA, coinBalance);

    // TaxCollector storage
    _mockSecondaryReceiverAllotedTax(_collateralType, secondaryReceiverAllotedTax);
    _mockSecondaryTaxReceiver(_collateralType, secondaryReceiverA, canTakeBackTax, taxPercentage);
    _mockPrimaryTaxReceiver(primaryTaxReceiver);
  }

  modifier authorized() {
    vm.startPrank(authorizedAccount);
    _;
  }

  function _mockCoinBalance(address _receiver, uint256 _coinBalance) internal {
    vm.mockCall(
      address(mockSafeEngine), abi.encodeCall(mockSafeEngine.coinBalance, (_receiver)), abi.encode(_coinBalance)
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
      address(mockSafeEngine),
      abi.encodeCall(mockSafeEngine.collateralTypes, (_collateralType)),
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

  function _mockSecondaryTaxReceiver(
    bytes32 _collateralType,
    address _receiver,
    bool _canTakeBackTax,
    uint128 _taxPercentage
  ) internal {
    // BUG: Accessing packed slots is not supported by Std Storage
    taxCollector.addSecondaryTaxReceiver(_collateralType, _receiver, _canTakeBackTax, _taxPercentage);
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

  function _mockCollateralList(bytes32 _collateralType) internal {
    taxCollector.addToCollateralList(_collateralType);
  }

  function _mockSecondaryReceiver(address _receiver) internal {
    taxCollector.addSecondaryReceiver(_receiver);
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
      receiver = secondaryReceiverA;
      if (!_isAbsorbable) {
        vm.assume(_deltaRate <= -int256(WHOLE_TAX_CUT / taxPercentage) && _deltaRate >= -int256(WHOLE_TAX_CUT));
        _currentTaxCut = int256(uint256(taxPercentage)) * _deltaRate / int256(WHOLE_TAX_CUT);
        vm.assume(_debtAmount <= coinBalance);
        vm.assume(-int256(coinBalance) > _debtAmount.mul(_currentTaxCut));
        _currentTaxCut = -int256(coinBalance) / int256(_debtAmount);
      } else {
        vm.assume(
          _deltaRate <= -int256(WHOLE_TAX_CUT / taxPercentage) && _deltaRate >= -int256(WHOLE_TAX_CUT)
            || _deltaRate >= int256(WHOLE_TAX_CUT / taxPercentage) && _deltaRate <= int256(WHOLE_TAX_CUT)
        );
        _currentTaxCut = int256(uint256(taxPercentage)) * _deltaRate / int256(WHOLE_TAX_CUT);
        vm.assume(_debtAmount <= WHOLE_TAX_CUT && -int256(coinBalance) <= _debtAmount.mul(_currentTaxCut));
      }
    }
  }
}

contract Unit_TaxCollector_Constructor is Base {
  event AddAuthorization(address _account);

  function setUp() public override {
    Base.setUp();

    vm.startPrank(user);
  }

  function test_Emit_AddAuthorization() public {
    expectEmitNoIndex();
    emit AddAuthorization(user);

    taxCollector = new TaxCollectorForTest(address(mockSafeEngine));
  }

  function test_Set_SafeEngine(address _safeEngine) public {
    taxCollector = new TaxCollectorForTest(_safeEngine);

    assertEq(address(taxCollector.safeEngine()), _safeEngine);
  }
}

contract Unit_TaxCollector_InitializeCollateralType is Base {
  event InitializeCollateralType(bytes32 _collateralType);

  function test_Revert_Unauthorized(bytes32 _collateralType) public {
    vm.expectRevert(IAuthorizable.Unauthorized.selector);

    taxCollector.initializeCollateralType(_collateralType);
  }

  function test_Revert_CollateralTypeAlreadyInit(bytes32 _collateralType) public authorized {
    _mockCollateralType(_collateralType, RAY, 0);

    vm.expectRevert('TaxCollector/collateral-type-already-init');

    taxCollector.initializeCollateralType(_collateralType);
  }

  function test_Set_CollateralTypeStabilityFee(bytes32 _collateralType) public authorized {
    taxCollector.initializeCollateralType(_collateralType);

    (uint256 _stabilityFee,) = taxCollector.collateralTypes(_collateralType);

    assertEq(_stabilityFee, RAY);
  }

  function test_Set_CollateralTypeUpdateTime(bytes32 _collateralType) public authorized {
    taxCollector.initializeCollateralType(_collateralType);

    (, uint256 _updateTime) = taxCollector.collateralTypes(_collateralType);

    assertEq(_updateTime, block.timestamp);
  }

  function test_Set_CollateralList(bytes32 _collateralType) public authorized {
    taxCollector.initializeCollateralType(_collateralType);

    assertEq(taxCollector.collateralListList()[0], _collateralType);
  }

  function test_Emit_InitializeCollateralType(bytes32 _collateralType) public authorized {
    expectEmitNoIndex();
    emit InitializeCollateralType(_collateralType);

    taxCollector.initializeCollateralType(_collateralType);
  }
}

contract Unit_TaxCollector_CollectedManyTax is Base {
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
    bool _ok = taxCollector.collectedManyTax(0, 2);

    assertEq(_ok, false);
  }

  function test_Return_Ok_True(uint256 _updateTime) public {
    vm.assume(_updateTime >= block.timestamp);

    _mockCollateralType(collateralTypeA, stabilityFee, _updateTime);
    _mockCollateralType(collateralTypeB, stabilityFee, _updateTime);
    _mockCollateralType(collateralTypeC, stabilityFee, _updateTime);

    bool _ok = taxCollector.collectedManyTax(0, 2);

    assertEq(_ok, true);
  }
}

contract Unit_TaxCollector_TaxManyOutcome is Base {
  using Math for uint256;

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
    (bool _ok,) = taxCollector.taxManyOutcome(0, 2);

    assertEq(_ok, false);
  }

  function test_Return_Ok_True_0(uint256 _coinBalance) public {
    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);
    int256 _rad = debtAmount.mul(_deltaRate) * 3;

    vm.assume(notOverflowWhenInt256(_coinBalance) && -int256(_coinBalance) <= _rad);

    _mockCoinBalance(primaryTaxReceiver, _coinBalance);

    (bool _ok,) = taxCollector.taxManyOutcome(0, 2);

    assertEq(_ok, true);
  }

  function test_Return_Ok_True_1(uint256 _lastAccumulatedRate) public {
    (uint256 _newlyAccumulatedRate,) = taxCollector.taxSingleOutcome(collateralTypeA);

    vm.assume(_lastAccumulatedRate <= _newlyAccumulatedRate);

    _mockCollateralType(collateralTypeA, debtAmount, _lastAccumulatedRate, 0, 0, 0, 0);
    _mockCollateralType(collateralTypeB, debtAmount, _lastAccumulatedRate, 0, 0, 0, 0);
    _mockCollateralType(collateralTypeC, debtAmount, _lastAccumulatedRate, 0, 0, 0, 0);

    (bool _ok,) = taxCollector.taxManyOutcome(0, 2);

    assertEq(_ok, true);
  }

  function test_Return_Rad(uint256 _updateTime) public {
    vm.assume(_updateTime >= block.timestamp);

    _mockCollateralType(collateralTypeB, stabilityFee, _updateTime);

    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);
    int256 _expectedRad = debtAmount.mul(_deltaRate) * 2;

    (, int256 _rad) = taxCollector.taxManyOutcome(0, 2);

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

    expectEmitNoIndex();
    emit CollectTax(collateralTypeA, lastAccumulatedRate, _deltaRate);
    expectEmitNoIndex();
    emit CollectTax(collateralTypeB, lastAccumulatedRate, _deltaRate);
    expectEmitNoIndex();
    emit CollectTax(collateralTypeC, lastAccumulatedRate, _deltaRate);

    taxCollector.taxMany(0, 2);
  }
}

contract Unit_TaxCollector_TaxSingle is Base {
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

    expectEmitNoIndex();
    emit CollectTax(collateralTypeA, lastAccumulatedRate, _deltaRate);

    taxCollector.taxSingle(collateralTypeA);
  }

  function test_Emit_DistributeTax() public {
    (, int256 _deltaRate) = taxCollector.taxSingleOutcome(collateralTypeA);
    int256 _currentTaxCut = _assumeCurrentTaxCut(debtAmount, _deltaRate, false, false);

    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, secondaryReceiverA, _currentTaxCut);
    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, secondaryReceiverC, _currentTaxCut);
    expectEmitNoIndex();
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

    expectEmitNoIndex();
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

    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, secondaryReceiverA, _currentTaxCut);
    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, secondaryReceiverC, _currentTaxCut);
    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, primaryTaxReceiver, _currentTaxCut);

    taxCollector.splitTaxIncome(collateralTypeA, _debtAmount, _deltaRate);
  }

  function testFail_ShouldNotDistributeTax(uint256 _debtAmount, int256 _deltaRate) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, false, false);

    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, secondaryReceiverB, _currentTaxCut);

    taxCollector.splitTaxIncome(collateralTypeA, _debtAmount, _deltaRate);
  }
}

contract Unit_TaxCollector_DistributeTax is Base {
  event DistributeTax(bytes32 indexed _collateralType, address indexed _target, int256 _taxCut);

  function setUp() public override {
    Base.setUp();

    Base.setUpDistributeTax(collateralTypeA);
  }

  function test_Revert_CoinBalanceDoesNotFitIntoInt256(
    bytes32 _collateralType,
    address _receiver,
    uint256 _debtAmount,
    int256 _deltaRate,
    uint256 _coinBalance
  ) public {
    vm.assume(!notOverflowWhenInt256(_coinBalance));

    _mockCoinBalance(_receiver, _coinBalance);

    vm.expectRevert('TaxCollector/coin-balance-does-not-fit-into-int256');

    taxCollector.distributeTax(_collateralType, _receiver, _debtAmount, _deltaRate);
  }

  function test_Call_SafeEngine_UpdateAccumulatedRate(
    uint256 _debtAmount,
    int256 _deltaRate,
    bool _isPrimaryTaxReceiver,
    bool _isAbsorbable
  ) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, _isPrimaryTaxReceiver, _isAbsorbable);

    vm.expectCall(
      address(mockSafeEngine),
      abi.encodeCall(mockSafeEngine.updateAccumulatedRate, (collateralTypeA, receiver, _currentTaxCut))
    );

    taxCollector.distributeTax(collateralTypeA, receiver, _debtAmount, _deltaRate);
  }

  function test_Emit_DistributeTax(
    uint256 _debtAmount,
    int256 _deltaRate,
    bool _isPrimaryTaxReceiver,
    bool _isAbsorbable
  ) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, _isPrimaryTaxReceiver, _isAbsorbable);

    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, receiver, _currentTaxCut);

    taxCollector.distributeTax(collateralTypeA, receiver, _debtAmount, _deltaRate);
  }

  function testFail_ZeroTaxCut(uint256 _debtAmount) public {
    int256 _deltaRate = 0;
    int256 _currentTaxCut = 0;

    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, receiver, _currentTaxCut);

    taxCollector.distributeTax(collateralTypeA, receiver, _debtAmount, _deltaRate);
  }

  function testFail_CanNotTakeBackTax(uint256 _debtAmount, int256 _deltaRate) public {
    int256 _currentTaxCut = _assumeCurrentTaxCut(_debtAmount, _deltaRate, false, false);

    _mockSecondaryTaxReceiver(collateralTypeA, receiver, !canTakeBackTax, taxPercentage);

    expectEmitNoIndex();
    emit DistributeTax(collateralTypeA, receiver, _currentTaxCut);

    taxCollector.distributeTax(collateralTypeA, receiver, _debtAmount, _deltaRate);
  }
}
