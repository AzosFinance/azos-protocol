// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {AzosSafeManager, EnumerableSet} from '@contracts/proxies/AzosSafeManager.sol';

contract AzosSafeManagerForTest is AzosSafeManager {
  using EnumerableSet for EnumerableSet.UintSet;

  constructor(address _safeEngine) AzosSafeManager(_safeEngine) {}

  function setSAFE(uint256 _safe, SAFEData memory __safeData) external {
    _safeData[_safe] = SAFEData({
      owner: __safeData.owner,
      pendingOwner: __safeData.pendingOwner,
      safeHandler: __safeData.safeHandler,
      collateralType: __safeData.collateralType
    });
    _usrSafes[__safeData.owner].add(_safe);
    _usrSafesPerCollat[__safeData.owner][__safeData.collateralType].add(_safe);
  }
}
