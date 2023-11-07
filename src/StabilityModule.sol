// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';
import {IERC20Metadata} from '@openzeppelin/token/ERC20/extensions/IERC20Metadata.sol';

import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {Authorizable, IAuthorizable} from '@contracts/utils/Authorizable.sol';

contract StabilityModule is Authorizable {
  /////////////////////////
  // Events And Errors   //
  /////////////////////////

  error FailedDelegateCall();
  error NoAdapter();
  error FailedDeploy();
  error InvalidTrade();
  error InvalidBalance();
  error InvalidFee();
  error DebtCeiling();

  // Event logs adding a new adapter by authorized address
  event AddAdapter(bytes32 indexed adapterName, address indexed adapter, address indexed authorized);
  // Event logs changing the treasury address by authorized address
  event ChangeTreasury(address indexed newTreasury, address indexed authorized);
  // Event logging the winding down of a module
  event WindDown(address indexed treasury, uint256 indexed amount, address indexed authorized);
  // Event logging change to max deposit
  event MaxDeposit(uint256 indexed maxDeposit);
  // Event logging the debt ceiling
  event DebtCeilingChange(uint256 indexed debtCeiling);
  // Event logging deposit
  event Deposit(uint256 indexed amount);
  // Event logging burning of any extra coins
  event BurnBalance(uint256 indexed amount);
  // Event logging the expansion of supply and debt
  event Expand(uint256 indexed amount, address indexed target, bytes returnData);
  // Event logging the keeper fee
  event KeeperFeePaid(uint256 indexed amount, address indexed keeper, address indexed token);
  // Event for changing the keeper fee
    event KeeperFee(uint256 indexed newFee);
  // Event logging change in debt and balance
  event DebtChange(
    int256 indexed previousDebt, int256 indexed newDebt, uint256 indexed previousBalance, uint256 newBalance
  );

  /////////////
  // State   //
  /////////////

  uint256 constant BASIS_POINTS = 10_000;

  IERC20Metadata public authorizedCollateral;
  uint256 public scalingFactor;

  address treasury;
  ISystemCoin public systemCoin; // ZAI

  // Debt is scaled to the collateral decimals; IE the system coin debt will be scaled to the number of decimals in the
  // collateral token
  int256 private _debt;
  uint256 public debtCeiling;
  uint256 private _deposits;
  uint256 public maxDeposit;

  uint256 public basisFee;

  mapping(bytes32 adapterName => address adapterContract) private _adapters;

  constructor(
    address authorizedCollateral_,
    address adapter_,
    bytes32 adapterName_,
    address treasury_,
    address systemCoin_,
    address governance_,
    uint256 maxDeposit_,
    uint256 debtCeiling_,
    uint256 basisFee_
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
    debtCeiling = debtCeiling_;
    basisFee = basisFee_;
    emit KeeperFee(basisFee_);
    emit DebtCeilingChange(debtCeiling_);
    emit MaxDeposit(maxDeposit_);
    emit AddAdapter(adapterName_, adapter_, msg.sender);
  }

  //////////////////////////
  // Mutable functions    //
  //////////////////////////

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

    (int256 previousDebt, uint256 previousBalance, uint256 previousEquity) = _checkpoint();

    // We have to scale the system coin's debt to the decimal precision of the collateral
    int256 newDebt = previousDebt + _scaleToDebt(mintAmount);
    if (newDebt > int256(debtCeiling)) {
      revert InvalidTrade();
    }
    systemCoin.mint(address(this), mintAmount);

    (bool success, bytes memory returnData) = target.delegatecall(data);
    if (!success) {
      revert DebtCeiling();
    }

    uint256 newBalance = IERC20Metadata(authorizedCollateral).balanceOf(address(this));
    uint256 newEquity = newBalance - uint256(newDebt);
    uint256 equityDelta = newEquity - previousEquity;

    if (newEquity < previousEquity) {
      revert InvalidTrade();
    }

    _debt = newDebt;

    _payKeeper(equityDelta, address(authorizedCollateral));

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

  /////////////////////////
  // Helper functions    //
  /////////////////////////

  // @notice Scales debt to the collateral token's decimals
  // @param amount Amount of debt to scale
  function _scaleToDebt(uint256 amount) internal view returns (int256) {
    if (scalingFactor == 0) {
      return int256(amount);
    }
    return int256(amount / (10 ** scalingFactor));
  }

  // @notice Pay the function caller a keeper fee
  // @param equityDelta Change in equity
  // @param token Address of the token to pay the keeper fee in
  function _payKeeper(uint256 equityDelta, address token) internal {
    uint256 keeperFee = (equityDelta * basisFee) / BASIS_POINTS;
    if (keeperFee > 0) {
      IERC20Metadata(token).transfer(msg.sender, keeperFee);
      emit KeeperFeePaid(keeperFee, msg.sender, token);
    }
  }

  // @notice Checkpoints the contracts debt, balance of collateral and equity
  function _checkpoint() internal view returns (int256 debt, uint256 balance, uint256 equity) {
    debt = _debt;
    balance = IERC20Metadata(authorizedCollateral).balanceOf(address(this));
    equity = balance - uint256(debt);
  }

  /////////////////////////////////
  // Access Control Functions    //
  /////////////////////////////////

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

  // @notice Change the debt ceiling
  // @param newDebtCeiling New debt ceiling
  function changeDebtCeiling(uint256 newDebtCeiling) external isAuthorized {
    debtCeiling = newDebtCeiling;
    emit DebtCeilingChange(newDebtCeiling);
  }

  // @notice Change the basis fee
  // @param newBasisFee New basis fee
  function changeBasisFee(uint256 newBasisFee) external isAuthorized {
    if (newBasisFee > BASIS_POINTS) {
      revert InvalidFee();
    }
    basisFee = newBasisFee;
    emit KeeperFee(newBasisFee);
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
