// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

contract MockAction {
	bool public actionCalled;
	
	function action(bytes memory) external returns (bool) {
		actionCalled = true;
		return true;
	}
}
