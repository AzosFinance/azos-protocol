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
import {IRouter} from '@azos/interfaces/Aerodrome/IRouter.sol';

contract StableSwapAero is StabilityMOM {
  IRouter public immutable router;
  address public immutable factory;

  constructor(
    IRouter router_,
    address factory_
  ) StabilityMOM(address(0), IMOMRegistry(address(0)), IERC20Metadata(address(0)), address(0), uint256(0)) {
    router = router_;
    factory = factory_;
  }

  function action(bytes calldata data) external returns (bool) {
    uint256 equityBefore = _checkpointEquity();
    (uint256 amountIn, uint256 amountOutMin, IRouter.Route[] memory routes, uint256 deadline) =
      abi.decode(data, (uint256, uint256, IRouter.Route[], uint256));
    _enforceRoute(routes);
    router.swapExactTokensForTokens(amountIn, amountOutMin, routes, address(this), deadline);
    uint256 equityAfter = _checkpointEquity();
    _enforceEquity(equityBefore, equityAfter);
    return true;
  }

  function _enforceRoute(IRouter.Route[] memory routes) internal view {
    for (uint256 i = 0; i < routes.length; i++) {
      if (routes[i].factory != factory) revert InvalidRoute();
      if (allowedAssets[routes[i].from] == false || allowedAssets[routes[i].to] == false) revert AssetNotAllowed();
    }
  }

  function _enforceEquity(uint256 equityBefore, uint256 equityAfter) internal pure returns (bool) {
    if (equityBefore < equityAfter) revert InvalidSwap();
    return true;
  }
}
