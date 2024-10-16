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
import {IPeripheryImmutableState} from '@azos/interfaces/Uniswap/IPeripheryImmutableState.sol';
import {IUniswapV3Pool} from '@azos/interfaces/Uniswap/IUniswapV3Pool.sol';
import {CallbackValidation} from '@azos/interfaces/Uniswap/CallBackValidation.sol';
// #todo if we're not using pool address we can remove it
import {PoolAddress} from '@azos/interfaces/Uniswap/PoolAddress.sol';
import {Path} from '@azos/interfaces/Uniswap/Path.sol';
import {Math} from '@openzeppelin/contracts/utils/math/Math.sol';

contract StableSwapUniV3 is StabilityMOM {
  using Path for bytes;

  ISwapRouter public immutable router;
  uint24 public constant POOL_FEE = 3000;
  address internal immutable _token0;
  address internal immutable _token1;
  // Our price target when inputting token0
  uint160 internal immutable token0InputPriceLimit;
  // Our price target when inputting token1
  uint160 internal immutable token1InputPriceLimit;

  constructor(ISwapRouter router_)
    StabilityMOM(address(0), IMOMRegistry(address(0)), IERC20Metadata(address(0)), address(0), uint256(0))
  {
    router = router_;

    address token0Before = address(_asset);
    address token1Before = address(_coin);
    address token0;
    address token1;
    if (token0Before > token1Before) {
      token0 = token1Before;
      token1 = token0Before;
    } else {
      token0 = token0Before;
      token1 = token1Before;
    }
    _token0 = token0;
    _token1 = token1;
    uint256 token0Decimals = IERC20Metadata(token0).decimals();
    uint256 token1Decimals = IERC20Metadata(token1).decimals();
    uint256 positiveDecimalsAdjustment;
    uint256 negativeDecimalsAdjustment;
    uint160 token0PriceLimit;
    uint160 token1PriceLimit;
    // If token0 has fewer decimals than token1, we need to derease the price limits to account for the difference
    if (token0Decimals < token1Decimals) {
      negativeDecimalsAdjustment = (token1Decimals - token0Decimals);
    }
    // If token0 has greater decimals than token1 we need to increase the price limits to account for the difference
    if (token0Decimals > token1Decimals) {
      positiveDecimalsAdjustment = (token0Decimals - token1Decimals);
    }

    // We represent the unadjusted price limits for swap input token 0 as 1.003 and swap input token 1 as 0.997
    uint256 inputToken0Price = 1.003e18;
    uint256 inputToken1Price = 0.997e18;

    if (negativeDecimalsAdjustment > 0) {
      token0PriceLimit = uint160(Math.sqrt(inputToken0Price / 10 ** negativeDecimalsAdjustment) * 2 ** 96);
      token1PriceLimit = uint160(Math.sqrt(inputToken1Price / 10 ** negativeDecimalsAdjustment) * 2 ** 96);
    } else if (positiveDecimalsAdjustment > 0) {
      token0PriceLimit = uint160(Math.sqrt(inputToken0Price * 10 ** positiveDecimalsAdjustment) * 2 ** 96);
      token1PriceLimit = uint160(Math.sqrt(inputToken1Price * 10 ** positiveDecimalsAdjustment) * 2 ** 96);
    } else {
      token0PriceLimit = uint160(Math.sqrt(inputToken0Price) * 2 ** 96);
      token1PriceLimit = uint160(Math.sqrt(inputToken1Price) * 2 ** 96);
    }
    token0InputPriceLimit = token0PriceLimit;
    token1InputPriceLimit = token1PriceLimit;
  }

  // #todo we need to reward the keepers for caling this function
  function action(bytes calldata data) external returns (bool) {
    ISwapRouter.ExactInputSingleParams memory params;
    uint160 sqrtPriceLimitX96;
    (address tokenIn, address tokenOut, uint256 amountIn, uint256 amountOutMin) =
      abi.decode(data, (address, address, uint256, uint256));

    if (tokenIn == _token0) {
      sqrtPriceLimitX96 = token0InputPriceLimit;
    } else if (tokenIn == _token1) {
      sqrtPriceLimitX96 = token1InputPriceLimit;
    }
    _enforceRoute(tokenIn, tokenOut);

    uint256 equityBefore = checkpointEquity();

    params = ISwapRouter.ExactInputSingleParams({
      tokenIn: tokenIn,
      tokenOut: tokenOut,
      fee: POOL_FEE,
      recipient: address(this),
      deadline: block.timestamp,
      amountIn: amountIn,
      amountOutMinimum: amountOutMin,
      sqrtPriceLimitX96: sqrtPriceLimitX96
    });

    uint256 amountOut = router.exactInputSingle(params);

    uint256 equityAfter = checkpointEquity();
    _enforceEquity(equityBefore, equityAfter);
    _payKeeper(equityBefore, equityAfter);
    emit Swap(tokenIn, tokenOut, amountIn, amountOut);
    return true;
  }

  function uniswapV3SwapCallback(int256 amount0Delta, int256 amount1Delta, bytes calldata _data) external {
    if (amount0Delta <= 0 && amount1Delta <= 0) revert InvalidDelta();
    SwapCallbackData memory data = abi.decode(_data, (SwapCallbackData));
    (address tokenIn, address tokenOut, uint24 fee) = data.path.decodeFirstPool();
    _enforceRoute(tokenIn, tokenOut);
    CallbackValidation.verifyCallback(IPeripheryImmutableState(address(router)).factory(), tokenIn, tokenOut, fee);

    uint256 amountToPay;
    if (amount0Delta > 0) {
      amountToPay = uint256(amount0Delta);
    } else {
      amountToPay = uint256(amount1Delta);
    }

    // All swaps are exact input swaps, so we pay the verified pool
    IERC20Metadata(tokenIn).transfer(msg.sender, amountToPay);
  }

  function _enforceRoute(address tokenIn, address tokenOut) internal view {
    if (allowedAssets[tokenIn] == false || allowedAssets[tokenOut] == false) revert AssetNotAllowed();
  }

  function _payKeeper(uint256 equityBefore, uint256 equityAfter) internal {
    uint256 equityChange = equityAfter - equityBefore;
    uint256 keeperFee = equityChange / 10;
    if (equityChange > 0) {
      _coin.transfer(msg.sender, keeperFee);
      emit KeeperPayment(msg.sender, keeperFee);
    }
  }

  struct SwapCallbackData {
    bytes path;
    address payer;
  }
}
