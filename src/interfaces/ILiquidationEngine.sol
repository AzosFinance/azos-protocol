// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {IAuthorizable} from '@interfaces/IAuthorizable.sol';
import {IDisableable} from '@interfaces/IDisableable.sol';

interface ILiquidationEngine is IAuthorizable, IDisableable {
  function removeCoinsFromAuction(uint256 _rad) external;
  function collateralTypes(bytes32)
    external
    view
    returns (
      address _collateralAuctionHouse,
      uint256 /* wad */ _liquidationPenalty,
      uint256 /* rad */ _liquidationQuantity
    );

  function connectSAFESaviour(address _saviour) external;
  function disconnectSAFESaviour(address _saviour) external;
  function protectSAFE(bytes32 _collateralType, address _safe, address _saviour) external;
  function liquidateSAFE(bytes32 _collateralType, address _safe) external returns (uint256 _auctionId);
  function getLimitAdjustedDebtToCover(bytes32 _collateralType, address _safe) external view returns (uint256 _wad);
}