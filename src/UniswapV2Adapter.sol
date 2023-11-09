// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IUniswapV2Router02} from '@router/IUniswapV2Router02.sol';

contract UniswapV2Adapter {
  function swap(bytes calldata data) public {
    (uint256 amountIn, uint256 amountOutMin, address[] memory path, uint256 deadline, address router) =
      abi.decode(data, (uint256, uint256, address[], uint256, address));
    IUniswapV2Router02(router).swapExactTokensForTokens(amountIn, amountOutMin, path, address(this), deadline);
  }
}
