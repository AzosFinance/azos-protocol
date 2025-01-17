// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.20;

interface IDIAOracleV2 {
    function getValue(string memory key) external view returns (uint128, uint128);
    function values(string memory) external view returns (uint256);
    function oracleUpdater() external view returns (address);
} 