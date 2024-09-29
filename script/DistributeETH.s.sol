pragma solidity ^0.8.19;

import 'forge-std/Script.sol';
import {Distributor} from './Distributor.sol';

contract DistributeETH is Script {
  string public mnemonic;
  address[] public publicKeys;
  uint256[] public privateKeys;
  Distributor public distributor;

  uint256 public chainId;

  function deriveKeys() public {
    for (uint32 i = 0; i < 10; i++) {
      (address publicKey, uint256 privateKey) = deriveRememberKey(mnemonic, i);
      publicKeys.push(publicKey);
      privateKeys.push(privateKey);
    }
  }

  function run() public {
    vm.startBroadcast();
    uint256 _amount = 0.5 ether;

    uint256 id;
    assembly {
      id := chainid()
    }
    chainId = id;

    mnemonic = vm.envString('MNEMONIC');
    deriveKeys();

    distributor = new Distributor();

    (uint256 amount,) = distributor.distribute{value: _amount}(publicKeys);

    console2.log('Distributed: ');
    console2.logUint(amount);

    // source .env && forge script DistributeETH -vvvvv --rpc-url $OP_SEPOLIA_RPC --broadcast --private-key $OP_SEPOLIA_DEPLOYER_PK --verify --etherscan-api-key $OP_ETHERSCAN_API_KEY
  }
}