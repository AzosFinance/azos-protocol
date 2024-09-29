// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {IAzosOwnable2Step} from '@interfaces/utils/IAzosOwnable2Step.sol';

import {Ownable2Step, Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';

/**
 * @title  AzosOwnable2Step
 * @notice This abstract contract inherits Ownable2Step
 */
abstract contract AzosOwnable2Step is Ownable2Step, IAzosOwnable2Step {
  // --- Overrides ---

  /// @inheritdoc IAzosOwnable2Step
  function owner() public view virtual override(Ownable, IAzosOwnable2Step) returns (address _owner) {
    return super.owner();
  }

  /// @inheritdoc IAzosOwnable2Step
  function pendingOwner() public view virtual override(Ownable2Step, IAzosOwnable2Step) returns (address _pendingOwner) {
    return super.pendingOwner();
  }

  /// @inheritdoc IAzosOwnable2Step
  function renounceOwnership() public virtual override(Ownable, IAzosOwnable2Step) onlyOwner {
    super.renounceOwnership();
  }

  /// @inheritdoc IAzosOwnable2Step
  function transferOwnership(address _newOwner) public virtual override(Ownable2Step, IAzosOwnable2Step) onlyOwner {
    super.transferOwnership(_newOwner);
  }

  /// @inheritdoc IAzosOwnable2Step
  function acceptOwnership() public virtual override(Ownable2Step, IAzosOwnable2Step) {
    super.acceptOwnership();
  }
}
