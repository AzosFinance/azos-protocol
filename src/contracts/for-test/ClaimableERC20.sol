// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ERC20} from '@openzeppelin/contracts/token/ERC20/ERC20.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';

/**
 * @title  ClaimableERC20
 * @notice This ERC20 contract allows users to claim a configurable amount of tokens every 13 hours
 */
contract ClaimableERC20 is IERC20Metadata, ERC20 {
  /// @notice The number of decimals the token uses
  uint8 internal _decimals;
  
  /// @notice The amount of tokens that can be claimed per period
  uint256 public immutable CLAIM_AMOUNT;
  
  /// @notice The duration of each claiming period (13 hours in seconds)
  uint256 public constant CLAIM_PERIOD = 13 hours;
  
  /// @notice The amount of tokens minted to the contract creator on deployment
  uint256 public constant INITIAL_MINT_AMOUNT = 2_000_000;
  
  /// @notice Mapping to track the last claim timestamp for each user
  mapping(address => uint256) public lastClaimTimestamp;
  
  /**
   * @param  _name The name of the ERC20 token
   * @param  _symbol The symbol of the ERC20 token
   * @param  __decimals The number of decimals the token uses
   * @param  _amount The amount of tokens that can be claimed per period
   */
  constructor(
    string memory _name,
    string memory _symbol,
    uint8 __decimals,
    uint256 _amount
  ) ERC20(_name, _symbol) {
    _decimals = __decimals;
    CLAIM_AMOUNT = _amount * 10**_decimals;
    
    // Mint 2 million tokens to the contract creator
    _mint(msg.sender, INITIAL_MINT_AMOUNT * 10**_decimals);
  }
  
  /// @inheritdoc IERC20Metadata
  function decimals() public view virtual override(ERC20, IERC20Metadata) returns (uint8) {
    return _decimals;
  }
  
  /**
   * @notice Claim the token allowance for the current period
   */
  function claim() external {
    require(canClaim(msg.sender), "Claim period has not elapsed");
    
    lastClaimTimestamp[msg.sender] = block.timestamp;
    
    _mint(msg.sender, CLAIM_AMOUNT);
  }
  
  /**
   * @notice Check if a user can claim tokens
   * @param _user Address of the user to check
   * @return Whether the user can claim tokens
   */
  function canClaim(address _user) public view returns (bool) {
    return block.timestamp >= lastClaimTimestamp[_user] + CLAIM_PERIOD;
  }
  
  /**
   * @notice Get the time remaining until the next claim for a user
   * @param _user Address of the user to check
   * @return The time remaining in seconds, or 0 if claiming is available
   */
  function getTimeUntilNextClaim(address _user) external view returns (uint256) {
    uint256 nextClaimTime = lastClaimTimestamp[_user] + CLAIM_PERIOD;
    if (block.timestamp >= nextClaimTime) {
      return 0;
    }
    return nextClaimTime - block.timestamp;
  }
}
