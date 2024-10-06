pragma solidity ^0.8.20;

import {MOM, IMOMRegistry, IERC20} from '@azos/MOM.sol';

contract StabilityMOM is MOM {
  constructor(address logicContract, IMOMRegistry registry, IERC20 token) MOM(registry, token) {
    _actions[1] = logicContract;
    _actionsCounter = 2;
  }
}
