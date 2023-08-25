// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {HaiSafeManager} from '@contracts/proxies/HaiSafeManager.sol';
import {CommonActions} from '@contracts/proxies/actions/CommonActions.sol';

import {IGlobalSettlement} from '@interfaces/settlement/IGlobalSettlement.sol';
import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {ICollateralJoin} from '@interfaces/utils/ICollateralJoin.sol';

import {RAY} from '@libraries/Math.sol';

/**
 * @title  GlobalSettlementActions
 * @notice All methods here are executed as delegatecalls from the user's proxy
 */
contract GlobalSettlementActions is CommonActions {
  // --- Methods ---

  /**
   * @notice Free remaining collateral from a SAFE after being processed by the global settlement
   * @param  _manager Address of the HaiSafeManager contract
   * @param  _globalSettlement Address of the GlobalSettlement contract
   * @param  _collateralJoin Address of the CollateralJoin contract
   * @param  _safeId Id of the SAFE to free collateral from
   * @return _collateralAmount Amount of collateral freed [wad]
   */
  function freeCollateral(
    address _manager,
    address _globalSettlement,
    address _collateralJoin,
    uint256 _safeId
  ) external delegateCall returns (uint256 _collateralAmount) {
    IGlobalSettlement __globalSettlement = IGlobalSettlement(_globalSettlement);
    HaiSafeManager __manager = HaiSafeManager(_manager);
    HaiSafeManager.SAFEData memory _safeData = __manager.safeData(_safeId);
    ISAFEEngine _safeEngine = ISAFEEngine(__manager.safeEngine());
    ISAFEEngine.SAFE memory _safe = _safeEngine.safes(_safeData.collateralType, _safeData.safeHandler);

    // check for debt and process safe if needed
    if (_safe.generatedDebt > 0) {
      __globalSettlement.processSAFE(_safeData.collateralType, _safeData.safeHandler);
      _safe = _safeEngine.safes(_safeData.collateralType, _safeData.safeHandler);
    }

    // quit system to proxy address
    if (!_safeEngine.canModifySAFE(address(this), _manager)) {
      _safeEngine.approveSAFEModification(_manager);
    }

    __manager.quitSystem(_safeId, address(this));

    // free collateral
    __globalSettlement.freeCollateral(_safeData.collateralType);

    // exit coins to user
    _collateralAmount = _safeEngine.tokenCollateral(_safeData.collateralType, address(this));
    _exitCollateral(_collateralJoin, _collateralAmount);
  }

  /**
   * @notice Prepare coins for redeeming
   * @param  _globalSettlement Address of the GlobalSettlement contract
   * @param  _coinJoin Address of the CoinJoin contract
   * @param  _coinAmount Amount of coins to prepare for redeeming [wad]
   */
  function prepareCoinsForRedeeming(
    address _globalSettlement,
    address _coinJoin,
    uint256 _coinAmount
  ) external delegateCall {
    IGlobalSettlement __globalSettlement = IGlobalSettlement(_globalSettlement);
    ISAFEEngine __safeEngine = __globalSettlement.safeEngine();

    uint256 _internalCoins = __safeEngine.coinBalance(address(this)) / RAY;
    uint256 _coinsToJoin = _internalCoins >= _coinAmount ? 0 : _coinAmount - _internalCoins;
    _joinSystemCoins(_coinJoin, address(this), _coinsToJoin);

    if (!__safeEngine.canModifySAFE(address(this), _globalSettlement)) {
      __safeEngine.approveSAFEModification(_globalSettlement);
    }

    IGlobalSettlement(_globalSettlement).prepareCoinsForRedeeming(_coinAmount);
  }

  /**
   * @notice Redeem collateral tokens from the global settlement
   * @param  _globalSettlement Address of the GlobalSettlement contract
   * @param  _collateralJoin Address of the CollateralJoin contract
   * @return _collateralAmount Amount of collateral redeemed [wad]
   */
  function redeemCollateral(
    address _globalSettlement,
    address _collateralJoin
  ) external delegateCall returns (uint256 _collateralAmount) {
    IGlobalSettlement __globalSettlement = IGlobalSettlement(_globalSettlement);
    ISAFEEngine __safeEngine = __globalSettlement.safeEngine();

    bytes32 _cType = ICollateralJoin(_collateralJoin).collateralType();
    uint256 _coinAmount =
      __globalSettlement.coinBag(address(this)) - __globalSettlement.coinsUsedToRedeem(_cType, address(this));

    __globalSettlement.redeemCollateral(_cType, _coinAmount);

    _collateralAmount = __safeEngine.tokenCollateral(_cType, address(this));
    _exitCollateral(_collateralJoin, _collateralAmount);
  }
}
