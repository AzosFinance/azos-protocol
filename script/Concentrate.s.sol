pragma solidity 0.8.19;

import 'forge-std/Script.sol';

contract Concentrate is Script {

    string public mnemonic;
  address[] public publicKeys;
  uint256[] public privateKeys;
  address payable public deployer;

  uint256 public chainId;

  function deriveKeys() public {
    for (uint32 i = 0; i < 10; i++) {
      (address publicKey, uint256 privateKey) = deriveRememberKey(mnemonic, i);
      publicKeys.push(publicKey);
      privateKeys.push(privateKey);
    }
  }

    function setUp() public virtual {
      mnemonic = vm.envString('MNEMONIC');
      deriveKeys();
      uint256 privKey = uint256(vm.envBytes32('SEPOLIA_DEPLOYER_PK'));
      deployer = payable(vm.rememberKey(privKey));
    }

    function run() public {
        for (uint256 i; i < publicKeys.length; i++) {
          vm.startBroadcast(publicKeys[i]);
          deployer.transfer(0.09 ether);
          vm.stopBroadcast();
        }
    }
  // forge script script/Concentrate.s.sol:Concentrate -f sepolia --broadcast --verify -vvvvv
}