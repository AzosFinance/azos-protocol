// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {TaxCollector, ITaxCollector, EnumerableSet} from '@contracts/TaxCollector.sol';

contract TaxCollectorForTest is TaxCollector {
  constructor(address _safeEngine) TaxCollector(_safeEngine) {}

  function splitTaxIncome(bytes32 _cType, uint256 _debtAmount, int256 _deltaRate) external {
    _splitTaxIncome(_cType, _debtAmount, _deltaRate);
  }

  function distributeTax(bytes32 _cType, address _receiver, uint256 _debtAmount, int256 _deltaRate) external {
    _distributeTax(_cType, _receiver, _debtAmount, _deltaRate);
  }

  function addSecondaryTaxReceiver(
    bytes32 _cType,
    address _receiver,
    bool _canTakeBackTax,
    uint128 _taxPercentage
  ) external {
    _secondaryTaxReceivers[_cType][_receiver] = ITaxCollector.TaxReceiver(_receiver, _canTakeBackTax, _taxPercentage);
  }

  function addToCollateralList(bytes32 _cType) external {
    _collateralList.add(_cType);
  }

  function addSecondaryReceiver(address _receiver) external {
    _secondaryReceivers.add(_receiver);
  }

  // --- Legacy test methods ---
  using EnumerableSet for EnumerableSet.AddressSet;
  using EnumerableSet for EnumerableSet.Bytes32Set;

  function secondaryReceiversAmount() external view returns (uint256) {
    return _secondaryReceivers.length();
  }

  function secondaryReceiverRevenueSources(address _receiver) external view returns (uint256) {
    return _secondaryReceiverRevenueSources[_receiver].length();
  }
}
