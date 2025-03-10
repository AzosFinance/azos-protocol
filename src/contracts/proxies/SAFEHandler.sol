// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ISAFEEngine} from '@interfaces/ISAFEEngine.sol';
import {ISuperfluid, ISuperToken} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/ISuperfluid.sol";
import {ISuperApp} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/ISuperApp.sol";
import {SuperAppDefinitions} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/superfluid/Definitions.sol";
import {IConstantFlowAgreementV1} from "@superfluid-finance/ethereum-contracts/contracts/interfaces/agreements/IConstantFlowAgreementV1.sol";
import {CFAv1Library} from "@superfluid-finance/ethereum-contracts/contracts/apps/CFAv1Library.sol";
import {ICollateralJoin} from '@interfaces/utils/ICollateralJoin.sol';
import {ICoinJoin} from '@interfaces/utils/ICoinJoin.sol';
import {IERC20Metadata} from '@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol';
import {Math, RAY, WAD} from '@libraries/Math.sol';

/**
 * @title  SAFEHandler
 * @notice This contract is a proxy contract used by the AzosSafeManager to handle SAFEs in the SAFEEngine
 * @dev    Each instance of this contract will be a proxy for a SAFE and can function as a Superfluid Super App
 */
contract SAFEHandler is ISuperApp {
    using Math for uint256;
    
    // --- Registry ---
    ISAFEEngine public immutable safeEngine;
    ISuperfluid public immutable host;
    
    // --- Super App Config ---
    uint256 constant private CONFIG_WORD = 
        SuperAppDefinitions.APP_LEVEL_FINAL |
        SuperAppDefinitions.BEFORE_AGREEMENT_CREATED_NOOP |
        SuperAppDefinitions.BEFORE_AGREEMENT_UPDATED_NOOP |
        SuperAppDefinitions.BEFORE_AGREEMENT_TERMINATED_NOOP;
    
    // --- Libraries ---
    using CFAv1Library for CFAv1Library.InitData;
    CFAv1Library.InitData private cfaV1;
    
    // --- Storage ---
    /// @notice Tracks accepted SuperTokens for streaming operations
    mapping(ISuperToken => bool) public acceptedTokens;
    
    /// @notice Tracks stream data for each token
    mapping(ISuperToken => mapping(address => StreamData)) public incomingStreams;
    
    /// @notice Maps SuperTokens to their corresponding join contracts
    mapping(ISuperToken => address) public tokenToJoin;
    
    /// @notice Maps SuperTokens to their underlying tokens (for unwrapping)
    mapping(ISuperToken => address) public superToUnderlying;
    
    /// @notice Tracks collateral types for each SuperToken
    mapping(ISuperToken => bytes32) public tokenToCollateralType;
    
    /// @notice CoinJoin contract for repaying debt
    address public coinJoin;
    
    /// @notice Stream data structure to track flow details
    struct StreamData {
        int96 flowRate;         // Current flow rate
        uint256 timestamp;      // Last update timestamp
        StreamAction action;    // Action to take with streamed tokens
    }
    
    /// @notice Supported actions for incoming streams
    enum StreamAction {
        NONE,            // Do nothing with streamed tokens
        ADD_COLLATERAL,  // Automatically add as collateral
        REPAY_DEBT       // Automatically repay debt
    }
    
    /// @notice Events for stream management
    event StreamConfigured(address indexed token, address indexed sender, StreamAction action);
    event CollateralAdded(address indexed token, uint256 amount);
    event DebtRepaid(address indexed token, uint256 amount);
    event JoinConfigured(address indexed superToken, address indexed joinContract, bytes32 collateralType);
    event CoinJoinConfigured(address indexed coinJoin);
    
    /**
     * @notice Constructor
     * @param _safeEngine Address of the SAFEEngine contract
     * @param _host Address of the Superfluid host contract
     */
    constructor(address _safeEngine, address _host) {
        safeEngine = ISAFEEngine(_safeEngine);
        safeEngine.approveSAFEModification(msg.sender); // Important: approve SAFE manager
        
        if (_host != address(0)) {
            host = ISuperfluid(_host);
            
            // Initialize CFA library
            IConstantFlowAgreementV1 cfa = IConstantFlowAgreementV1(
                address(host.getAgreementClass(
                    keccak256("org.superfluid-finance.agreements.ConstantFlowAgreement.v1")
                ))
            );
            cfaV1 = CFAv1Library.InitData(host, cfa);
            
            // Register as Super App
            host.registerApp(CONFIG_WORD);
        } else {
            host = ISuperfluid(address(0));
        }
    }
    
    // --- Configuration Functions ---
    
    /**
     * @notice Configure which tokens are accepted for streaming
     * @param _token SuperToken address
     * @param _accepted Whether to accept this token
     */
    function setAcceptedToken(ISuperToken _token, bool _accepted) external {
        require(msg.sender == safeEngine.canModifySAFE(address(this), msg.sender), "Not authorized");
        acceptedTokens[_token] = _accepted;
    }
    
    /**
     * @notice Configure what to do with incoming streams
     * @param _token SuperToken address
     * @param _sender Sender of the stream
     * @param _action Action to take with streamed tokens
     */
    function configureStream(ISuperToken _token, address _sender, StreamAction _action) external {
        require(msg.sender == safeEngine.canModifySAFE(address(this), msg.sender), "Not authorized");
        incomingStreams[_token][_sender].action = _action;
        emit StreamConfigured(address(_token), _sender, _action);
    }
    
    /**
     * @notice Configure join contract for a SuperToken
     * @param _superToken SuperToken address
     * @param _joinContract Join contract address
     * @param _underlyingToken Underlying token address
     * @param _collateralType Collateral type bytes32
     */
    function configureTokenJoin(
        ISuperToken _superToken, 
        address _joinContract, 
        address _underlyingToken,
        bytes32 _collateralType
    ) external {
        require(msg.sender == safeEngine.canModifySAFE(address(this), msg.sender), "Not authorized");
        
        tokenToJoin[_superToken] = _joinContract;
        superToUnderlying[_superToken] = _underlyingToken;
        tokenToCollateralType[_superToken] = _collateralType;
        
        // Approve the join contract to take the underlying token
        IERC20Metadata(_underlyingToken).approve(_joinContract, type(uint256).max);
        
        emit JoinConfigured(address(_superToken), _joinContract, _collateralType);
    }
    
    /**
     * @notice Configure CoinJoin for repaying debt
     * @param _coinJoin CoinJoin contract address
     */
    function configureCoinJoin(address _coinJoin) external {
        require(msg.sender == safeEngine.canModifySAFE(address(this), msg.sender), "Not authorized");
        coinJoin = _coinJoin;
        
        // Get the system coin address from the CoinJoin
        address systemCoin = address(ICoinJoin(_coinJoin).systemCoin());
        
        // Approve the CoinJoin to take the system coin
        IERC20Metadata(systemCoin).approve(_coinJoin, type(uint256).max);
        
        emit CoinJoinConfigured(_coinJoin);
    }
    
    // --- Super App Interface Implementation ---
    
    function beforeAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 /*_agreementId*/,
        bytes calldata /*_agreementData*/,
        bytes calldata /*_ctx*/
    ) external view override returns (bytes memory) {
        // Only accept streams for tokens we've approved
        require(acceptedTokens[_superToken], "Token not accepted");
        
        // Only accept constant flow agreements
        require(
            _agreementClass == address(cfaV1.cfa),
            "Only CFAv1 supported"
        );
        
        return new bytes(0);
    }
    
    function afterAgreementCreated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata _agreementData,
        bytes calldata /*_cbdata*/,
        bytes calldata _ctx
    ) external override returns (bytes memory newCtx) {
        require(msg.sender == address(host), "Only host can call callbacks");
        
        if (_agreementClass == address(cfaV1.cfa)) {
            // Get the flow details
            (address sender, ) = abi.decode(_agreementData, (address, address));
            
            (,int96 flowRate,,) = cfaV1.cfa.getFlowByID(_superToken, _agreementId);
            
            // Update stream data
            incomingStreams[_superToken][sender] = StreamData({
                flowRate: flowRate,
                timestamp: block.timestamp,
                action: incomingStreams[_superToken][sender].action
            });
        }
        
        return _ctx;
    }
    
    function beforeAgreementUpdated(
        ISuperToken /*_superToken*/,
        address /*_agreementClass*/,
        bytes32 /*_agreementId*/,
        bytes calldata /*_agreementData*/,
        bytes calldata /*_ctx*/
    ) external pure override returns (bytes memory) {
        return new bytes(0);
    }
    
    function afterAgreementUpdated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 _agreementId,
        bytes calldata _agreementData,
        bytes calldata /*_cbdata*/,
        bytes calldata _ctx
    ) external override returns (bytes memory newCtx) {
        require(msg.sender == address(host), "Only host can call callbacks");
        
        if (_agreementClass == address(cfaV1.cfa)) {
            // Get the flow details
            (address sender, ) = abi.decode(_agreementData, (address, address));
            
            (,int96 flowRate,,) = cfaV1.cfa.getFlowByID(_superToken, _agreementId);
            
            // Process tokens received since last update
            _processReceivedTokens(_superToken, sender);
            
            // Update stream data with new flow rate
            incomingStreams[_superToken][sender].flowRate = flowRate;
            incomingStreams[_superToken][sender].timestamp = block.timestamp;
        }
        
        return _ctx;
    }
    
    function beforeAgreementTerminated(
        ISuperToken /*_superToken*/,
        address /*_agreementClass*/,
        bytes32 /*_agreementId*/,
        bytes calldata /*_agreementData*/,
        bytes calldata /*_ctx*/
    ) external pure override returns (bytes memory) {
        return new bytes(0);
    }
    
    function afterAgreementTerminated(
        ISuperToken _superToken,
        address _agreementClass,
        bytes32 /*_agreementId*/,
        bytes calldata _agreementData,
        bytes calldata /*_cbdata*/,
        bytes calldata _ctx
    ) external override returns (bytes memory newCtx) {
        require(msg.sender == address(host), "Only host can call callbacks");
        
        if (_agreementClass == address(cfaV1.cfa)) {
            // Get the flow details
            (address sender, ) = abi.decode(_agreementData, (address, address));
            
            // Process any final tokens received
            _processReceivedTokens(_superToken, sender);
            
            // Reset the flow rate
            incomingStreams[_superToken][sender].flowRate = 0;
            incomingStreams[_superToken][sender].timestamp = block.timestamp;
        }
        
        return _ctx;
    }
    
    // --- Internal Functions ---
    
    /**
     * @notice Process tokens received from a stream since the last update
     * @param _token The SuperToken being streamed
     * @param _sender The sender of the stream
     */
    function _processReceivedTokens(ISuperToken _token, address _sender) internal {
        StreamData storage streamData = incomingStreams[_token][_sender];
        
        // Skip if flow rate is zero or action is NONE
        if (streamData.flowRate <= 0 || streamData.action == StreamAction.NONE) {
            return;
        }
        
        // Calculate tokens received since last update
        uint256 timeElapsed = block.timestamp - streamData.timestamp;
        uint256 tokensReceived = uint256(uint96(streamData.flowRate)) * timeElapsed;
        
        if (tokensReceived > 0) {
            // Perform the configured action
            if (streamData.action == StreamAction.ADD_COLLATERAL) {
                _addCollateral(_token, tokensReceived);
            } 
            else if (streamData.action == StreamAction.REPAY_DEBT) {
                _repayDebt(_token, tokensReceived);
            }
        }
    }
    
    /**
     * @notice Add collateral from streamed SuperTokens
     * @param _token The SuperToken to use as collateral
     * @param _amount The amount of SuperTokens to add as collateral
     */
    function _addCollateral(ISuperToken _token, uint256 _amount) internal {
        address joinAddress = tokenToJoin[_token];
        bytes32 cType = tokenToCollateralType[_token];
        address underlying = superToUnderlying[_token];
        
        if (joinAddress == address(0) || underlying == address(0)) {
            return; // Not configured correctly
        }
        
        // 1. Downgrade/unwrap the SuperToken to get the underlying token
        _token.downgrade(_amount);
        
        // 2. Use the CollateralJoin to add the collateral
        ICollateralJoin join = ICollateralJoin(joinAddress);
        join.join(address(this), _amount);
        
        // Emit event
        emit CollateralAdded(address(_token), _amount);
    }
    
    /**
     * @notice Repay debt using streamed SuperTokens
     * @param _token The SuperToken to use for repayment
     * @param _amount The amount of SuperTokens to use for repayment
     */
    function _repayDebt(ISuperToken _token, uint256 _amount) internal {
        if (coinJoin == address(0)) {
            return; // CoinJoin not configured
        }
        
        // Check if this is a system coin super token
        ICoinJoin _coinJoin = ICoinJoin(coinJoin);
        address systemCoinAddr = address(_coinJoin.systemCoin());
        
        // 1. Downgrade/unwrap the SuperToken to get the underlying token
        _token.downgrade(_amount);
        
        // 2. Use the CoinJoin to repay debt
        if (systemCoinAddr == superToUnderlying[_token]) {
            // If it's the system coin, use it directly to repay debt
            _coinJoin.join(address(this), _amount);
            
            // Calculate debt to repay
            bytes32 cType = safeEngine.safes(tokenToCollateralType[_token], address(this)).collateralType;
            uint256 rate = safeEngine.cData(cType).accumulatedRate;
            uint256 coinAmount = safeEngine.coinBalance(address(this));
            
            // Repay debt
            if (coinAmount > 0) {
                uint256 generatedDebt = safeEngine.safes(cType, address(this)).generatedDebt;
                int256 deltaDebt = (coinAmount / rate).toInt();
                deltaDebt = uint256(deltaDebt) <= generatedDebt ? -deltaDebt : -int256(generatedDebt);
                
                // Modify SAFE collateralization
                safeEngine.modifySAFECollateralization(
                    cType,
                    address(this),
                    address(this),
                    address(this),
                    0,
                    deltaDebt
                );
            }
        }
        
        // Emit event  
        emit DebtRepaid(address(_token), _amount);
    }
}
