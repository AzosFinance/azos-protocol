pragma solidity ^0.8.20;

import {MOM, IMOMRegistry, IERC20} from '@azos/MOM.sol';
import {IStabilityMOM} from '@azosinterfaces/IStabilityMOM.sol';

contract StabilityMOM is MOM, IStabilityMOM {
  mapping(address allowedAsset => bool isAllowed) public allowedAssets;

  constructor(address logicContract, IMOMRegistry registry, IERC20 token, address pauser) MOM(registry, token, pauser) {
    _actions[_actionsCounter] = logicContract;
    allowedAssets[address(token)] = true;
    allowedAssets[address(_systemCoin)] = true;
    emit ActionRegistered(logicContract, _actionsCounter);
    _actionsCounter++;
  }

  // @inheritdoc IMOM
  function delegateAction(uint256[] calldata actionIds, bytes[] calldata datas) external returns (bool[] memory) {
    if (actionIds.length != datas.length) revert ArraysMustHaveSameLength();
    
    bool[] memory successes = new bool[](actionIds.length);
    
    for (uint256 i = 0; i < actionIds.length; i++) {
      address actionContract = _actions[actionIds[i]];
      if (actionContract == address(0)) revert InvalidAction();
      if (actionContract.code.length == 0) revert NoCode();
      if (!_isActionRegistered[actionIds[i]]) revert ActionNotRegistered();
      
      (bool success, bytes memory result) = actionContract.delegatecall(abi.encodeWithSignature('action(bytes)', datas[i]));
      if (!success) revert ActionFailed();
      
      emit Action(success, result, actionContract);
      successes[i] = success;
    }
    
    return successes;
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
