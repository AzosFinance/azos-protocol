// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IAzosProxy} from '@interfaces/proxies/IAzosProxy.sol';

import {AzosOwnable2Step, IAzosOwnable2Step} from '@contracts/utils/AzosOwnable2Step.sol';

import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';

/**
 * @title  AzosProxy
 * @notice This contract is an ownable proxy to execute batched transactions in the protocol contracts
 * @dev    The proxy executes a delegate call to an Actions contract, which have the logic to execute the batched transactions
 */
contract AzosProxy is AzosOwnable2Step, IAzosProxy {
  using Address for address;

  // --- Init ---

  /**
   * @param  _owner The owner of the proxy contract
   */
  constructor(address _owner) Ownable(_owner) {}

  // --- Methods ---

  /// @inheritdoc IAzosProxy
  function execute(address _target, bytes memory _data) external payable onlyOwner returns (bytes memory _response) {
    if (_target == address(0)) revert TargetAddressRequired();
    _response = _target.functionDelegateCall(_data);
  }

  // --- Overrides ---

  /// @inheritdoc IAzosOwnable2Step
  function owner() public view override(AzosOwnable2Step, IAzosOwnable2Step) returns (address _owner) {
    return super.owner();
  }

  /// @inheritdoc IAzosOwnable2Step
  function pendingOwner() public view override(AzosOwnable2Step, IAzosOwnable2Step) returns (address _pendingOwner) {
    return super.pendingOwner();
  }

  /// @inheritdoc IAzosOwnable2Step
  function renounceOwnership() public override(AzosOwnable2Step, IAzosOwnable2Step) onlyOwner {
    super.renounceOwnership();
  }

  /// @inheritdoc IAzosOwnable2Step
  function transferOwnership(address _newOwner) public override(AzosOwnable2Step, IAzosOwnable2Step) onlyOwner {
    super.transferOwnership(_newOwner);
  }

  /// @inheritdoc IAzosOwnable2Step
  function acceptOwnership() public override(AzosOwnable2Step, IAzosOwnable2Step) {
    super.acceptOwnership();
  }
}
