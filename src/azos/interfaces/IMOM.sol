pragma solidity ^0.8.20;

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

  /// @notice Error thrown when an invalid action is provided
  error InvalidAction();

  /// @notice Registers a new action contract
  /// @param actionContract The address of the action contract to register
  function registerAction(address actionContract) external;

  /// @notice Deregisters an existing action contract
  /// @param logicId The ID of the action contract to deregister
  function deRegisterAction(uint256 logicId) external;

  /// @notice Executes an arbitrary low-level call
  /// @dev Only callable by authorized accounts. Use with extreme caution.
  /// @param _to The target address for the call
  /// @param _value The amount of ETH to send with the call
  /// @param _data The calldata to send
  /// @return success Boolean indicating whether the call was successful
  /// @return result The raw bytes returned from the call
  function execute(address _to, uint256 _value, bytes calldata _data) external returns (bool, bytes memory);
}
