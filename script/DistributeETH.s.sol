pragma solidity 0.8.19;

import "forge-std/Script.sol";
import { Distributor } from "src/Distributor.sol";

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
        uint256 privKey = uint256(vm.envBytes32("SEPOLIA_DEPLOYER_PK"));
        address deployer = vm.rememberKey(privKey);
        vm.startBroadcast(deployer);
        uint256 _amount = 1 ether;

        uint256 id;
        assembly {
            id := chainid()
        }
        chainId = id;

        mnemonic = vm.envString("MNEMONIC");
        deriveKeys();

        distributor = new Distributor();
        console2.logUint(deployer.balance);
        ( uint256 amount, ) = distributor.distribute{value: _amount}(publicKeys);

        console2.log("Distributed: ");
        console2.logUint(amount);

        // forge script script/DistributeETH.s.sol:DistributeETH -f sepolia --broadcast --verify -vvvvv

    }
}