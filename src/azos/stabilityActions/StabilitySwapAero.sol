pragma solidity ^0.8.20;

import {StabilityMOM, IMOMRegistry, IERC20} from '@azos/StabilityMOM.sol';
import {IRouter} from '@azos/interfaces/Aerodrome/IRouter.sol';

contract StabilitySwapAero is StabilityMOM {

  IRouter private immutable _router;

  constructor(address logicContract, IMOMRegistry registry, IERC20 token, IRouter router) StabilityMOM(logicContract, registry, token) {
    _router = router;
  }

  function action(bytes calldata data) external returns (bool) {}
    
}