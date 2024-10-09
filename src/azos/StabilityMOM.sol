pragma solidity ^0.8.20;

import {MOM, IMOMRegistry, IERC20} from '@azos/MOM.sol';
import {IStabilityMOM} from '@azosinterfaces/IStabilityMOM.sol';
contract StabilityMOM is MOM, IStabilityMOM {

  mapping(address allowedAsset => bool isAllowed) public allowedAssets;

  constructor(address logicContract, IMOMRegistry registry, IERC20 token) MOM(registry, token) {
    _actions[_actionsCounter] = logicContract;
    allowedAssets[address(token)] = true;
    allowedAssets[address(_systemCoin)] = true;
    emit ActionRegistered(logicContract, _actionsCounter);
    _actionsCounter++;
  }

  function delegateAction(uint256 actionId, bytes calldata data) external returns (bool) {
    address actionContract = _actions[actionId];
    if (actionContract == address(0)) revert InvalidAction();
    if (actionContract.code.length == 0) revert NoCode();
    if (!_isActionRegistered[actionId]) revert ActionNotRegistered();
    (bool success, bytes memory result) = actionContract.delegatecall(abi.encodeWithSignature("action(bytes)", data));
    if (!success) revert ActionFailed();
    emit Action(success, result, actionContract);
    return success;
  }

  function updateAllowedAssets(address[] calldata assets, bool[] calldata statuses) external isAuthorized {
    if (assets.length != statuses.length) revert ArraysMustHaveSameLength();
    
    for (uint256 i = 0; i < assets.length; i++) {
      allowedAssets[assets[i]] = statuses[i];
      emit AllowedAssetsUpdated(assets[i], statuses[i]);
    }
  }

}
