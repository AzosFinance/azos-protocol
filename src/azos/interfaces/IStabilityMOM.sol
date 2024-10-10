// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/// @title IStabilityMOM Interface
/// @notice Interface for the Stability Module Operations Manager (MOM)
/// @dev This interface defines the events, errors, and functions for the StabilityMOM contract
interface IStabilityMOM {
    /// @notice Emitted when an action is executed
    /// @param success Whether the action was successful
    /// @param result The result of the action
    /// @param actionContract The address of the contract that executed the action
    event Action(bool success, bytes result, address indexed actionContract);

    /// @notice Emitted when the allowed status of an asset is updated
    /// @param asset The address of the asset
    /// @param isAllowed The new allowed status of the asset
    event AllowedAssetsUpdated(address indexed asset, bool isAllowed);

    /// @notice Error thrown when trying to call a contract with no code
    error NoCode();

    /// @notice Error thrown when an action fails to execute
    error ActionFailed();

    /// @notice Error thrown when trying to execute an unregistered action
    error ActionNotRegistered();

    /// @notice Error thrown when input arrays have different lengths
    error ArraysMustHaveSameLength();

    /// @notice Delegates multiple actions to be executed
    /// @param actionIds An array of action IDs to be executed
    /// @param datas An array of encoded function data for each action
    /// @return An array of booleans indicating the success status of each action
    function delegateAction(uint256[] calldata actionIds, bytes[] calldata datas) external returns (bool[] memory);

    /// @notice Updates the allowed status of multiple assets
    /// @param assets An array of asset addresses to update
    /// @param statuses An array of boolean values indicating the new allowed status for each asset
    function updateAllowedAssets(address[] calldata assets, bool[] calldata statuses) external;

    /// @notice Checks if an asset is allowed
    /// @param allowedAsset The address of the asset to check
    /// @return isAllowed Boolean indicating whether the asset is allowed
    function allowedAssets(address allowedAsset) external view returns (bool isAllowed);
}
