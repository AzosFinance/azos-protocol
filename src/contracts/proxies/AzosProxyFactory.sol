// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {AzosProxy} from '@contracts/proxies/AzosProxy.sol';
import {IAzosProxy} from '@interfaces/proxies/IAzosProxy.sol';
import {IAzosProxyFactory} from '@interfaces/proxies/IAzosProxyFactory.sol';

/**
 * @title  AzosProxyFactory
 * @notice This contract is used to deploy new AzosProxy instances
 */
contract AzosProxyFactory is IAzosProxyFactory {
  // --- Data ---

  /// @inheritdoc IAzosProxyFactory
  mapping(address _proxyAddress => bool _exists) public isProxy;

  /// @inheritdoc IAzosProxyFactory
  mapping(address _owner => IAzosProxy) public proxies;

  /// @inheritdoc IAzosProxyFactory
  mapping(address _owner => uint256 nonce) public nonces;

  // --- Methods ---

  /// @inheritdoc IAzosProxyFactory
  function build() external returns (address payable _proxy) {
    _proxy = _build(msg.sender);
  }

  /// @inheritdoc IAzosProxyFactory
  function build(address _owner) external returns (address payable _proxy) {
    _proxy = _build(_owner);
  }

  /// @notice Internal method used to deploy a new proxy instance
  function _build(address _owner) internal returns (address payable _proxy) {
    // Not allow new _proxy if the user already has one and remains being the owner
    if (proxies[_owner] != IAzosProxy(payable(address(0))) && proxies[_owner].owner() == _owner) {
      revert AlreadyHasProxy(_owner, proxies[_owner]);
    }
    // Calculate the salt for the owner, incrementing their nonce in the process
    bytes32 _salt = keccak256(abi.encode(_owner, nonces[_owner]++));
    // Create the new proxy
    _proxy = payable(address(new AzosProxy{salt: _salt}(_owner)));
    isProxy[_proxy] = true;
    proxies[_owner] = IAzosProxy(_proxy);
    emit Created(msg.sender, _owner, address(_proxy));
  }
}
