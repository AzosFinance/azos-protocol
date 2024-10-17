// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockERC20 is ERC20 {
	uint8 private _decimals;
	
	constructor(string memory name, string memory symbol, uint8 decimals_) ERC20(name, symbol) {
		_decimals = decimals_;
	}
	
	function decimals() public view virtual override returns (uint8) {
		return _decimals;
	}
	
	function mint(address to, uint256 amount) public {
		_mint(to, amount);
	}
	
	// Optional: Add a burn function if needed for your tests
	function burn(address from, uint256 amount) public {
		_burn(from, amount);
	}
}
