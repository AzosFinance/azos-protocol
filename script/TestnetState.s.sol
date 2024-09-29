// // SPDX-License-Identifier: UNLICENSED
// pragma solidity 0.8.19;

// import {Contracts} from '@script/Contracts.s.sol';

// import 'forge-std/Script.sol';
// import '@src/BasicActionsMock.sol';
// import {HaiProxy} from '@contracts/proxies/HaiProxy.sol';
// import {HaiProxyRegistry} from '@contracts/proxies/HaiProxyRegistry.sol';
// import {BasicActionsMock} from '@src/BasicActionsMock.sol';
// import {MintableERC20} from '@contracts/for-test/MintableERC20.sol';
// import {SystemCoin} from '@contracts/tokens/SystemCoin.sol';
// import {SAFEEngine} from '@contracts/SAFEEngine.sol';

// contract TestnetState is Script {
//   SAFEEngine public SAFEENGINE;
//   MintableERC20 public BCT;
//   MintableERC20 public FGB;
//   MintableERC20 public REI;
//   HaiProxyRegistry public REGISTRY;
//   SystemCoin public COIN;
//   BasicActionsMock public BASICACTIONSMOCK;
//   address public MANAGER;
//   address public BCTJOIN;
//   address public FGBJOIN;
//   address public REIJOIN;
//   address public COINJOIN;
//   address public TAXCOLLECTOR;

//   uint256 constant SEPOLIA_BCT_ETH_PRICE_FEED = 0.0432e18; // 1 BCT = 0.0432 ETH = $77.76
//   uint256 constant SEPOLIA_FGB_ETH_PRICE_FEED = 0.0054e17; // 1 FGB = 0.0054 ETH = $9.72
//   uint256 constant SEPOLIA_REI_ETH_PRICE_FEED = 0.0189e17; // 1 REI = 0.0189 ETH = $34.02
//   uint256 constant BCT_PRICE = 77; // 1 BCT = $77.76
//   uint256 constant FGB_PRICE = 9; // 1 FGB = $9.72
//   uint256 constant REI_PRICE = 34; // 1 REI = $34.02
//   uint256 constant ETH_PRICE = 1800e18; // 1 ETH = 1800 USD

//   string RPC_URL;
//   address deployer;
//   string public mnemonic;
//   address[] public publicKeys;
//   uint256[] public privateKeys;
//   HaiProxy[] public proxies;

//   bytes32 public bct = bytes32('BCT');
//   bytes32 public fgb = bytes32('FGB');
//   bytes32 public rei = bytes32('REI');

//   function deployProxy(address owner) public returns (address proxy) {
//     proxy = REGISTRY.build(owner);
//   }

//   function mintTokens(address user, uint256 amount, address token) public {
//     MintableERC20(token).mint(user, amount);
//   }

//   function mintAllTokens() public {
//     for (uint256 i; i < publicKeys.length; i++) {
//       uint256 userAmount = 10_000 * 1 ether * (i + 1);
//       mintTokens(publicKeys[i], userAmount, address(BCT));
//       mintTokens(publicKeys[i], userAmount, address(FGB));
//       mintTokens(publicKeys[i], userAmount, address(REI));
//     }
//   }

//   function setApprovals() public {
//     for (uint256 i; i < publicKeys.length; i++) {
//       vm.stopBroadcast();
//       vm.startBroadcast(publicKeys[i]);
//       BCT.approve(address(proxies[i]), type(uint256).max);
//       FGB.approve(address(proxies[i]), type(uint256).max);
//       REI.approve(address(proxies[i]), type(uint256).max);
//     }
//   }

//   // note that the SafeIds from the GebSafeManager will correspond to the indices of the publicKeys array
//   function openSafe(
//     address owner,
//     HaiProxy proxy,
//     uint256 collateralAmount,
//     uint256 deltaWad,
//     address collateralJoin,
//     bytes32 collateralType
//   ) public {
//     vm.stopBroadcast();
//     vm.startBroadcast(owner);
//     bytes memory data = abi.encodeWithSelector(
//       BASICACTIONSMOCK.openLockTokenCollateralAndGenerateDebt.selector,
//       MANAGER,
//       TAXCOLLECTOR,
//       collateralJoin,
//       COINJOIN,
//       collateralType,
//       collateralAmount,
//       deltaWad
//     );
//     proxy.execute(address(BASICACTIONSMOCK), data);
//   }

//   function openAllSafes() public {
//     for (uint32 i = 0; i < publicKeys.length; i++) {
//       uint256 userAmount = 10_000 * 1 ether * (i + 1);
//       uint256 dollarAmountBct = userAmount * BCT_PRICE;
//       uint256 dollarAmountFgb = userAmount * FGB_PRICE;
//       uint256 dollarAmountRei = userAmount * REI_PRICE;
//       uint256 bctDelta = dollarAmountBct / 10;
//       uint256 fgbDelta = dollarAmountFgb / 10;
//       uint256 reiDelta = dollarAmountRei / 10;
//       openSafe(publicKeys[i], proxies[i], userAmount, userAmount, BCTJOIN, bct);
//       openSafe(publicKeys[i], proxies[i], userAmount, userAmount / 2, FGBJOIN, fgb);
//       openSafe(publicKeys[i], proxies[i], userAmount, userAmount, REIJOIN, rei);
//     }
//   }

//   function deriveKeys() public {
//     for (uint32 i = 0; i < 10; i++) {
//       (address publicKey, uint256 privateKey) = deriveRememberKey(mnemonic, i);
//       publicKeys.push(publicKey);
//       privateKeys.push(privateKey);
//     }
//   }

//   function deployProxies() public {
//     for (uint32 i = 0; i < publicKeys.length; i++) {
//       address userProxyAddress = deployProxy(publicKeys[i]);
//       HaiProxy userProxy = HaiProxy(payable(userProxyAddress));
//       proxies.push(userProxy);
//     }
//   }

//   function setUp() public {
//     SAFEENGINE = SAFEEngine(vm.envAddress('SAFE_ENGINE'));
//     BCT = MintableERC20(vm.envAddress('BCT'));
//     FGB = MintableERC20(vm.envAddress('FGB'));
//     REI = MintableERC20(vm.envAddress('REI'));
//     REGISTRY = HaiProxyRegistry(vm.envAddress('HAI_PROXY_REGISTRY'));
//     COIN = SystemCoin(vm.envAddress('SYSTEM_COIN'));
//     BASICACTIONSMOCK = BasicActionsMock(vm.envAddress('BASIC_ACTIONS_MOCK'));
//     MANAGER = vm.envAddress('HAI_SAFE_MANAGER');
//     BCTJOIN = vm.envAddress('BCT_JOIN');
//     FGBJOIN = vm.envAddress('FGB_JOIN');
//     REIJOIN = vm.envAddress('REI_JOIN');
//     COINJOIN = vm.envAddress('COIN_JOIN');
//     TAXCOLLECTOR = vm.envAddress('TAX_COLLECTOR');
//   }

//   function run() public {
//     RPC_URL = vm.envString('SEPOLIA_RPC');
//     mnemonic = vm.envString('MNEMONIC');
//     uint256 privKey = uint256(vm.envBytes32('SEPOLIA_DEPLOYER_PK'));
//     deployer = vm.rememberKey(privKey);
//     deriveKeys();
//     vm.startBroadcast(deployer);

//     deployProxies();
//     mintAllTokens();
//     setApprovals();
//     openAllSafes();
//   }

  // forge script script/TestnetState.s.sol:TestnetState -f sepolia --broadcast -vvvvv
// }