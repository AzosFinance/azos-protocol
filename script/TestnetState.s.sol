// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Contracts} from '@script/Contracts.s.sol';

import "forge-std/Script.sol";
import '@src/BasicActionsMock.sol';
import {HaiProxy} from '@contracts/proxies/HaiProxy.sol';
import {HaiProxyRegistry} from '@contracts/proxies/HaiProxyRegistry.sol';
import {BasicActionsMock} from '@src/BasicActionsMock.sol';
import {MintableERC20} from '@contracts/for-test/MintableERC20.sol';
import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';
import {SAFEEngine} from '@contracts/SAFEEngine.sol';

contract TestnetState is Script {

    SAFEEngine constant SAFEENGINE = SAFEEngine(0xC6B768B49a3Fb6A054A5d15bFD2Bb61EAbe694A8);
    MintableERC20 constant BCT = MintableERC20(0x1D1FaAe1e739d772566F8Fb17A824c10A4868aA0);
    MintableERC20 constant FGB = MintableERC20(0xE6F85fbedA18eB49072e3b4bb1aAAeFCc8255397);
    MintableERC20 constant REI = MintableERC20(0x0879bE43D76D2cB4ADED433A177a6a78BFe8e85c);
    HaiProxyRegistry constant REGISTRY = HaiProxyRegistry(0xf98CaD9B57168a9Ec8ed352dc2b96125faB2a1d1);
    SystemCoin constant COIN = SystemCoin(0xBe6AE5f9A4A326d3D4F613d2159b5c6CE78F7339);
    BasicActionsMock constant BASICACTIONSMOCK = BasicActionsMock(0xfd47f17587778127e0A29376B8cCAe8E810972F5);
    address constant MANAGER = 0x7c73f24511d8eC2AAE325EB85DeA5c274Ea9cC17;
    address constant BCTJOIN = 0xd16bAC78e799f157167C1e0e7240a0298E73749C;
    address constant FGBJOIN = 0xc12176c95c998cC367BCe24d54E2833f5f4487C0;
    address constant REIJOIN = 0x10c16F46240391EF7A548630d6Ce303D41ae9B59;
    address constant COINJOIN = 0x261fbA9deEAD5364D88442492c27776e7F361cbE;
    address constant TAXCOLLECTOR = 0x7306F4776E2B989B58D4662102Cb87b901a96660;

    uint256 constant SEPOLIA_BCT_ETH_PRICE_FEED = 0.0432e18; // 1 BCT = 0.0432 ETH = $77.76
    uint256 constant SEPOLIA_FGB_ETH_PRICE_FEED = 0.0054e17; // 1 FGB = 0.0054 ETH = $9.72
    uint256 constant SEPOLIA_REI_ETH_PRICE_FEED = 0.0189e17; // 1 REI = 0.0189 ETH = $34.02
    uint256 constant BCT_PRICE = 77; // 1 BCT = $77.76
    uint256 constant FGB_PRICE = 9; // 1 FGB = $9.72
    uint256 constant REI_PRICE = 34; // 1 REI = $34.02
    uint256 constant ETH_PRICE = 1800e18; // 1 ETH = 1800 USD

    string RPC_URL;
    address deployer;
    string public mnemonic;
    address[] public publicKeys;
    uint256[] public privateKeys;
    HaiProxy[] public proxies;

    bytes32 public bct = bytes32('BCT');
    bytes32 public fgb = bytes32('FGB');
    bytes32 public rei = bytes32('REI');

    function deployProxy(address owner) public returns (address proxy) {
        proxy = REGISTRY.build(owner);
    }

    function mintTokens(address user, uint256 amount, address token) public {
        MintableERC20(token).mint(user, amount);
    }

    function mintAllTokens() public {
        for (uint256 i; i < publicKeys.length; i++) {
            uint256 userAmount = 10000 * 1 ether * (i + 1);
            mintTokens(publicKeys[i], userAmount, address(BCT));
            mintTokens(publicKeys[i], userAmount, address(FGB));
            mintTokens(publicKeys[i], userAmount, address(REI));
        }
    }

    function setApprovals() public {
        for (uint256 i; i < publicKeys.length; i++) {
            vm.stopBroadcast();
            vm.startBroadcast(publicKeys[i]);
            BCT.approve(address(proxies[i]), type(uint256).max);
            FGB.approve(address(proxies[i]), type(uint256).max);
            REI.approve(address(proxies[i]), type(uint256).max);
        }
    }

    // note that the SafeIds from the GebSafeManager will correspond to the indices of the publicKeys array
    function openSafe(address owner, HaiProxy proxy, uint256 collateralAmount, uint256 deltaWad, address collateralJoin, bytes32 collateralType) public {
        vm.stopBroadcast();
        vm.startBroadcast(owner);
        bytes memory data = abi.encodeWithSelector(
            BASICACTIONSMOCK.openLockTokenCollateralAndGenerateDebt.selector,
            MANAGER,
            TAXCOLLECTOR,
            collateralJoin,
            COINJOIN,
            collateralType,
            collateralAmount,
            deltaWad
        );
        proxy.execute(address(BASICACTIONSMOCK), data);
    }

    function openAllSafes() public {
        for (uint32 i = 0; i < publicKeys.length; i++) {
            uint256 userAmount = 10000 * 1 ether * (i + 1);
            uint256 dollarAmountBct = userAmount * BCT_PRICE;
            uint256 dollarAmountFgb = userAmount * FGB_PRICE;
            uint256 dollarAmountRei = userAmount * REI_PRICE;
            uint256 bctDelta = dollarAmountBct / 10;
            uint256 fgbDelta = dollarAmountFgb / 10;
            uint256 reiDelta = dollarAmountRei / 10;
            openSafe(publicKeys[i], proxies[i], userAmount, userAmount, BCTJOIN, bct);
            openSafe(publicKeys[i], proxies[i], userAmount, userAmount / 2, FGBJOIN, fgb);
            openSafe(publicKeys[i], proxies[i], userAmount, userAmount, REIJOIN, rei);
        }
    }

    function deriveKeys() public {
        for (uint32 i = 0; i < 10; i++) {
            (address publicKey, uint256 privateKey) = deriveRememberKey(mnemonic, i);
            publicKeys.push(publicKey);
            privateKeys.push(privateKey);
        }
    }

    function deployProxies() public {
        for (uint32 i = 0; i < publicKeys.length; i++) {
            address userProxyAddress = deployProxy(publicKeys[i]);
            HaiProxy userProxy = HaiProxy(payable(userProxyAddress));
            proxies.push(userProxy);
        }
    }

    function run() public {
        RPC_URL = vm.envString("SEPOLIA_RPC");
        mnemonic = vm.envString("MNEMONIC");
        uint256 privKey = uint256(vm.envBytes32("SEPOLIA_DEPLOYER_PK"));
        deployer = vm.rememberKey(privKey);
        deriveKeys();
        vm.startBroadcast(deployer);

        deployProxies();
        mintAllTokens();
        setApprovals();
        openAllSafes();

    }

    // forge script script/TestnetState.s.sol:TestnetState -f sepolia --broadcast -vvvvv

}