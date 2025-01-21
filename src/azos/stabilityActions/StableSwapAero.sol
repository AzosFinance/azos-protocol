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
    address factory_,
    IMOMRegistry registry_,
    IERC20Metadata asset_,
    address pauser_,
    uint256 depositCap_
  ) StabilityMOM(
    address(this),  // logic contract is this contract itself
    registry_,      // MOM registry
    asset_,         // asset token
    pauser_,        // pauser address
    depositCap_     // deposit cap
  ) {
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
    _payKeeper(equityBefore, equityAfter);
    emit Swap(routes[0].from, routes[routes.length-1].to, amountIn, amountOutMin);
    return true;
  }

  function _enforceRoute(IRouter.Route[] memory routes) internal view {
    for (uint256 i = 0; i < routes.length; i++) {
      if (routes[i].factory != factory) revert InvalidRoute();
      if (allowedAssets[routes[i].from] == false || allowedAssets[routes[i].to] == false) revert AssetNotAllowed();
    }
  }

  function _payKeeper(uint256 equityBefore, uint256 equityAfter) internal {
    uint256 equityChange = equityAfter - equityBefore;
    uint256 keeperFee = equityChange / 10;
    if (equityChange > 0) {
      _coin.transfer(msg.sender, keeperFee);
      emit KeeperPayment(msg.sender, keeperFee);
    }
  }
}
