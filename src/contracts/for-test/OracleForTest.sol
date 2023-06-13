// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IBaseOracle} from '@interfaces/oracles/IBaseOracle.sol';

// solhint-disable
contract OracleForTest is IBaseOracle {
  uint256 price;
  bool validity = true;
  bool throwsError;
  string public symbol;

  constructor(uint256 _price) {
    price = _price;
  }

  function getResultWithValidity() external view returns (uint256 _price, bool _validity) {
    _checkThrowsError();
    _price = price;
    _validity = validity;
  }

  function setPriceAndValidity(uint256 _price, bool _validity) public virtual {
    price = _price;
    validity = _validity;
  }

  function priceSource() external view returns (address) {
    _checkThrowsError();
    return address(this);
  }

  function read() external view returns (uint256 _value) {
    return price;
  }

  function setThrowsError(bool _throwError) public virtual {
    throwsError = _throwError;
  }

  function _checkThrowsError() internal view {
    if (throwsError) {
      revert();
    }
  }
}
