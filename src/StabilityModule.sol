// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {IERC20Metadata} from '@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol';

import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {Authorizable, IAuthorizable} from '@contracts/utils/Authorizable.sol';

contract StabilityModule is Authorizable {
  // Errors
  error FailedDelegateCall();
  error NoAdapter();
  error FailedDeploy();
  error InvalidTrade();
  error InvalidBalance();

  // Events

  // Event logs adding a new adapter by authorized address
  event AddAdapter(bytes32 indexed adapterName, address indexed adapter, address indexed authorized);
  // Event logs changing the treasury address by authorized address
  event ChangeTreasury(address indexed newTreasury, address indexed authorized);
  // Event logging the winding down of a module
  event WindDown(address indexed treasury, uint256 indexed amount, address indexed authorized);
  // Event logging change to max deposit
  event MaxDeposit(uint256 indexed maxDeposit);
  // Event logging deposit
  event Deposit(uint256 indexed amount);
  // Event logging burning of any extra coins
  event BurnBalance(uint256 indexed amount);
  // Event logging the expansion of supply and debt
  event Expand(uint256 indexed amount, address indexed target, bytes returnData);
  // Event logging change in debt and balance
  event DebtChange(
    int256 indexed previousDebt, int256 indexed newDebt, uint256 indexed previousBalance, uint256 newBalance
  );

  // State

  IERC20Metadata public authorizedCollateral;
  uint256 public scalingFactor;

  address treasury;
  ISystemCoin public systemCoin; // ZAI

  // Debt is scaled to the collateral decimals; IE the system coin debt will be scaled to the number of decimals in the
  // collateral token
  int256 private _debt;
  uint256 private _deposits;
  uint256 public maxDeposit;
  mapping(bytes32 adapterName => address adapterContract) private _adapters;

  constructor(
    address authorizedCollateral_,
    address adapter_,
    bytes32 adapterName_,
    address treasury_,
    address systemCoin_,
    address governance_,
    uint256 maxDeposit_
  ) Authorizable(governance_) {
    if (
      authorizedCollateral_ == address(0) || adapter_ == address(0) || systemCoin_ == address(0)
        || treasury_ == address(0) || governance_ == address(0) || systemCoin_ == address(0) || adapterName_ == bytes32(0)
    ) {
      revert FailedDeploy();
    }
    _adapters[adapterName_] = adapter_;
    authorizedCollateral = IERC20Metadata(authorizedCollateral_);
    systemCoin = ISystemCoin(systemCoin_);
    scalingFactor = systemCoin.decimals() - authorizedCollateral.decimals();
    treasury = treasury_;
    maxDeposit = maxDeposit_;
    emit MaxDeposit(maxDeposit_);
    emit AddAdapter(adapterName_, adapter_, msg.sender);
  }

  // Mutable functions

  // @notice Allows expanding system coin supply and executing delegate function calls on approved adapters
  // @param adapterName Name of the adapter
  // @param data Data to be passed to the adapter
  // @param mintAmount Amount of system coins to mint
  function expandAndBuy(bytes32 adapterName, bytes calldata data, uint256 mintAmount) public {
    address target = _adapters[adapterName];
    if (target == address(0)) {
      revert NoAdapter();
    }

    if (systemCoin.balanceOf(address(this)) > 0) {
      burnBalance();
    }

    int256 previousDebt = _debt;
    uint256 previousBalance = IERC20Metadata(authorizedCollateral).balanceOf(address(this));

    uint256 previousEquity = previousBalance - uint256(previousDebt);

    // We have to scale the system coin's debt to the decimal precision of the collateral token
    int256 newDebt = previousDebt + _scaleToDebt(mintAmount);
    systemCoin.mint(address(this), mintAmount);

    (bool success, bytes memory returnData) = target.delegatecall(data);
    if (!success) {
      revert FailedDelegateCall();
    }

    uint256 newBalance = IERC20Metadata(authorizedCollateral).balanceOf(address(this));
    uint256 newEquity = newBalance - uint256(newDebt);

    if (newEquity < previousEquity) {
      revert InvalidTrade();
    }

    _debt = newDebt;

    emit DebtChange(previousDebt, newDebt, previousBalance, newBalance);
    emit Expand(mintAmount, target, returnData);
  }

  // @notice Burns any system coins from the stability module; and reduces it's debt by that amount
  function burnBalance() public {
    if (systemCoin.balanceOf(address(this)) == 0) {
      revert InvalidBalance();
    }
    uint256 balance = systemCoin.balanceOf(address(this));
    systemCoin.burn(balance);
    _debt = _debt - _scaleToDebt(balance);
    emit BurnBalance(balance);
  }

  // Helper functions

  function _scaleToDebt(uint256 amount) internal view returns (int256) {
    if (scalingFactor == 0) {
      return int256(amount);
    }
    return int256(amount / (10 ** scalingFactor));
  }

  // Access Control Functions

  // @notice Add an authorized adapter
  // @param adapterName_ Name of the adapter
  // @param adapter_ Address of the adapter
  function addAdapter(bytes32 adapterName_, address adapter_) external isAuthorized {
    _adapters[adapterName_] = adapter_;
    emit AddAdapter(adapterName_, adapter_, msg.sender);
  }

  // @notice Change the treasury address
  // @param newTreasury_ Address of the new treasury
  function changeTreasury(address newTreasury_) external isAuthorized {
    treasury = newTreasury_;
    emit ChangeTreasury(newTreasury_, msg.sender);
  }

  // @notice Wind down the module by transferring all collateral to the treasury
  function windDown() external isAuthorized {
    uint256 balance = IERC20Metadata(authorizedCollateral).balanceOf(address(this));
    IERC20Metadata(authorizedCollateral).transfer(treasury, balance);
    emit WindDown(treasury, balance, msg.sender);
  }

  // @notice Change the maximum total deposit threshold
  // @param newMaxDeposit New maximum total deposit threshold
  function changeMaxDeposit(uint256 newMaxDeposit) external isAuthorized {
    maxDeposit = newMaxDeposit;
    emit MaxDeposit(newMaxDeposit);
  }

  // View functions

  // @notice Get the debt of the module
  function getDebt() external view returns (int256) {
    return _debt;
  }

  // @notice Get the deposits of the module
  function getDeposits() external view returns (uint256) {
    return _deposits;
  }

  // @notice Get a specific adapter address
  function getAdapter(bytes32 adapterName_) external view returns (address) {
    return _adapters[adapterName_];
  }
}
