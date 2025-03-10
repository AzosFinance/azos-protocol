// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import {MOM, IMOMRegistry, IERC20Metadata} from '@azos/MOM.sol';
import {IFertilityMOM} from '@azos/interfaces/IFertilityMOM.sol';
import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';


/**
 * @title FertilityMOM
 * @notice A MOM contract that allows users to deposit stability tokens in exchange for AZUSD
 * @dev Inherits from MOM contract and implements deposit/burn functionality
 */
contract FertilityMOM is MOM, IFertilityMOM {
    // --- Storage ---
    mapping(address allowedAsset => bool isAllowed) public allowedAssets;
    uint256 internal _depositCap;
    uint256 internal _deposited;
    address public treasury; // Address that can collect deposited tokens
    mapping(address => bool) public paused;

    /**
     * @notice Constructs a new FertilityMOM contract
     * @param registry_ The MOMRegistry contract address
     * @param asset_ The initial allowed stability token
     * @param treasury_ The address that can collect deposited tokens
     * @param pauser_ The address that can pause the contract
     * @param depositCap_ The maximum amount of tokens that can be deposited
     */
    constructor(
        IMOMRegistry registry_,
        IERC20Metadata asset_,
        address treasury_,
        address pauser_,
        uint256 depositCap_
    ) MOM(registry_, asset_, pauser_) {
        if (treasury_ == address(0)) revert InvalidTreasury();
        if (address(asset_) == address(0)) revert InvalidAmount();
        if (depositCap_ == 0) revert InvalidAmount();

        _depositCap = depositCap_;
        treasury = treasury_;
        allowedAssets[address(asset_)] = true;
        emit AllowedAssetsUpdated(address(asset_), true, msg.sender);
        emit TreasuryUpdated(treasury_, msg.sender);
    }

    /**
     * @notice Processes a deposit or burn action
     * @param data Encoded parameters (address token, uint256 amount, bool isDeposit)
     * @return success Whether the action was successful
     */
    function action(bytes calldata data) external override isAuthorized returns (bool success) {
        (address token, uint256 amount, address actor) = abi.decode(data, (address, uint256, address));

        // Validate deposit
        if (!allowedAssets[token]) revert AssetNotAllowed();
        if (amount == 0) revert InvalidAmount();
        if (IERC20Metadata(token).decimals() != 18) revert InvalidDecimals();
        if (_deposited + amount > _depositCap) revert DepositCapExceeded();
        if (paused[token]) revert AssetPaused();

        // Transfer tokens from registry to this contract
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        _deposited += amount;

        // Mint system coins directly to user
        ISystemCoin(address(_registry.systemCoin())).mint(actor, amount);

        emit Deposit(token, amount, amount, actor);

        return true;
    }

    /**
     * @notice Withdraws tokens to the treasury
     * @param token The token to withdraw
     * @param amount The amount to withdraw
     */
    function withdrawToTreasury(address token, uint256 amount) external isAuthorized {
        // Only allowed assets can be withdrawn
        if (!allowedAssets[token]) revert AssetNotAllowed();
        
        // Check if contract has enough balance
        uint256 balance = IERC20Metadata(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        // Transfer tokens to treasury
        bool success = IERC20Metadata(token).transfer(treasury, amount);
        if (!success) revert TransferFailed();
        
        emit TreasuryWithdraw(token, amount, msg.sender);
    }

    /**
     * @notice Updates the treasury address
     * @param newTreasury The new treasury address
     */
    function updateTreasury(address newTreasury) external isAuthorized {
        if (newTreasury == address(0)) revert InvalidTreasury();
        treasury = newTreasury;
        emit TreasuryUpdated(newTreasury, msg.sender);
    }

    /**
     * @notice Updates the allowed assets list
     * @param assets Array of token addresses
     * @param statuses Array of allowed statuses
     */
    function updateAllowedAssets(address[] calldata assets, bool[] calldata statuses) external isAuthorized {
        if (assets.length != statuses.length) revert ArrayLengthMismatch();
        if (assets.length == 0) revert InvalidAmount();

        for (uint256 i = 0; i < assets.length; i++) {
            if (assets[i] == address(0)) revert InvalidAmount();
            allowedAssets[assets[i]] = statuses[i];
            emit AllowedAssetsUpdated(assets[i], statuses[i], msg.sender);
        }
    }

    /**
     * @notice Updates the deposit cap
     * @param newCap The new deposit cap
     */
    function updateDepositCap(uint256 newCap) external isAuthorized {
        if (newCap == 0) revert InvalidAmount();
        _depositCap = newCap;
        emit DepositCapUpdated(newCap, msg.sender);
    }

    /**
     * @notice Gets the current deposit cap
     * @return The current deposit cap
     */
    function getDepositCap() external view returns (uint256) {
        return _depositCap;
    }

    /**
     * @notice Gets the total amount deposited
     * @return The total amount deposited
     */
    function getDeposited() external view returns (uint256) {
        return _deposited;
    }

    /**
     * @notice Emergency withdrawal of tokens to treasury
     * @dev Only callable by authorized addresses
     * @param token The token address to withdraw
     * @param amount The amount to withdraw
     */
    function emergencyWithdraw(address token, uint256 amount) external isAuthorized whenPaused {
        // Check if token is allowed
        if (!allowedAssets[token]) revert AssetNotAllowed();
        
        // Check if contract has enough balance
        uint256 balance = IERC20Metadata(token).balanceOf(address(this));
        if (balance < amount) revert InsufficientBalance();

        // Transfer tokens to treasury
        bool success = IERC20Metadata(token).transfer(treasury, amount);
        if (!success) revert TransferFailed();
        
        // Update deposited amount
        _deposited -= amount;
        
        emit EmergencyWithdraw(token, amount, msg.sender);
    }
} 