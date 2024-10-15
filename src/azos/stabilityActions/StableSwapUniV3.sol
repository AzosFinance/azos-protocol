// SPDX-License-Identifier: UNLICENSED

/*
      /\                   
     /  \    _______  ___  
    / /\ \  |_  / _ \/ __| 
   / ____ \  / / (_) \__ \ 
  /_/    \_\/___\___/|___/ 
*/

pragma solidity ^0.8.20;

import {StabilityMOM, IMOMRegistry, IERC20Metadata} from '@azos/StabilityMOM.sol';
import {ISwapRouter} from '@azos/interfaces/Uniswap/ISwapRouter.sol';

contract StableSwapUniV3 is StabilityMOM {
  ISwapRouter public immutable router;

  constructor(
    ISwapRouter router_
  ) StabilityMOM(address(0), IMOMRegistry(address(0)), IERC20Metadata(address(0)), address(0)) {
    router = router_;
  }

  function action(bytes calldata data) external returns (bool) {
  }

  function _enforceRoute(address tokenIn, address tokenOut) internal view {
    if (allowedAssets[tokenIn] == false || allowedAssets[tokenOut] == false) revert AssetNotAllowed();
  }

  function _enforceEquity(uint256 equityBefore, uint256 equityAfter) internal pure returns (bool) {
    if (equityBefore < equityAfter) revert InvalidSwap();
    return true;
  }
}
