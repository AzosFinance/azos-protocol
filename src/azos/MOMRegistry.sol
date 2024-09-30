// SPDX-License-Identifier: MIT

                          
//      /\                   
//     /  \    _______  ___  
//    / /\ \  |_  / _ \/ __| 
//   / ____ \  / / (_) \__ \ 
//  /_/    \_\/___\___/|___/ 
                          
pragma solidity 0.8.20;

import {Authorizable} from '@contracts/utils/Authorizable.sol';
import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {IProtocolToken} from '@interfaces/tokens/IProtocolToken.sol';
import {IOracleRelayer} from '@interfaces/IOracleRelayer.sol';
import {Math, RAY, WAD} from '@libraries/Math.sol';

// Market Operations Module Registry
// This contract is used to register and manage Market Operations Modules (MOMs).  It is authorized on both the system coin and protocol token
// in order to mint and burn tokens.  It also keeps track of each individual module's issuances and limits.
contract MOMRegistry is Authorizable {

  using Math for uint256;

  error NotMOM();
  error InvalidLimit();
  error ProtocolMint();
  error ProtocolBurn();
  error CoinLimit();
  error CoinBurn();
  error InvalidRedemptionPrice();
  error TransferFailed();

  event MOMRegistered(address module, uint256 protocolLimit, uint256 coinLimit, uint256 momId);
  event MOMLimitsAdjusted(address module, uint256 protocolLimit, uint256 coinLimit);
  event MintedProtocolToken(address module, uint256 amount, uint256 debt);
  event BurnedProtocolToken(address module, uint256 amount, uint256 debt);
  event MintedCoin(address module, uint256 amount, uint256 coinDebt);
  event BurnedCoin(address module, uint256 amount, uint256 coinDebt);

  uint256 public constant RAY_TO_WAD = 1e9;

  ISystemCoin public systemCoin;
  IProtocolToken public protocolToken;
  IOracleRelayer public oracleRelayer;

  uint256 public momCounterId;

  mapping(address module => uint256 protocolIssuance) public protocolIssuances;
  mapping(address module => uint256 coinIssuance) public coinIssuances;
  mapping(address module => uint256 protocolLimit) public protocolLimits;
  mapping(address module => uint256 coinLimit) public coinLimits;

  // allows modules to be enumerated
  mapping(uint256 momId => address module) public modules;
  // mapping for gas optimization
  mapping(address module => bool isMOM) public isMOM;

  constructor(address _systemCoin, address _protocolToken, address _oracleRelayer, address governor) Authorizable(governor) {
    systemCoin = ISystemCoin(_systemCoin);
    protocolToken = IProtocolToken(_protocolToken);
    oracleRelayer = IOracleRelayer(_oracleRelayer);
    momCounterId = 1;
  }

  ///////////////////////////////////////////////////////
  //  ________  _ _____  _____ ____  _      ____  _
  // /  __/\  \///__ __\/  __//  __\/ \  /|/  _ \/ \
  // |  \   \  /   / \  |  \  |  \/|| |\ ||| / \|| |
  // |  /_  /  \   | |  |  /_ |    /| | \||| |-||| |_/\
  // \____\/__/\\  \_/  \____\\_/\_\\_/  \|\_/ \|\____/
  ////////////////////////////////////////////////////////

  /// @notice Registers a new Market Operations Module (MOM)
  /// @dev Only callable by authorized accounts. Assigns limits and increments the MOM counter.
  /// @param module The address of the MOM to be registered
  /// @param protocolLimit The maximum amount of protocol tokens the MOM can issue
  /// @param coinLimit The maximum amount of system coins the MOM can issue
  /// @custom:emits MOMRegistered Emitted with the module address, limits, and assigned MOM ID
  function registerMOM(address module, uint256 protocolLimit, uint256 coinLimit) public isAuthorized() {
    protocolLimits[module] = protocolLimit;
    coinLimits[module] = coinLimit;
    modules[momCounterId] = module;
    momCounterId++;
    emit MOMRegistered(module, protocolLimit, coinLimit, momCounterId);
  }

  /// @notice Adjusts the issuance limits for an existing Market Operations Module (MOM)
  /// @dev Only callable by authorized accounts. Ensures new limits are not lower than current issuances.
  /// @param module The address of the MOM to adjust limits for
  /// @param protocolLimit The new maximum issuance limit for protocol tokens
  /// @param coinLimit The new maximum issuance limit for system coins
  /// @custom:throws InvalidLimit If new limits are lower than current issuances
  /// @custom:emits MOMLimitsAdjusted Emitted with the module address and new limits
  function adjustMOM(address module, uint256 protocolLimit, uint256 coinLimit) public isAuthorized() {
    if (protocolLimit > protocolIssuances[module] || coinLimit > coinIssuances[module]) revert InvalidLimit();
    protocolLimits[module] = protocolLimit;
    coinLimits[module] = coinLimit;
    emit MOMLimitsAdjusted(module, protocolLimit, coinLimit);
  }

  ////////////////////////////////////////////////////////////////
  //   ,---.    ,---.    ,-----.    ,---.    ,---.   .-'''-.    //
  //   |    \  /    |  .'  .-,  '.  |    \  /    |  / _     \   //
  //   |  ,  \/  ,  | / ,-.|  \ _ \ |  ,  \/  ,  | (`' )/`--'   //
  //   |  |\_   /|  |;  \  '_ /  | :|  |\_   /|  |(_ o _).      //
  //   |  _( )_/ |  ||  _`,/ \ _/  ||  _( )_/ |  | (_,_). '.    //
  //   | (_ o _) |  |: (  '\_/ \   ;| (_ o _) |  |.---.  \  :   //
  //   |  (_,_)  |  | \ `"/  \  ) / |  (_,_)  |  |\    `-'  |   //
  //   |  |      |  |  '. \_/``".'  |  |      |  | \       /    //
  //   '--'      '--'    '-----'    '--'      '--'  `-...-'     //
  ////////////////////////////////////////////////////////////////

  /// @notice Mints protocol tokens for a registered MOM
  /// @dev Only callable by registered MOMs. Enforces issuance limits.
  /// @param amount The amount of protocol tokens to mint
  /// @custom:throws ProtocolMint If minting would exceed the module's protocol token limit
  /// @custom:emits MintedProtocolToken Emitted with the module address and minted amount
  function mintProtocolToken(uint256 amount) public onlyMOM() {
    address module = msg.sender;
    uint256 debt = protocolIssuances[module];
    if (!_enforceProtocolMint(module, amount, debt)) revert ProtocolMint();
    debt += amount;
    protocolIssuances[module] = debt;
    protocolToken.mint(module, amount);
    emit MintedProtocolToken(module, amount, debt);
  }

  /// @notice Burns protocol tokens for a registered MOM
  /// @dev Only callable by registered MOMs. Requires prior token approval.
  /// @param amount The amount of protocol tokens to burn
  /// @custom:throws ProtocolBurn If burning would result in negative issuance
  /// @custom:emits BurnedProtocolToken Emitted with the module address and burned amount
  function burnProtocolToken(uint256 amount) public onlyMOM() {
    address module = msg.sender;
    uint256 debt = protocolIssuances[module];
    if (!_enforceProtocolBurn(amount, debt)) revert ProtocolBurn();
    debt -= amount;
    protocolIssuances[module] = debt;
    protocolToken.transferFrom(module, address(this), amount);
    protocolToken.burn(amount);
    emit BurnedProtocolToken(module, amount, debt);
  }

  /// @notice Mints system coins for a registered MOM
  /// @dev Only callable by registered MOMs. Enforces issuance limits.
  /// @param amount The amount of system coins to mint
  /// @custom:throws CoinLimit If minting would exceed the module's coin limit
  /// @custom:emits MintedCoin Emitted with the module address and minted amount
  function mintCoin(uint256 amount) public onlyMOM() {
    address module = msg.sender;
    uint256 wadRedemptionPrice = oracleRelayer.redemptionPrice() / RAY_TO_WAD;
    if (wadRedemptionPrice == 0) revert InvalidRedemptionPrice();
    uint256 adjustedDebt = amount.wmul(wadRedemptionPrice);
    uint256 coinDebt = coinIssuances[module];
    if (!_enforceCoinMint(module, adjustedDebt, coinDebt)) revert CoinLimit();
    coinDebt += adjustedDebt;
    coinIssuances[module] = coinDebt;
    systemCoin.mint(module, amount);
    emit MintedCoin(module, amount, coinDebt);
  }

  /// @notice Burns system coins for a registered MOM
  /// @dev Only callable by registered MOMs. Requires prior coin approval.
  /// @param amount The amount of system coins to burn
  /// @custom:throws CoinLimit If burning would result in negative issuance
  /// @custom:emits BurnedCoin Emitted with the module address and burned amount
  function burnCoin(uint256 amount) public onlyMOM() {
    address module = msg.sender;
    uint256 wadRedemptionPrice = oracleRelayer.redemptionPrice() / RAY_TO_WAD;
    if (wadRedemptionPrice == 0) revert InvalidRedemptionPrice();
    uint256 adjustedDebt = amount.wmul(wadRedemptionPrice);
    uint256 coinDebt = coinIssuances[module];
    if (!_enforceCoinBurn(adjustedDebt, coinDebt)) revert CoinLimit();
    coinDebt -= adjustedDebt;
    coinIssuances[module] = coinDebt;
    bool success = systemCoin.transferFrom(module, address(this), amount);
    if (!success) revert TransferFailed();
    systemCoin.burn(amount);
    emit BurnedCoin(module, amount, coinDebt);
  }

  /////////////////////////////////////////////////////
  // _  _      _____  _____ ____  _      ____  _        
  // / \/ \  /|/__ __\/  __//  __\/ \  /|/  _ \/ \
  // | || |\ ||  / \  |  \  |  \/|| |\ ||| / \|| |
  // | || | \||  | |  |  /_ |    /| | \||| |-||| |_/\
  // \_/\_/  \|  \_/  \____\\_/\_\\_/  \|\_/ \|\____/
  /////////////////////////////////////////////////////

  function _enforceProtocolMint(address module, uint256 amount, uint256 debt) internal view returns (bool) {
    if (debt + amount > protocolLimits[module]) return false;
    return true;
  }

  function _enforceProtocolBurn(uint256 amount, uint256 debt) internal pure returns (bool) {
    if (debt - amount > 0) return false;
    return true;
  }

  function _enforceCoinMint(address module, uint256 amount, uint256 adjustedDebt) internal view returns (bool) {
    if (adjustedDebt + amount > coinLimits[module]) return false;
    return true;
  }

  function _enforceCoinBurn(uint256 amount, uint256 adjustedDebt) internal pure returns (bool) {
    if (adjustedDebt - amount > 0) return false;
    return true;
  }

  /// @notice Executes an arbitrary low-level call
  /// @dev Only callable by authorized accounts. Use with extreme caution.
  /// @param _to The target address for the call
  /// @param _value The amount of ETH to send with the call
  /// @param _data The calldata to send
  /// @return success Boolean indicating whether the call was successful
  /// @return result The raw bytes returned from the call
  /// @custom:security This function can potentially execute malicious code if not properly secured
    function execute(
        address _to,
        uint256 _value,
        bytes calldata _data
    ) external isAuthorized() returns (bool, bytes memory) {
        (bool success, bytes memory result) = _to.call{value:_value}(_data);
        return (success, result);
    }


  /// @notice Restricts function access to registered Market Operations Modules (MOMs) or self
  /// @dev A MOM is considered registered if it has non-zero protocol or coin limits
  /// @custom:throws NotMOM if the caller is not a registered MOM
  modifier onlyMOM() {
    if (!isMOM[msg.sender] || !_isAuthorized(msg.sender)) revert NotMOM();
    _;
  }
}