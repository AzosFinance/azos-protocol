// SPDX-License-Identifier: MIT

/////////////////////////////////
//      /\                     //
//     /  \    _______  ___    //
//    / /\ \  |_  / _ \/ __|   //
//   / ____ \  / / (_) \__ \   //
//  /_/    \_\/___\___/|___/   //
/////////////////////////////////

pragma solidity 0.8.20;

import {Authorizable} from '@contracts/utils/Authorizable.sol';
import {IMOMRegistry} from '@azosinterfaces/IMOMRegistry.sol';
import {IERC20} from '@openzeppelin/contracts/token/ERC20/IERC20.sol';

contract MOM is Authorizable {
  IMOMRegistry private immutable _registry;

  constructor(IMOMRegistry registry) Authorizable(address(registry)) {
    _registry = registry;
  }
}
