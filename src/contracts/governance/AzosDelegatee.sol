// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {Ownable} from '@openzeppelin/contracts/access/Ownable2Step.sol';
import {IGovernor} from '@openzeppelin/contracts/governance/IGovernor.sol';
import {IAzosDelegatee} from '@interfaces/governance/IAzosDelegatee.sol';

/**
 * @title  AzosDelegatee
 * @notice This contract is used to proxy the voting power delegated to it to a delegatee
 * @dev    Compatible with OpenZeppelin's Governor contract
 */
contract AzosDelegatee is IAzosDelegatee, Ownable {
  /// @inheritdoc IAzosDelegatee
  address public delegatee;

  constructor(address _owner) Ownable(_owner) {}

  /// @inheritdoc IAzosDelegatee
  function setDelegatee(address _delegatee) external onlyOwner {
    delegatee = _delegatee;
    emit DelegateeSet(_delegatee);
  }

  /// @inheritdoc IAzosDelegatee
  function castVote(
    IGovernor _governor,
    uint256 _proposalId,
    uint8 _support
  ) public onlyDelegatee returns (uint256 _weight) {
    return _governor.castVote(_proposalId, _support);
  }

  /// @inheritdoc IAzosDelegatee
  function castVoteWithReason(
    IGovernor _governor,
    uint256 _proposalId,
    uint8 _support,
    string memory _reason
  ) public onlyDelegatee returns (uint256 _weight) {
    return _governor.castVoteWithReason(_proposalId, _support, _reason);
  }

  /// @inheritdoc IAzosDelegatee
  function castVoteWithReasonAndParams(
    IGovernor _governor,
    uint256 _proposalId,
    uint8 _support,
    string memory _reason,
    bytes memory _params
  ) public onlyDelegatee returns (uint256 _weight) {
    return _governor.castVoteWithReasonAndParams(_proposalId, _support, _reason, _params);
  }

  modifier onlyDelegatee() {
    if (msg.sender != delegatee) revert OnlyDelegatee();
    _;
  }
}
