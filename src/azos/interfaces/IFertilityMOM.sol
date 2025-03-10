// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {IMOMRegistry} from '@azos/interfaces/IMOMRegistry.sol';

/**
 * @title IFertilityMOM Interface
 * @notice Interface for the FertilityMOM contract which handles deposits of stability tokens for AZUSD
 */
interface IFertilityMOM {
    // --- Events ---
    event Deposit(address indexed token, uint256 amount, uint256 AZUSDMinted, address indexed actor);
    event TreasuryWithdraw(address indexed token, uint256 amount, address indexed actor);
    event TreasuryUpdated(address indexed newTreasury, address indexed actor);
    event AllowedAssetsUpdated(address indexed asset, bool status, address indexed actor);
    event DepositCapUpdated(uint256 newCap, address indexed actor);
    event EmergencyWithdraw(address indexed token, uint256 amount, address indexed actor);

    // --- Errors ---
    error InvalidTreasury();
    error InvalidAmount();
    error AssetNotAllowed();
    error InsufficientBalance();
    error TransferFailed();
    error ArrayLengthMismatch();
    error DepositCapExceeded();
    error InvalidDecimals();
    error AssetPaused();

    // --- Actions ---
    function action(bytes calldata data) external returns (bool);

    // --- Treasury Operations ---
    function withdrawToTreasury(address token, uint256 amount) external;
    function updateTreasury(address newTreasury) external;
    function emergencyWithdraw(address token, uint256 amount) external;

    // --- Administration ---
    function updateAllowedAssets(address[] calldata assets, bool[] calldata statuses) external;
    function updateDepositCap(uint256 newCap) external;

    // --- Views ---
    function allowedAssets(address asset) external view returns (bool);
    function treasury() external view returns (address);
    function getDepositCap() external view returns (uint256);
    function getDeposited() external view returns (uint256);
} 