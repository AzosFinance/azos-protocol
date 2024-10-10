// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {IProtocolToken} from '@interfaces/tokens/IProtocolToken.sol';
import {IOracleRelayer} from '@interfaces/IOracleRelayer.sol';

interface IMOMRegistry {
  // Events
  event MOMRegistered(address module, uint256 protocolLimit, uint256 coinLimit, uint256 momId);
  event MOMLimitsAdjusted(address module, uint256 protocolLimit, uint256 coinLimit);
  event MintedProtocolToken(address module, uint256 amount, uint256 debt);
  event BurnedProtocolToken(address module, uint256 amount, uint256 debt);
  event MintedCoin(address module, uint256 amount, uint256 coinDebt);
  event BurnedCoin(address module, uint256 amount, uint256 coinDebt);

  // Custom Errors
  error NotMOM();
  error InvalidLimit();
  error ProtocolMint();
  error ProtocolBurn();
  error CoinLimit();
  error CoinBurn();
  error InvalidRedemptionPrice();
  error TransferFailed();
  error InvalidModule();
  error MOMWindDown();

  // Constants
  function RAY_TO_WAD() external view returns (uint256);

  // State Variables
  function systemCoin() external view returns (ISystemCoin);
  function protocolToken() external view returns (IProtocolToken);
  function oracleRelayer() external view returns (IOracleRelayer);
  function momCounterId() external view returns (uint256);

  // Mappings
  function protocolIssuances(address module) external view returns (uint256);
  function coinIssuances(address module) external view returns (uint256);
  function protocolLimits(address module) external view returns (uint256);
  function coinLimits(address module) external view returns (uint256);
  function modules(uint256 momId) external view returns (address);
  function isMOM(address module) external view returns (bool);

  // Functions
  /// @notice Registers a new Market Operations Module (MOM)
  /// @dev Only callable by authorized accounts. Assigns limits and increments the MOM counter.
  /// @param module The address of the MOM to be registered
  /// @param protocolLimit The maximum amount of protocol tokens the MOM can issue
  /// @param coinLimit The maximum amount of system coins the MOM can issue
  /// @param status The initial status of the MOM (active or inactive)
  function registerMOM(address module, uint256 protocolLimit, uint256 coinLimit, bool status) external;

  /// @notice Adjusts the issuance limits for an existing Market Operations Module (MOM)
  /// @dev Only callable by authorized accounts. Ensures new limits are not lower than current issuances.
  /// @param module The address of the MOM to adjust limits for
  /// @param protocolLimit The new maximum issuance limit for protocol tokens
  /// @param coinLimit The new maximum issuance limit for system coins
  function adjustMOM(address module, uint256 protocolLimit, uint256 coinLimit) external;

  /// @notice Mints protocol tokens for a registered MOM
  /// @dev Only callable by registered MOMs. Enforces issuance limits.
  /// @param amount The amount of protocol tokens to mint
  function mintProtocolToken(uint256 amount) external returns (bool);

  /// @notice Burns protocol tokens for a registered MOM
  /// @dev Only callable by registered MOMs. Requires prior token approval.
  /// @param amount The amount of protocol tokens to burn
  function burnProtocolToken(uint256 amount) external returns (bool);

  /// @notice Mints system coins for a registered MOM
  /// @dev Only callable by registered MOMs. Enforces issuance limits.
  /// @param amount The amount of system coins to mint
  function mintCoin(uint256 amount) external returns (bool);

  /// @notice Burns system coins for a registered MOM
  /// @dev Only callable by registered MOMs. Requires prior coin approval.
  /// @param amount The amount of system coins to burn
  function burnCoin(uint256 amount) external returns (bool);

  /// @notice Get all data associated with a specific module
  /// @param module The address of the module to query
  /// @return protocolIssuance The protocol token issuance for the module
  /// @return coinIssuance The system coin issuance for the module
  /// @return protocolLimit The protocol token limit for the module
  /// @return coinLimit The system coin limit for the module
  function getModuleData(address module)
    external
    view
    returns (uint256 protocolIssuance, uint256 coinIssuance, uint256 protocolLimit, uint256 coinLimit);

  /// @notice Executes multiple arbitrary low-level calls
  /// @dev Only callable by authorized accounts. Use with extreme caution.
  /// @param _tos The target addresses for the calls
  /// @param _values The amounts of ETH to send with each call
  /// @param _datas The calldatas to send
  /// @return successes Array of booleans indicating whether each call was successful
  /// @return results Array of raw bytes returned from each call
  function execute(address[] calldata _tos, uint256[] calldata _values, bytes[] calldata _datas) external returns (bool[] memory, bytes[] memory);
}
