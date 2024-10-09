// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

interface IStabilityMOM {
    // Events
    event Action(bool success, bytes result, address indexed actionContract);
    event AllowedAssetsUpdated(address indexed asset, bool isAllowed);

    // Errors
    error NoCode();
    error ActionFailed();
    error ActionNotRegistered();
    error ArraysMustHaveSameLength();

    // Functions
    function delegateAction(uint256 actionId, bytes calldata data) external returns (bool);
}
