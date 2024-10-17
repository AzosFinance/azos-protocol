// SPDX-License-Identifier: UNLICENSED

/*
      /\
     /  \    _______  ___
    / /\ \  |_  / _ \/ __|
   / ____ \  / / (_) \__ \
  /_/    \_\/___\___/|___/
*/

// #todo consider how we would extend stability mom for Cowswap and signature based DEXs
pragma solidity ^0.8.20;

import {MOM, IMOMRegistry, IERC20Metadata} from '@azos/MOM.sol';
import {IStabilityMOM} from '@azosinterfaces/IStabilityMOM.sol';

contract StabilityMOM is MOM, IStabilityMOM {
  mapping(address allowedAsset => bool isAllowed) public allowedAssets;
  uint256 internal _depositCap;
  uint256 internal _deposited;
  /// #todo enable stablecoins with greater decimals than 18
  uint256 internal _stablecoinDecimalsAdjustment;

  constructor(
    address logicContract,
    IMOMRegistry registry,
    IERC20Metadata asset,
    address pauser,
    uint256 depositCap
  ) MOM(registry, asset, pauser) {
    _actions[_actionsCounter] = logicContract;
    _isActionRegistered[_actionsCounter] = true;
    allowedAssets[address(asset)] = true;
    allowedAssets[address(_coin)] = true;
    emit ActionRegistered(logicContract, _actionsCounter);
    _stablecoinDecimalsAdjustment = 10 ** asset.decimals();
    _actionsCounter++;
    _depositCap = depositCap;
    emit DepositCap(depositCap);
  }

  // #todo think about how we can extend the single swap fuctionality of the existing actions contracts
  // #todo perhaps we can have a delegateAction hook; so that we can checkpoint equity after a series of actions
  // @inheritdoc IMOM
  function delegateAction(
    uint256[] calldata actionIds,
    bytes[] calldata datas
  ) external whenNotPaused returns (bool[] memory) {
    if (actionIds.length != datas.length) revert ArraysMustHaveSameLength();

    bool[] memory successes = new bool[](actionIds.length);

    for (uint256 i = 0; i < actionIds.length; i++) {
      address actionContract = _actions[actionIds[i]];
      if (actionContract == address(0)) revert InvalidAction();
      if (actionContract.code.length == 0) revert NoCode();
      if (!_isActionRegistered[actionIds[i]]) revert ActionNotRegistered();

      (bool success, bytes memory result) =
        actionContract.delegatecall(abi.encodeWithSignature('action(bytes)', datas[i]));
      if (!success) revert ActionFailed();

      emit Action(success, result, actionContract);
      successes[i] = success;
    }

    return successes;
  }

  function checkpointEquity() public view returns (uint256 equity) {
    return _checkpointEquity();
  }

  // #todo write correct implementations for minting coins
  function testingCoinMint(uint256 amount) external {
    _mintCoins(amount);
  }

  function receiveLiquidity(uint256 amount) external {
    if (amount + _deposited > _depositCap) revert DepositCapReached();
    _deposited += amount;
    uint256 balanceBefore = _asset.balanceOf(address(this));
    _asset.transferFrom(msg.sender, address(this), amount);
    uint256 balanceAfter = _asset.balanceOf(address(this));
    if (balanceAfter - balanceBefore != amount) revert InvalidAmount();
    _mintCoins(_scaleStablecoin(amount));
    _coin.transfer(msg.sender, _scaleStablecoin(amount));
    emit LiquidityReceived(msg.sender, amount);
  }

  function raiseDepositCap(uint256 amount) external isAuthorized {
    if (amount < _depositCap) revert DepositCapMustBeRaised();
    _depositCap += amount;
    emit DepositCap(amount);
  }
  
  function getDepositCap() public view returns (uint256) {
    return _depositCap;
  }
  
  function getDeposited() public view returns (uint256) {
    return _deposited;
  }
  
  function _checkpointEquity() internal view override returns (uint256 equity) {
    uint256 coinDebt = _getCoinDebt();
    uint256 coinBalance = _getCoinBalance();
    uint256 stablecoinBalance = _asset.balanceOf(address(this));
    uint256 adjustedStablecoinBalance = _scaleStablecoin(stablecoinBalance);
    equity = coinBalance + adjustedStablecoinBalance - coinDebt;
  }

  function _enforceEquity(uint256 equityBefore, uint256 equityAfter) internal pure returns (bool) {
    if (equityBefore < equityAfter) revert InvalidEquity();
    return true;
  }

  // #todo make scaling work with decimals above 18
  function _scaleStablecoin(uint256 amount) internal view returns (uint256) {
    return amount * 10e18 / _stablecoinDecimalsAdjustment;
  }

  // @inheritdoc IMOM
  function updateAllowedAssets(address[] calldata assets, bool[] calldata statuses) external isAuthorized {
    if (assets.length != statuses.length) revert ArraysMustHaveSameLength();

    for (uint256 i = 0; i < assets.length; i++) {
      allowedAssets[assets[i]] = statuses[i];
      emit AllowedAssetsUpdated(assets[i], statuses[i]);
    }
  }
}
