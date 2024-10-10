pragma solidity ^0.8.20;

import {StabilityMOM, IMOMRegistry, IERC20} from '@azos/StabilityMOM.sol';
import {IRouter} from '@azos/interfaces/Aerodrome/IRouter.sol';

contract StabilitySwapAero is StabilityMOM {
  IRouter private immutable _router;

  constructor(
    address logicContract,
    IMOMRegistry registry,
    IERC20 token,
    IRouter router,
    address pauser
  ) StabilityMOM(logicContract, registry, token, pauser) {
    _router = router;
  }

  function action(bytes calldata data) external returns (bool) {
    (uint256 amountIn, uint256 amountOutMin, IRouter.Route[] memory routes, uint256 deadline) =
      abi.decode(data, (uint256, uint256, IRouter.Route[], uint256));
    _router.swapExactTokensForTokens(amountIn, amountOutMin, routes, address(this), deadline);
    return true;
  }
}
