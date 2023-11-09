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
  error FailedTransfer();
  error InvalidTrade();
  error InvalidBalance();
  error InvalidFee();
  error InvalidDeposit();
  error InvalidDebt();
  error DebtCeiling();

  // Event logs adding a new adapter by authorized address
  event AddAdapter(bytes32 indexed adapterName, address indexed adapter, address indexed authorized);
  // Event logs changing the treasury address by authorized address
  event ChangeTreasury(address indexed newTreasury, address indexed authorized);
  // Event logging the winding down of a module
  event WindDown(
    address indexed treasury, uint256 indexed collateralAmount, uint256 coinAmount, address indexed authorized
  );
  // Event logging change to max deposit
  event MaxDeposit(uint256 indexed maxDeposit);
  // Event logging the debt ceiling
  event DebtCeilingChange(uint256 indexed debtCeiling);
  // Event logging deposit
  event Deposit(uint256 indexed amount);
  // Event logging burning of any extra coins
  event BurnBalance(uint256 indexed amount);
  // Event logging the expansion of supply and return data from trade
  event Expand(uint256 indexed amount, uint256 indexed burnAmount, address indexed target, bytes returnData);
  // Event logging the contraction of supply and return data from trade
  event Contract(uint256 indexed amount, uint256 indexed burnAmount, address indexed target, bytes returnData);
  // Event logging the keeper fee
  event KeeperFeePaid(uint256 indexed amount, address indexed keeper, address indexed token);
  // Event for changing the keeper fee
  event KeeperFee(uint256 indexed newFee);
  // Event for logging the authorized collateral address
  event AuthorizedCollateral(address indexed authorizedCollateral);

  // Event logging change in debt and balance during expansion
  event ExpandDebt(
    int256 indexed previousDebt, int256 indexed newDebt, uint256 indexed previousBalance, uint256 newBalance
  );

  // Event logging change in debt and balance during contraction
  event ContractDebt(
    int256 indexed previousDebt, int256 indexed newDebt, uint256 indexed previousBalance, uint256 newBalance
  );

  uint256 constant BASIS_POINTS = 10_000;

  /////////////
  // State   //
  /////////////

  IERC20Metadata public authorizedCollateral;
  // To convert system coins to collateral we divide by 10 to the power of scaling factor
  // To convert collateral to system coins we multiply by 10 to the power of scaling factor
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
    emit AuthorizedCollateral(authorizedCollateral_);
  }

  //////////////////////////
  // Mutative functions   //
  //////////////////////////

  // @notice Allows expanding system coin supply and executing delegate function calls on approved adapters
  // @param adapterName Name of the adapter example: bytes32("Curve")
  // @param data Data to be passed to the adapter
  // @param mintAmount Amount of system coins to mint
  function expandAndBuy(bytes32 adapterName, bytes calldata data, uint256 mintAmount) public {
    address target = _adapters[adapterName];
    if (target == address(0)) {
      revert NoAdapter();
    }

    (int256 previousDebt, uint256 previousCollateral, uint256 previousEquity) = _checkpoint();

    // We have to scale the system coin's debt to the decimal precision of the collateral
    int256 newDebt = previousDebt + _scaleFromSystemCoin(mintAmount);
    if (newDebt > int256(debtCeiling)) {
      revert DebtCeiling();
    }
    systemCoin.mint(address(this), mintAmount);

    (bool success, bytes memory returnData) = target.delegatecall(data);
    if (!success) {
      revert FailedDelegateCall();
    }

    (uint256 equityDelta, uint256 newCollateral, int256 finalDebt, uint256 burnAmount) =
      _checkEquity(previousEquity, newDebt);

    _payKeeper(equityDelta, address(authorizedCollateral));

    emit ExpandDebt(previousDebt, finalDebt, previousCollateral, newCollateral);
    emit Expand(mintAmount, burnAmount, target, returnData);
  }

  // @notice Allows contracting the system coin supply and executing delegate function calls on approved adapters
  // @param adapterName Name of the adapter
  // @param data Data to be passed to the adapter
  function contractAndSell(bytes32 adapterName, bytes calldata data) public {
    address target = _adapters[adapterName];
    if (target == address(0)) {
      revert NoAdapter();
    }

    (int256 previousDebt, uint256 previousCollateral, uint256 previousEquity) = _checkpoint();

    (bool success, bytes memory returnData) = target.delegatecall(data);
    if (!success) {
      revert FailedDelegateCall();
    }

    (uint256 equityDelta, uint256 newCollateral, int256 finalDebt, uint256 burnAmount) =
      _checkEquity(previousEquity, previousDebt);

    _payKeeper(equityDelta, address(systemCoin));

    emit ContractDebt(previousDebt, finalDebt, previousCollateral, newCollateral);
    emit Contract(0, burnAmount, target, returnData);
  }

  // @notice Allows user's to deposit approved collateral for system coins
  // @param amount Amount of collateral to deposit
  function deposit(uint256 amount) public {
    uint256 previousDeposit = _deposits;
    if (amount + previousDeposit > maxDeposit) {
      revert InvalidDeposit();
    }
    _deposits = previousDeposit + amount;
    bool success;
    success = authorizedCollateral.transferFrom(msg.sender, address(this), amount);
    if (!success) {
      revert FailedTransfer();
    }

    _debt = _debt + int256(amount);
    uint256 scaledAmount = _scaleToSystemCoin(amount);
    systemCoin.mint(msg.sender, scaledAmount);
    emit Deposit(amount);
  }

  /////////////////////////
  // Helper functions    //
  /////////////////////////

  // @notice Pay the function caller a keeper fee
  // @param equityDelta Change in equity
  // @param token Address of the token to pay the keeper fee in
  function _payKeeper(uint256 equityDelta, address token) private {
    uint256 keeperFee = (equityDelta * basisFee) / BASIS_POINTS;
    if (keeperFee > 0) {
      IERC20Metadata(token).transfer(msg.sender, keeperFee);
      emit KeeperFeePaid(keeperFee, msg.sender, token);
    }
  }

  // @notice Burns any system coins from the stability module; and reduces it's debt by that amount
  // @param currentDebt Current debt of the module
  function _burnCoin(int256 currentDebt) private returns (int256 debt, uint256 coinBalance) {
    coinBalance = systemCoin.balanceOf(address(this));
    if (coinBalance == 0) {
      _debt = currentDebt;
      return (currentDebt, 0);
    }

    debt = currentDebt - _scaleFromSystemCoin(coinBalance);
    systemCoin.burn(coinBalance);
    _debt = debt;
    emit BurnBalance(coinBalance);
  }

  // @notice Checkpoints the contracts debt, balance of collateral and equity
  function _checkpoint() private view returns (int256 debt, uint256 collateralBalance, uint256 equity) {
    debt = _debt;
    collateralBalance = authorizedCollateral.balanceOf(address(this));
    uint256 coinBalance = systemCoin.balanceOf(address(this));
    if (debt > 0) {
      equity = collateralBalance + uint256(_scaleFromSystemCoin(coinBalance)) - uint256(debt);
    } else {
      equity = collateralBalance + uint256(_scaleFromSystemCoin(coinBalance)) + abs(debt);
    }
  }

  // @notice Check equity
  // @param previousEquity Previous equity
  // @param newDebt Existing debt balance
  function _checkEquity(
    uint256 previousEquity,
    int256 debt
  ) private returns (uint256 newCollateral, uint256 equityDelta, int256 finalDebt, uint256 burned) {
    newCollateral = authorizedCollateral.balanceOf(address(this));
    (finalDebt, burned) = _burnCoin(debt);

    // We have to account for the sign of our debt
    // If the debt is negative; that's a credit towards our equity
    uint256 newEquity;
    if (finalDebt > 0) {
      newEquity = newCollateral - uint256(finalDebt);
    } else {
      newEquity = newCollateral + abs(finalDebt);
    }

    if (newEquity <= previousEquity) {
      revert InvalidTrade();
    }

    equityDelta = newEquity - previousEquity;
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
    int256 debt = _debt;
    uint256 credit;
    if (debt > 0) {
      revert InvalidDebt();
    }

    if (debt < 0) {
      credit = abs(debt);
      systemCoin.mint(treasury, credit);
    }

    uint256 balance = authorizedCollateral.balanceOf(address(this));
    authorizedCollateral.transfer(treasury, balance);

    emit WindDown(treasury, balance, credit, msg.sender);
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

  /////////////////////////
  // View functions      //
  /////////////////////////

  // @notice Scales system coin to the collateral token's decimals
  // @param amount Amount of system coin to scale
  function _scaleFromSystemCoin(uint256 amount) public view returns (int256) {
    if (scalingFactor == 0) {
      return int256(amount);
    }
    return int256(amount / (10 ** scalingFactor));
  }

  // @notice Scales collateral token to the system coin's decimals
  // @param amount Amount of collateral to scale
  function _scaleToSystemCoin(uint256 amount) public view returns (uint256) {
    if (scalingFactor == 0) {
      return amount;
    }
    return amount * (10 ** scalingFactor);
  }

  // @notice Get the debt of the module
  function getDebt() external view returns (int256) {
    return _debt;
  }

  // @notice Get the deposits of the module
  function getDeposits() external view returns (uint256) {
    return _deposits;
  }

  // @notice Get a specific adapter address
  // @param adapterName_ Name of the adapter
  function getAdapter(bytes32 adapterName_) external view returns (address) {
    return _adapters[adapterName_];
  }

  // @notice Return the absolute value of a signed integer as an unsigned integer
  function abs(int256 x) internal pure returns (uint256) {
    x >= 0 ? x : -x;
    return uint256(x);
  }
}
