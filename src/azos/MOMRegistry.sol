// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

/*
      /\                   
     /  \    _______  ___  
    / /\ \  |_  / _ \/ __| 
   / ____ \  / / (_) \__ \ 
  /_/    \_\/___\___/|___/ 
*/

import {Authorizable} from '@contracts/utils/Authorizable.sol';
import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {IProtocolToken} from '@interfaces/tokens/IProtocolToken.sol';
import {IOracleRelayer} from '@interfaces/IOracleRelayer.sol';
import {Math, RAY, WAD} from '@libraries/Math.sol';
import {IMOMRegistry} from '@azosinterfaces/IMOMRegistry.sol';
import {IMOM} from '@azosinterfaces/IMOM.sol';

/// @title Market Operations Module Registry
/// @notice This contract is used to register and manage Market Operations Modules (MOMs). It is authorized on both the system coin and protocol token
/// in order to mint and burn tokens. It also keeps track of each individual module's issuances and limits.
contract MOMRegistry is Authorizable, IMOMRegistry {
  using Math for uint256;

  uint256 public constant RAY_TO_WAD = 1e9;

  ISystemCoin public systemCoin;
  IProtocolToken public protocolToken;
  IOracleRelayer public oracleRelayer;

  uint256 public momCounterId;

  mapping(address module => uint256 protocolIssuance) public protocolIssuances;
  mapping(address module => uint256 coinIssuance) public coinIssuances;
  mapping(address module => uint256 protocolLimit) public protocolLimits;
  mapping(address module => uint256 coinLimit) public coinLimits;
  mapping(address module => bool isMOM) public isMOM;
  mapping(uint256 momId => address module) public modules;

  constructor(
    address _systemCoin,
    address _protocolToken,
    address _oracleRelayer,
    address governor
  ) Authorizable(governor) {
    systemCoin = ISystemCoin(_systemCoin);
    protocolToken = IProtocolToken(_protocolToken);
    oracleRelayer = IOracleRelayer(_oracleRelayer);
    momCounterId = 1;
  }

  /// @inheritdoc IMOMRegistry
  function registerMOM(address module, uint256 protocolLimit, uint256 coinLimit, bool status) external isAuthorized {
    if (protocolLimit == 0 || coinLimit == 0) revert InvalidLimit();
    if (module == address(0)) revert InvalidModule();
    protocolLimits[module] = protocolLimit;
    coinLimits[module] = coinLimit;
    modules[momCounterId] = module;
    if (status == false) {
      if (protocolIssuances[module] != 0 || coinIssuances[module] != 0) revert MOMWindDown();
    }
    isMOM[module] = status;
    momCounterId++;
    emit MOMRegistered(module, protocolLimit, coinLimit, momCounterId);
  }

  /// @inheritdoc IMOMRegistry
  function adjustMOM(address module, uint256 protocolLimit, uint256 coinLimit) external isAuthorized {
    if (protocolLimit > protocolIssuances[module] || coinLimit > coinIssuances[module]) revert InvalidLimit();
    protocolLimits[module] = protocolLimit;
    coinLimits[module] = coinLimit;
    emit MOMLimitsAdjusted(module, protocolLimit, coinLimit);
  }

  /// @inheritdoc IMOMRegistry
  function mintProtocolToken(uint256 amount) public onlyMOM returns (bool) {
    address module = msg.sender;
    uint256 debt = protocolIssuances[module];
    if (!_enforceProtocolMint(module, amount, debt)) revert ProtocolMint();
    debt += amount;
    protocolIssuances[module] = debt;
    protocolToken.mint(module, amount);
    emit MintedProtocolToken(module, amount, debt);
    return true;
  }

  /// @inheritdoc IMOMRegistry
  function burnProtocolToken(uint256 amount) public onlyMOM returns (bool) {
    address module = msg.sender;
    uint256 debt = protocolIssuances[module];
    if (!_enforceProtocolBurn(amount, debt)) revert ProtocolBurn();
    debt -= amount;
    protocolIssuances[module] = debt;
    protocolToken.transferFrom(module, address(this), amount);
    protocolToken.burn(amount);
    emit BurnedProtocolToken(module, amount, debt);
    return true;
  }

  /// @inheritdoc IMOMRegistry
  function mintCoin(uint256 amount) public onlyMOM returns (bool) {
    address module = msg.sender;
    uint256 wadRedemptionPrice = getRedemptionPrice();
    if (wadRedemptionPrice == 0) revert InvalidRedemptionPrice();
    uint256 adjustedDebt = amount.wmul(wadRedemptionPrice);
    uint256 coinDebt = coinIssuances[module];
    if (!_enforceCoinMint(module, adjustedDebt, coinDebt)) revert CoinLimit();
    coinDebt += adjustedDebt;
    coinIssuances[module] = coinDebt;
    systemCoin.mint(module, amount);
    emit MintedCoin(module, amount, coinDebt);
    return true;
  }

  /// @inheritdoc IMOMRegistry
  function burnCoin(uint256 amount) public onlyMOM returns (bool) {
    address module = msg.sender;
    uint256 wadRedemptionPrice = getRedemptionPrice();
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
    return true;
  }

  /// @notice Returns the normalized redemption price of the system coin
  function getRedemptionPrice() public returns (uint256) {
    return oracleRelayer.redemptionPrice() / RAY_TO_WAD;
  }

  function _enforceProtocolMint(address module, uint256 amount, uint256 debt) private view returns (bool) {
    if (debt + amount > protocolLimits[module]) return false;
    return true;
  }

  function _enforceProtocolBurn(uint256 amount, uint256 debt) private pure returns (bool) {
    if (debt - amount > 0) return false;
    return true;
  }

  function _enforceCoinMint(address module, uint256 amount, uint256 adjustedDebt) private view returns (bool) {
    if (adjustedDebt + amount > coinLimits[module]) return false;
    return true;
  }

  function _enforceCoinBurn(uint256 amount, uint256 adjustedDebt) private pure returns (bool) {
    if (adjustedDebt - amount > 0) return false;
    return true;
  }

  /// @inheritdoc IMOMRegistry
  function getModuleData(address module)
    external
    view
    returns (uint256 protocolIssuance, uint256 coinIssuance, uint256 protocolLimit, uint256 coinLimit)
  {
    return (protocolIssuances[module], coinIssuances[module], protocolLimits[module], coinLimits[module]);
  }

  /// @inheritdoc IMOMRegistry
  function execute(
    address[] calldata _tos,
    uint256[] calldata _values,
    bytes[] calldata _datas
  ) external isAuthorized returns (bool[] memory, bytes[] memory) {
    if (_tos.length != _values.length || _tos.length != _datas.length) revert ArraysMustHaveSameLength();

    bool[] memory successes = new bool[](_tos.length);
    bytes[] memory results = new bytes[](_tos.length);

    for (uint256 i = 0; i < _tos.length; i++) {
      (bool success, bytes memory result) = _tos[i].call{value: _values[i]}(_datas[i]);
      successes[i] = success;
      results[i] = result;
    }

    return (successes, results);
  }

  /// @notice Restricts function access to registered Market Operations Modules (MOMs) or self
  /// @dev A MOM is considered registered if it has non-zero protocol or coin limits
  modifier onlyMOM() {
    if (!isMOM[msg.sender] || !_isAuthorized(msg.sender)) revert NotMOM();
    _;
  }
}
