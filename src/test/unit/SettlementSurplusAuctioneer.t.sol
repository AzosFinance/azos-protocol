// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {
  SettlementSurplusAuctioneer,
  ISettlementSurplusAuctioneer
} from '@contracts/settlement/SettlementSurplusAuctioneer.sol';
import {IAccountingEngine} from '@interfaces/IAccountingEngine.sol';
import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {ISurplusAuctionHouse} from '@interfaces/ISurplusAuctionHouse.sol';
import {IAuthorizable} from '@interfaces/utils/IAuthorizable.sol';
import {IModifiable} from '@interfaces/utils/IModifiable.sol';
import {HaiTest, stdStorage, StdStorage} from '@test/utils/HaiTest.t.sol';

abstract contract Base is HaiTest {
  using stdStorage for StdStorage;

  address deployer = label('deployer');
  address authorizedAccount = label('authorizedAccount');
  address user = label('user');

  IAccountingEngine mockAccountingEngine = IAccountingEngine(mockContract('AccountingEngine'));
  ISurplusAuctionHouse mockSurplusAuctionHouse = ISurplusAuctionHouse(mockContract('SurplusAuctionHouse'));
  ISAFEEngine mockSafeEngine = ISAFEEngine(mockContract('SafeEngine'));

  SettlementSurplusAuctioneer settlementSurplusAuctioneer;

  function setUp() public virtual {
    vm.startPrank(deployer);

    _mockSafeEngine(mockSafeEngine);

    settlementSurplusAuctioneer =
      new SettlementSurplusAuctioneer(address(mockAccountingEngine), address(mockSurplusAuctionHouse));
    label(address(settlementSurplusAuctioneer), 'SettlementSurplusAuctioneer');

    settlementSurplusAuctioneer.addAuthorization(authorizedAccount);

    vm.stopPrank();
  }

  modifier authorized() {
    vm.startPrank(authorizedAccount);
    _;
  }

  function _mockContractEnabled(uint256 _contractEnabled) internal {
    vm.mockCall(
      address(mockAccountingEngine),
      abi.encodeCall(mockAccountingEngine.contractEnabled, ()),
      abi.encode(_contractEnabled)
    );
  }

  function _mockSafeEngine(ISAFEEngine _safeEngine) internal {
    vm.mockCall(
      address(mockAccountingEngine), abi.encodeCall(mockAccountingEngine.safeEngine, ()), abi.encode(_safeEngine)
    );
  }

  function _mockAccountingEngineParams(uint256 _surplusDelay, uint256 _surplusAmount) internal {
    IAccountingEngine.AccountingEngineParams memory _params;
    _params.surplusDelay = _surplusDelay;
    _params.surplusAmount = _surplusAmount;

    vm.mockCall(address(mockAccountingEngine), abi.encodeCall(mockAccountingEngine.params, ()), abi.encode(_params));
  }

  function _mockStartAuction(uint256 _amountToSell, uint256 _initialBid, uint256 _id) internal {
    vm.mockCall(
      address(mockSurplusAuctionHouse),
      abi.encodeCall(mockSurplusAuctionHouse.startAuction, (_amountToSell, _initialBid)),
      abi.encode(_id)
    );
  }

  function _mockCoinBalance(address _coinAddress, uint256 _coinBalance) internal {
    vm.mockCall(
      address(mockSafeEngine), abi.encodeCall(mockSafeEngine.coinBalance, (_coinAddress)), abi.encode(_coinBalance)
    );
  }

  function _mockLastSurplusAuctionTime(uint256 _lastSurplusTime) internal {
    stdstore.target(address(settlementSurplusAuctioneer)).sig(ISettlementSurplusAuctioneer.lastSurplusTime.selector)
      .checked_write(_lastSurplusTime);
  }
}

contract Unit_SettlementSurplusAuctioneer_Constructor is Base {
  event AddAuthorization(address _account);

  function setUp() public override {
    Base.setUp();

    vm.startPrank(user);
  }

  function test_Emit_AddAuthorization() public {
    expectEmitNoIndex();
    emit AddAuthorization(user);

    settlementSurplusAuctioneer =
      new SettlementSurplusAuctioneer(address(mockAccountingEngine), address(mockSurplusAuctionHouse));
  }

  function test_Set_AccountingEngine() public {
    assertEq(address(settlementSurplusAuctioneer.accountingEngine()), address(mockAccountingEngine));
  }

  function test_Set_SurplusAuctionHouse() public {
    assertEq(address(settlementSurplusAuctioneer.surplusAuctionHouse()), address(mockSurplusAuctionHouse));
  }

  function test_Set_SafeEngine() public {
    assertEq(address(settlementSurplusAuctioneer.safeEngine()), address(mockSafeEngine));
  }

  function test_Call_SafeEngine_ApproveSAFEModification() public {
    vm.expectCall(
      address(mockSafeEngine),
      abi.encodeCall(mockSafeEngine.approveSAFEModification, (address(mockSurplusAuctionHouse)))
    );

    settlementSurplusAuctioneer =
      new SettlementSurplusAuctioneer(address(mockAccountingEngine), address(mockSurplusAuctionHouse));
  }
}

contract Unit_SettlementSurplusAuctioneer_ModifyParameters is Base {
  function test_ModifyParameters_AccountingEngine(address _accountingEngine) public authorized {
    settlementSurplusAuctioneer.modifyParameters('accountingEngine', abi.encode(_accountingEngine));

    assertEq(_accountingEngine, address(settlementSurplusAuctioneer.accountingEngine()));
  }

  function test_ModifyParameters_SurplusAuctionHouse(address _surplusAuctionHouse) public authorized {
    address _previousSurplusAuctionHouse = address(settlementSurplusAuctioneer.surplusAuctionHouse());

    vm.expectCall(
      address(mockSafeEngine), abi.encodeCall(mockSafeEngine.denySAFEModification, (_previousSurplusAuctionHouse))
    );
    vm.expectCall(
      address(mockSafeEngine), abi.encodeCall(mockSafeEngine.approveSAFEModification, (_surplusAuctionHouse))
    );

    settlementSurplusAuctioneer.modifyParameters('surplusAuctionHouse', abi.encode(_surplusAuctionHouse));

    assertEq(_surplusAuctionHouse, address(settlementSurplusAuctioneer.surplusAuctionHouse()));
  }

  function test_Revert_ModifyParameters_UnrecognizedParam() public authorized {
    vm.expectRevert(IModifiable.UnrecognizedParam.selector);

    settlementSurplusAuctioneer.modifyParameters('unrecognizedParam', abi.encode(0));
  }
}

contract Unit_SettlementSurplusAuctioneer_AuctionSurplus is Base {
  event AuctionSurplus(uint256 indexed _id, uint256 _lastSurplusTime, uint256 _coinBalance);

  modifier happyPath(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) {
    _assumeHappyPath(_lastSurplusTime, _surplusDelay);
    _mockContractEnabled(0);
    _mockLastSurplusAuctionTime(_lastSurplusTime);
    _mockAccountingEngineParams(_surplusDelay, _surplusAmount);
    _mockCoinBalance(address(settlementSurplusAuctioneer), _coinBalance);
    _mockStartAuction(_coinBalance, 0, _idA);
    _mockStartAuction(_surplusAmount, 0, _idB);
    _;
  }

  function _assumeHappyPath(uint256 _lastSurplusTime, uint256 _surplusDelay) internal {
    vm.assume(notOverflow(_lastSurplusTime, _surplusDelay));
    vm.assume(block.timestamp >= _lastSurplusTime + _surplusDelay);
  }

  function test_Revert_AccountingEngineStillEnabled(uint256 _contractEnabled) public {
    vm.assume(_contractEnabled != 0);

    _mockContractEnabled(_contractEnabled);

    vm.expectRevert('SettlementSurplusAuctioneer/accounting-engine-still-enabled');

    settlementSurplusAuctioneer.auctionSurplus();
  }

  function test_Revert_SurplusAuctionDelayNotPassed(uint256 _lastSurplusTime, uint256 _surplusDelay) public {
    vm.assume(notOverflow(_lastSurplusTime, _surplusDelay));
    vm.assume(block.timestamp < _lastSurplusTime + _surplusDelay);

    _mockContractEnabled(0);
    _mockLastSurplusAuctionTime(_lastSurplusTime);
    _mockAccountingEngineParams(_surplusDelay, 0);

    vm.expectRevert('SettlementSurplusAuctioneer/surplus-auction-delay-not-passed');

    settlementSurplusAuctioneer.auctionSurplus();
  }

  function test_Set_LastSurplusAuctionTime(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    settlementSurplusAuctioneer.auctionSurplus();

    assertEq(settlementSurplusAuctioneer.lastSurplusTime(), block.timestamp);
  }

  function test_Return_Id_A(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    vm.assume(_coinBalance < _surplusAmount);
    vm.assume(_coinBalance > 0);

    assertEq(settlementSurplusAuctioneer.auctionSurplus(), _idA);
  }

  function test_Return_Id_B(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    vm.assume(_coinBalance >= _surplusAmount);
    vm.assume(_surplusAmount > 0);

    assertEq(settlementSurplusAuctioneer.auctionSurplus(), _idB);
  }

  function test_Return_Id_C(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    vm.assume(
      _coinBalance < _surplusAmount && _coinBalance == 0 || _coinBalance >= _surplusAmount && _surplusAmount == 0
    );

    assertEq(settlementSurplusAuctioneer.auctionSurplus(), 0);
  }

  function test_Emit_AuctionSurplus_A(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    vm.assume(_coinBalance < _surplusAmount);
    vm.assume(_coinBalance > 0);

    expectEmitNoIndex();
    emit AuctionSurplus(_idA, block.timestamp, _coinBalance);

    settlementSurplusAuctioneer.auctionSurplus();
  }

  function test_Emit_AuctionSurplus_B(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    vm.assume(_coinBalance >= _surplusAmount);
    vm.assume(_surplusAmount > 0);

    expectEmitNoIndex();
    emit AuctionSurplus(_idB, block.timestamp, _coinBalance);

    settlementSurplusAuctioneer.auctionSurplus();
  }

  function testFail_Emit_AuctionSurplus(
    uint256 _lastSurplusTime,
    uint256 _surplusDelay,
    uint256 _surplusAmount,
    uint256 _coinBalance,
    uint256 _idA,
    uint256 _idB
  ) public happyPath(_lastSurplusTime, _surplusDelay, _surplusAmount, _coinBalance, _idA, _idB) {
    vm.assume(
      _coinBalance < _surplusAmount && _coinBalance == 0 || _coinBalance >= _surplusAmount && _surplusAmount == 0
    );

    expectEmitNoIndex();
    emit AuctionSurplus(0, block.timestamp, _coinBalance);

    settlementSurplusAuctioneer.auctionSurplus();
  }
}
