// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ISAFEEngine as SAFEEngineLike} from '@interfaces/ISAFEEngine.sol';
import {IToken as DSTokenLike} from '@interfaces/external/IToken.sol';

import {IAuthorizable} from '@interfaces/utils/IAuthorizable.sol';
import {IDisableable} from '@interfaces/utils/IDisableable.sol';

interface ICoinJoin is IAuthorizable, IDisableable {
  // --- Events ---
  event Join(address _sender, address _account, uint256 _wad);
  event Exit(address _sender, address _account, uint256 _wad);

  // --- Data ---
  function safeEngine() external view returns (SAFEEngineLike _safeEngine);
  function systemCoin() external view returns (DSTokenLike _systemCoin);
  function decimals() external view returns (uint256 _decimals);

  function join(address _account, uint256 _wad) external;
  function exit(address _account, uint256 _wad) external;
}
