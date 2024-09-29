// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {AzosSafeManager, IAzosSafeManager, ISAFEEngine} from '@contracts/proxies/AzosSafeManager.sol';

import {AzosSafeManagerForTest} from '@test/mocks/AzosSafeManagerForTest.sol';
import {AzosTest} from '@test/utils/AzosTest.t.sol';

abstract contract Base is AzosTest {
  address deployer = label('deployer');
  ISAFEEngine safeEngine = ISAFEEngine(mockContract('safeEngine'));

  AzosSafeManager safeManager;

  function setUp() public virtual {
    vm.startPrank(deployer);

    safeManager = new AzosSafeManagerForTest(address(safeEngine));
    label(address(safeManager), 'AzosSafeManager');

    vm.stopPrank();
  }

  function _mockSAFE(uint256 _safe, IAzosSafeManager.SAFEData memory _safeData) internal {
    AzosSafeManagerForTest(address(safeManager)).setSAFE(_safe, _safeData);
  }
}

contract Unit_AzosSafeManager_TransferSAFEOwnership is Base {
  event InitiateTransferSAFEOwnership(address indexed _sender, uint256 indexed _safe, address _dst);

  modifier happyPath(uint256 _safe, IAzosSafeManager.SAFEData memory _safeData, address _recipient) {
    _assumeHappyPath(_safe, _safeData, _recipient);
    _mockValues(_safe, _safeData);
    _;
  }

  function _assumeHappyPath(uint256, IAzosSafeManager.SAFEData memory _safeData, address _recipient) internal pure {
    vm.assume(_safeData.pendingOwner != _recipient && _safeData.pendingOwner != _safeData.owner);
    vm.assume(_safeData.owner != _recipient);
  }

  function _mockValues(uint256 _safe, IAzosSafeManager.SAFEData memory _safeData) internal {
    _mockSAFE(_safe, _safeData);
  }

  function test_TransferOwnership(
    uint256 _safe,
    IAzosSafeManager.SAFEData memory _safeData,
    address _recipient
  ) external happyPath(_safe, _safeData, _recipient) {
    vm.expectEmit();
    emit InitiateTransferSAFEOwnership(_safeData.owner, _safe, _recipient);

    vm.startPrank(_safeData.owner);
    safeManager.transferSAFEOwnership(_safe, _recipient);

    assertEq(safeManager.safeData(_safe).pendingOwner, _recipient);
  }

  function test_Reset_TransferOwnership(
    uint256 _safe,
    IAzosSafeManager.SAFEData memory _safeData,
    address _recipient
  ) external happyPath(_safe, _safeData, _recipient) {
    vm.assume(_safeData.owner != address(0));
    vm.assume(_safeData.pendingOwner != address(0));

    vm.expectEmit();
    emit InitiateTransferSAFEOwnership(_safeData.owner, _safe, address(0));

    vm.startPrank(_safeData.owner);
    safeManager.transferSAFEOwnership(_safe, address(0));

    assertEq(safeManager.safeData(_safe).pendingOwner, address(0));
  }

  function test_Revert_NotOwner(
    uint256 _safe,
    IAzosSafeManager.SAFEData memory _safeData,
    address _recipient,
    address _sender
  ) external happyPath(_safe, _safeData, _recipient) {
    vm.assume(_sender != _safeData.owner && _sender != address(0));

    vm.expectRevert(IAzosSafeManager.SafeNotAllowed.selector);

    vm.startPrank(_sender);
    safeManager.transferSAFEOwnership(_safe, _recipient);
  }

  function test_Revert_AlreadySafeOwner(
    uint256 _safe,
    IAzosSafeManager.SAFEData memory _safeData,
    address _recipient
  ) external happyPath(_safe, _safeData, _recipient) {
    vm.expectRevert(IAzosSafeManager.AlreadySafeOwner.selector);

    vm.startPrank(_safeData.owner);
    safeManager.transferSAFEOwnership(_safe, _safeData.owner);
  }
}

contract Unit_AzosSafeManager_AcceptSAFEOwnership is Base {
  event TransferSAFEOwnership(address indexed _sender, uint256 indexed _safe, address _dst);

  function test_AcceptTransferOwnership(uint256 _safe, IAzosSafeManager.SAFEData memory _safeData) external {
    vm.assume(_safeData.owner != _safeData.pendingOwner);
    vm.assume(_safeData.pendingOwner != address(0));
    _mockSAFE(_safe, _safeData);

    vm.expectEmit();
    emit TransferSAFEOwnership(_safeData.owner, _safe, _safeData.pendingOwner);

    vm.startPrank(_safeData.pendingOwner);
    safeManager.acceptSAFEOwnership(_safe);

    assertEq(safeManager.safeData(_safe).pendingOwner, address(0));
    assertEq(safeManager.safeData(_safe).owner, _safeData.pendingOwner);

    // Check that the enumerables were updated
    assertEq(safeManager.getSafes(_safeData.owner).length, 0);
    assertEq(safeManager.getSafes(_safeData.pendingOwner).length, 1);

    // Check that the colletaral enumerables were updated
    assertEq(safeManager.getSafes(_safeData.owner, _safeData.collateralType).length, 0);
    assertEq(safeManager.getSafes(_safeData.pendingOwner, _safeData.collateralType).length, 1);
  }

  function test_Revert_NotPendingOwner(
    uint256 _safe,
    IAzosSafeManager.SAFEData memory _safeData,
    address _sender
  ) external {
    vm.assume(_safeData.pendingOwner != _sender);
    _mockSAFE(_safe, _safeData);

    vm.expectRevert(IAzosSafeManager.SafeNotAllowed.selector);

    vm.startPrank(_sender);
    safeManager.acceptSAFEOwnership(_safe);
  }
}
