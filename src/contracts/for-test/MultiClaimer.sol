// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ClaimableERC20} from "./ClaimableERC20.sol";

/**
 * @title MultiClaimer
 * @notice Allows claiming multiple ClaimableERC20 tokens in a single transaction
 */
contract MultiClaimer {
    /// @notice Array of all claimable token addresses
    ClaimableERC20[] public claimableTokens;
    
    /// @notice Emitted when tokens are claimed
    event TokensClaimed(address indexed user, address[] tokens);

    /**
     * @notice Constructor that sets up the claimable tokens
     * @param _tokens Array of ClaimableERC20 token addresses
     */
    constructor(address[] memory _tokens) {
        for (uint256 i = 0; i < _tokens.length; i++) {
            claimableTokens.push(ClaimableERC20(_tokens[i]));
        }
    }

    /**
     * @notice Claims all available tokens for the caller
     * @return claimedTokens Array of addresses of the tokens that were successfully claimed
     */
    function claimAll() external returns (address[] memory claimedTokens) {
        uint256 tokenCount = claimableTokens.length;
        address[] memory claimed = new address[](tokenCount);
        uint256 claimedCount = 0;

        for (uint256 i = 0; i < tokenCount; i++) {
            ClaimableERC20 token = claimableTokens[i];
            if (token.canClaim(msg.sender)) {
                token.claim();
                claimed[claimedCount] = address(token);
                claimedCount++;
            }
        }

        // Create correctly sized array for claimed tokens
        claimedTokens = new address[](claimedCount);
        for (uint256 i = 0; i < claimedCount; i++) {
            claimedTokens[i] = claimed[i];
        }

        emit TokensClaimed(msg.sender, claimedTokens);
    }

    /**
     * @notice Get all tokens that are currently claimable by an address
     * @param _user Address to check claimable tokens for
     * @return claimableList Array of addresses of tokens that can be claimed
     */
    function getClaimableTokens(address _user) external view returns (address[] memory claimableList) {
        uint256 tokenCount = claimableTokens.length;
        address[] memory available = new address[](tokenCount);
        uint256 availableCount = 0;

        for (uint256 i = 0; i < tokenCount; i++) {
            if (claimableTokens[i].canClaim(_user)) {
                available[availableCount] = address(claimableTokens[i]);
                availableCount++;
            }
        }

        // Create correctly sized array for available tokens
        claimableList = new address[](availableCount);
        for (uint256 i = 0; i < availableCount; i++) {
            claimableList[i] = available[i];
        }
    }

    /**
     * @notice Get the total number of registered claimable tokens
     */
    function getTokenCount() external view returns (uint256) {
        return claimableTokens.length;
    }
} 