// SPDX-License-Identifier: MIT

/////////////////////////////////
//      /\                     //
//     /  \    _______  ___    //
//    / /\ \  |_  / _ \/ __|   //
//   / ____ \  / / (_) \__ \   //
//  /_/    \_\/___\___/|___/   //
/////////////////////////////////

pragma solidity ^0.8.20;

import {Authorizable} from '@contracts/utils/Authorizable.sol';
import {IMOMRegistry} from '@azosinterfaces/IMOMRegistry.sol';
import {IMOM} from '@azosinterfaces/IMOM.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

abstract contract MOM is Authorizable, IMOM {
  // Implementations of MOM will rely heavily on delegatecall therefore do not alter the order of these variables
  // The storage layout of action contracts and MOM implementations must match perfectly
  // Utilize constants and immutable variables in action contracts as they persist in bytecode not in storage
  IMOMRegistry internal immutable _registry;
  IERC20 internal immutable _systemCoin;
  IERC20 internal immutable _token;

  uint256 internal _actionsCounter;
  mapping(uint256 logicId => address logicContract) internal _actions;
  mapping(uint256 logicId => bool isRegistered) internal _isActionRegistered;

  constructor(IMOMRegistry registry, IERC20 token) Authorizable(address(registry)) {
    _registry = registry;
    _systemCoin = registry.systemCoin();
    _token = token;
    _actionsCounter = 1;
  }

  function registerAction(address actionContract) external virtual isRegistry {
    if (actionContract == address(0)) revert InvalidAction();
    _actions[_actionsCounter] = actionContract;
    _isActionRegistered[_actionsCounter] = true;
    emit ActionRegistered(actionContract, _actionsCounter);
    _actionsCounter++;
  }

  function deRegisterAction(uint256 logicId) external virtual isRegistry {
    _isActionRegistered[logicId] = false;
    emit ActionDeregistered(_actions[logicId], logicId);
  }

  function _mintCoins(uint256 amount) internal virtual returns (bool success) {
    success = _registry.mintCoin(amount);
  }

  function _mintProtocolTokens(uint256 amount) internal virtual returns (bool success) {
    success = _registry.mintProtocolToken(amount);
  }

  function _burnCoins(uint256 amount) internal virtual returns (bool success) {
    success = _registry.burnCoin(amount);
  }

  function _burnProtocolTokens(uint256 amount) internal virtual returns (bool success) {
    success = _registry.burnProtocolToken(amount);
  }

  function _getCoinBalance() internal view virtual returns (uint256) {
    return _systemCoin.balanceOf(address(this));
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
