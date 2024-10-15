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
  uint24 public constant poolFee = 3000;
  uint160 public constant PRICE_LIMIT = 0;

  constructor(
    ISwapRouter router_
  ) StabilityMOM(address(0), IMOMRegistry(address(0)), IERC20Metadata(address(0)), address(0)) {
    router = router_;
  }

  function action(bytes calldata data) external returns (bool) {
    ISwapRouter.ExactInputSingleParams memory params;
    (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) = abi.decode(data, (address, address, uint256, uint256));
    params = ISwapRouter.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      fee: poolFee,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: amountOutMin,
      sqrtPriceLimitX96: 0
    });
  }

  function _enforceRoute(address tokenIn, address tokenOut) internal view {
    if (allowedAssets[tokenIn] == false || allowedAssets[tokenOut] == false) revert AssetNotAllowed();
  }

  function _enforceEquity(uint256 equityBefore, uint256 equityAfter) internal pure returns (bool) {
    if (equityBefore < equityAfter) revert InvalidSwap();
    return true;
  }
}
