// SPDX-License-Identifier: UNLICENSED

/*
      /\                   
     /  \    _______  ___  
    / /\ \  |_  / _ \/ __| 
   / ____ \  / / (_) \__ \ 
  /_/    \_\/___\___/|___/ 
*/

pragma solidity ^0.8.20;

import {Authorizable} from '@contracts/utils/Authorizable.sol';
import {IMOMRegistry} from '@azosinterfaces/IMOMRegistry.sol';
import {IMOM} from '@azosinterfaces/IMOM.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Pausable} from '@openzeppelin/contracts/utils/Pausable.sol';

abstract contract MOM is Authorizable, IMOM, Pausable {
  // Implementations of MOM will rely heavily on delegatecall therefore do not alter the order of these variables
  // The storage layout of action contracts and MOM implementations must match perfectly
  // Utilize constants and immutable variables in action contracts as they persist in bytecode not in storage
  // Do not use constants or immutable variables for state variables in MOM implementations
  IMOMRegistry internal _registry;
  IERC20Metadata internal _asset;
  IERC20Metadata internal _token;
  IERC20Metadata internal _coin;

  uint256 internal _actionsCounter;
  mapping(uint256 actionId => address logicContract) internal _actions;
  mapping(uint256 actionId => bool isRegistered) internal _isActionRegistered;

  constructor(IMOMRegistry registry, IERC20Metadata asset_, address pauser) Authorizable(address(registry)) {
    _addAuthorization(pauser);
    _registry = registry;
    _asset = asset_;
    _token = _registry.protocolToken();
    _coin = _registry.systemCoin();
    _actionsCounter = 1;
  }

  function _mintCoins(uint256 amount) internal virtual returns (bool success) {
    success = _registry.mintCoin(amount);
    if (!success) revert MintFailed();
  }

  function _mintProtocolTokens(uint256 amount) internal virtual returns (bool success) {
    success = _registry.mintProtocolToken(amount);
    if (!success) revert MintFailed();
  }

  function _burnCoins(uint256 amount) internal virtual returns (bool success) {
    success = _registry.burnCoin(amount);
    if (!success) revert BurnFailed();
  }

  function _burnProtocolTokens(uint256 amount) internal virtual returns (bool success) {
    success = _registry.burnProtocolToken(amount);
    if (!success) revert BurnFailed();
  }

  function _getCoinBalance() internal view virtual returns (uint256) {
    return _asset.balanceOf(address(this));
  }

  function _getProtocolTokenBalance() internal view virtual returns (uint256) {
    return _token.balanceOf(address(this));
  }

  function _getCoinDebt() internal view virtual returns (uint256) {
    return _registry.coinIssuances(address(this));
  }

  function _getTokenDebt() internal view virtual returns (uint256) {
    return _registry.protocolIssuances(address(this));
  }

  function _getCoinLimit() internal view virtual returns (uint256) {
    return _registry.coinLimits(address(this));
  }

  function _getProtocolTokenLimit() internal view virtual returns (uint256) {
    return _registry.protocolLimits(address(this));
  }

  // MOM implementations must override this function
  function _checkpointEquity() internal view virtual returns (uint256 equity) {
    return 0;
  }

  function _getModuleData()
    internal
    view
    virtual
    returns (uint256 protocolIssuance, uint256 coinIssuance, uint256 protocolLimit, uint256 coinLimit)
  {
    return _registry.getModuleData(address(this));
  }

  // @inheritdoc IMOM
  function registerAction(address actionContract) external virtual isRegistry {
    if (actionContract == address(0)) revert InvalidAction();
    _actions[_actionsCounter] = actionContract;
    _isActionRegistered[_actionsCounter] = true;
    emit ActionRegistered(actionContract, _actionsCounter);
    _actionsCounter++;
  }

  // @inheritdoc IMOM
  function deRegisterAction(uint256 actionId) external virtual isRegistry {
    _isActionRegistered[actionId] = false;
    emit ActionDeregistered(_actions[actionId], actionId);
  }

  // @inheritdoc IMOM
  function pause() external virtual isAuthorized {
    _pause();
  }

  /// @inheritdoc IMOM
  function windDown() external virtual override isRegistry whenPaused {
    uint256 coinBalance = _getCoinBalance();
    uint256 protocolTokenBalance = _getProtocolTokenBalance();
    uint256 protocolIssuance = _getTokenDebt();
    uint256 coinIssuance = _getCoinDebt();
    uint256 remainingCoinDebt;
    uint256 remainingTokenDebt;
    if (coinBalance > coinIssuance) {
      _burnCoins(coinIssuance);
      remainingCoinDebt = 0;
    } else {
      _burnCoins(coinBalance);
      remainingCoinDebt = coinIssuance - coinBalance;
    }
    if (protocolTokenBalance > protocolIssuance) {
      _burnProtocolTokens(protocolIssuance);
      remainingTokenDebt = 0;
    } else {
      _burnProtocolTokens(protocolTokenBalance);
      remainingTokenDebt = protocolIssuance - protocolTokenBalance;
    }
    emit WindDown(coinBalance, protocolTokenBalance, remainingCoinDebt, remainingTokenDebt);
  }

  /// @inheritdoc IMOM
  function execute(
    address _to,
    uint256 _value,
    bytes calldata _data
  ) external virtual isRegistry returns (bool, bytes memory) {
    (bool success, bytes memory result) = _to.call{value: _value}(_data);
    emit Executed(_to, _value, _data, success, result);
    return (success, result);
  }

  modifier isRegistry() {
    if (msg.sender != address(_registry)) revert NotAuthorized();
    _;
  }
}
