// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

interface IAzosGovernor {
  struct AzosGovernorParams {
    uint48 votingDelay;
    uint32 votingPeriod;
    uint48 quorumVoteExtension;
    uint256 proposalThreshold;
    uint256 quorumNumeratorValue;
    uint256 timelockMinDelay;
  }
}
