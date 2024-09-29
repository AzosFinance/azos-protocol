pragma solidity ^0.8.20;

import {Script} from 'forge-std/Script.sol';
import {Distributor} from './Distributor.sol';

contract DistributeETH is Script {
  string public mnemonic;
  address[] public publicKeys;
  uint256[] public privateKeys;
  Distributor public distributor;

  uint256 public chainId;

  function deriveKeys() public {
    for (uint32 _i = 0; _i < 10; _i++) {
      (address _publicKey, uint256 _privateKey) = deriveRememberKey(mnemonic, _i);
      publicKeys.push(_publicKey);
      privateKeys.push(_privateKey);
    }
  }

  function run() public {
    vm.startBroadcast();
    uint256 _amount = 0.5 ether;

    uint256 _id;
    assembly {
      _id := chainid()
    }
    chainId = _id;

    mnemonic = vm.envString('MNEMONIC');
    deriveKeys();

    distributor = new Distributor();

    (_amount,) = distributor.distribute{value: _amount}(publicKeys);

    // source .env && forge script DistributeETH -vvvvv --rpc-url $OP_SEPOLIA_RPC --broadcast --private-key $OP_SEPOLIA_DEPLOYER_PK --verify --etherscan-api-key $OP_ETHERSCAN_API_KEY
  }
}
