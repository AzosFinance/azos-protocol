// SPDX-License-Identifier: MIT

pragma solidity ^0.8.20;

import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import {IMOMRegistry} from './IMOMRegistry.sol';

interface IMOM {
  /// @notice Emitted when a new action is registered
  /// @param actionContract The address of the registered action contract
  /// @param logicId The ID assigned to the registered action
  event ActionRegistered(address actionContract, uint256 logicId);

  /// @notice Emitted when an action is deregistered
  /// @param actionContract The address of the deregistered action contract
  /// @param logicId The ID of the deregistered action
  event ActionDeregistered(address actionContract, uint256 logicId);

  /// @notice Emitted when an execute function is called
  /// @param to The target address of the call
  /// @param value The amount of ETH sent with the call
  /// @param data The calldata sent
  /// @param success Whether the call was successful
  /// @param result The raw bytes returned from the call
  event Executed(address to, uint256 value, bytes data, bool success, bytes result);

  /// @notice Emitted when the MOM winds down
  /// @param coinBalance The balance of the MOM's coin
  /// @param protocolTokenBalance The balance of the MOM's protocol token
  /// @param remainingCoinDebt The remaining coin debt after winding down
  /// @param remainingProtocolTokenDebt The remaining protocol token debt after winding down
  event WindDown(
    uint256 coinBalance, uint256 protocolTokenBalance, uint256 remainingCoinDebt, uint256 remainingProtocolTokenDebt
  );

  /// @notice Error thrown when an invalid action is provided
  error InvalidAction();

  /// @notice Error thrown when a mint operation fails
  error MintFailed();

  /// @notice Error thrown when a burn operation fails
  error BurnFailed();

  /// @notice Registers a new action contract
  /// @param actionContract The address of the action contract to register
  function registerAction(address actionContract) external;

  /// @notice Deregisters an existing action contract
  /// @param actionId The ID of the action contract to deregister
  function deRegisterAction(uint256 actionId) external;

  /// @notice Executes an arbitrary low-level call
  /// @dev Only callable by authorized accounts. Use with extreme caution.
  /// @param _to The target address for the call
  /// @param _value The amount of ETH to send with the call
  /// @param _data The calldata to send
  /// @return success Boolean indicating whether the call was successful
  /// @return result The raw bytes returned from the call
  function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);

  /// @notice Pauses the contract
  /// @dev Can only be called by authorized accounts
  function pause() external;

  /// @notice Winds down the MOM, burning coins and protocol tokens
  /// @dev Can only be called by the registry when the contract is paused
  function windDown() external;
}
