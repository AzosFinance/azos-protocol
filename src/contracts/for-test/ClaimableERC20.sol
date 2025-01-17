// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Ownable} from '@openzeppelin/contracts/access/Ownable.sol';

/**
 * @title  ClaimableERC20
 * @notice This ERC20 contract allows users to claim a configurable amount of tokens every 13 hours
 */
contract ClaimableERC20 is IERC20Metadata, ERC20, Ownable {
  /// @notice The number of decimals the token uses
  uint8 internal _decimals;
  
  /// @notice The amount of tokens that can be claimed per period
  uint256 public claimAmount;
  
  /// @notice The duration of each claiming period
  uint256 public claimPeriod;
  
  /// @notice The amount of tokens minted to the contract creator on deployment
  uint256 public constant INITIAL_MINT_AMOUNT = 2_000_000;
  
  /// @notice Mapping to track the last claim timestamp for each user
  mapping(address => uint256) public lastClaimTimestamp;

  event ClaimPeriodUpdated(uint256 newPeriod);
  event ClaimAmountUpdated(uint256 newAmount);
  
  /**
   * @param  _name The name of the ERC20 token
   * @param  _symbol The symbol of the ERC20 token
   * @param  __decimals The number of decimals the token uses
   * @param  _amount The amount of tokens that can be claimed per period
   * @param  _claimPeriod The initial claim period in seconds
   */
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 __decimals,
    uint256 _amount,
    uint256 _claimPeriod
  ) ERC20(_name, _symbol) Ownable(msg.sender) {
    _decimals = __decimals;
    claimAmount = _amount * 10**_decimals;
    claimPeriod = _claimPeriod;
    
    // Mint 2 million tokens to the contract creator
    _mint(msg.sender, INITIAL_MINT_AMOUNT * 10**_decimals);
  }

  /**
   * @notice Allows owner to set a new claim period
   * @param _newPeriod New claim period in seconds
   */
  function setClaimPeriod(uint256 _newPeriod) external onlyOwner {
    require(_newPeriod > 0, 'Claim period must be greater than 0');
    claimPeriod = _newPeriod;
    emit ClaimPeriodUpdated(_newPeriod);
  }

  /**
   * @notice Allows owner to set a new claim amount
   * @param _newAmount New claim amount (before decimals)
   */
  function setClaimAmount(uint256 _newAmount) external onlyOwner {
    uint256 adjustedAmount = _newAmount * 10**_decimals;
    require(adjustedAmount > 0, 'Claim amount must be greater than 0');
    claimAmount = adjustedAmount;
    emit ClaimAmountUpdated(adjustedAmount);
  }

  /// @inheritdoc IERC20Metadata
  function decimals() public view virtual override(ERC20, IERC20Metadata) returns (uint8) {
    return _decimals;
  }
  
  /**
   * @notice Claim the token allowance for the current period
   */
  function claim() external {
    require(canClaim(msg.sender), 'Claim period has not elapsed');
    
    lastClaimTimestamp[msg.sender] = block.timestamp;
    
    _mint(msg.sender, claimAmount);
  }
  
  /**
   * @notice Check if a user can claim tokens
   * @param _user Address of the user to check
   * @return Whether the user can claim tokens
   */
  function canClaim(address _user) public view returns (bool) {
    return block.timestamp >= lastClaimTimestamp[_user] + claimPeriod;
  }
  
  /**
   * @notice Get the time remaining until the next claim for a user
   * @param _user Address of the user to check
   * @return The time remaining in seconds, or 0 if claiming is available
   */
  function getTimeUntilNextClaim(address _user) external view returns (uint256) {
    uint256 nextClaimTime = lastClaimTimestamp[_user] + claimPeriod;
    if (block.timestamp >= nextClaimTime) {
      return 0;
    }
    return nextClaimTime - block.timestamp;
  }
}
