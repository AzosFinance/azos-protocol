// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {SuperToken} from '@superfluid-finance/ethereum-contracts/contracts/tokens/SuperToken.sol';
import {ISuperToken} from '@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/ISuperToken.sol';
import {ISystemCoin} from '@interfaces/tokens/ISystemCoin.sol';

/**
 * @title SystemCoinSuperToken
 * @notice Superfluid wrapper for SystemCoin (AZUSD) to enable streaming capabilities
 * @dev This follows the standard SuperToken pattern where an underlying token
 *      can be wrapped/unwrapped to enable streaming features
 */
contract SystemCoinSuperToken is SuperToken {
    /// @notice The underlying SystemCoin (AZUSD) token
    ISystemCoin public immutable systemCoin;
    
    /**
     * @notice Constructor for SystemCoinSuperToken
     * @param _systemCoin Address of the SystemCoin (AZUSD) token
     */
    constructor(address _systemCoin) {
        systemCoin = ISystemCoin(_systemCoin);
    }
    
    /**
     * @notice Initialize the SuperToken with necessary information
     * @param _name Name of the SuperToken
     * @param _symbol Symbol of the SuperToken
     */
    function initialize(string memory _name, string memory _symbol) external {
        require(address(this) != address(0), 'SystemCoinSuperToken: zero address');
        
        // Initialize the SuperToken with the name, symbol and underlying token information
        _initialize(
            address(systemCoin), // underlying token
            18, // decimals (same as SystemCoin)
            _name, 
            _symbol
        );
    }
} 