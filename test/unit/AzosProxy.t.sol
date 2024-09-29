// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {AzosProxy, IAzosProxy} from '@contracts/proxies/AzosProxy.sol';
import {IAuthorizable} from '@interfaces/utils/IAuthorizable.sol';
import {Address} from '@openzeppelin/contracts/utils/Address.sol';
import {AzosTest, stdStorage, StdStorage} from '@test/utils/AzosTest.t.sol';

abstract contract Base is AzosTest {
  using stdStorage for StdStorage;

  address deployer = label('deployer');
  address owner = label('owner');

  AzosProxy proxy;

  function setUp() public virtual {
    vm.startPrank(deployer);

    proxy = new AzosProxy(owner);

    vm.stopPrank();
  }
}

contract Unit_AzosProxy_Execute is Base {
  address target = label('target');

  modifier happyPath() {
    vm.startPrank(owner);
    _;
  }

  function test_Execute() public happyPath mockAsContract(target) {
    proxy.execute(target, bytes(''));
  }

  function test_Revert_TargetNoCode() public happyPath {
    vm.expectRevert(abi.encodeWithSelector(Address.AddressEmptyCode.selector, target));

    proxy.execute(target, bytes(''));

    // Sanity check
    assert(target.code.length == 0);
  }

  function test_Revert_TargetAddressZero() public happyPath {
    vm.expectRevert(IAzosProxy.TargetAddressRequired.selector);

    proxy.execute(address(0), bytes(''));
  }
}
