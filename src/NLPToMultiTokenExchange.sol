// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { Address } from "@openzeppelin/contracts/utils/Address.sol";
import { AggregatorV3Interface } from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Extended } from "./interfaces/IERC20Extended.sol";

/**
 * @title NLPToMultiTokenExchange
 * @author NewLo Team
 * @notice NewLo Point (NLP) から複数トークン（ETH, USDC, USDT）への交換コントラクト
 * @dev This contract allows users to exchange NLP tokens for multiple tokens using flexible price feeds
 *
 * @dev Key Features:
 *      - 1:1 NLP to JPY exchange rate
 *      - Multi-token support (ETH, USDC, USDT)
 *      - Flexible price data management (Chainlink oracles + external/batch updates)
 *      - Role-based access control for different administrative functions
 *      - Configurable exchange fees per token
 *      - Operational fee collection system
 *      - Emergency pause functionality
 *      - Administrative fund management
 *      - Comprehensive exchange statistics
 *      - Gasless exchange using permit
 *
 * @dev Exchange Formula:
 *      1. NLP → JPY (1:1 ratio)
 *      2. JPY → USD using JPY/USD price feed (oracle or external)
 *      3. USD → Target Token using token/USD price feed
 *      Formula: tokenAmount = (nlpAmount * jpyUsdPrice) / tokenUsdPrice - exchangeFee - operationalFee
 *
 * @dev Price Data Sources:
 *      - Chainlink Oracle (when available)
 *      - External price data (batch updates by admin)
 *      - Fallback to external data when oracle fails
 *
 * @dev Security Features:
 *      - Reentrancy protection
 *      - Pausable for emergency stops
 *      - Price staleness checks
 *      - Comprehensive input validation
 *      - CEI (Checks-Effects-Interactions) pattern
 *      - Role-based access control for different functions
 *
 * @dev Access Control Roles:
 *      - DEFAULT_ADMIN_ROLE: Super admin with all permissions
 *      - CONFIG_MANAGER_ROLE: Can configure tokens, fees, and general settings
 *      - PRICE_UPDATER_ROLE: Can update external price data
 *      - EMERGENCY_MANAGER_ROLE: Can pause/unpause and perform emergency withdrawals
 *      - FEE_MANAGER_ROLE: Can manage operational fees and withdrawal
 */
contract NLPToMultiTokenExchange is AccessControl, ReentrancyGuard, Pausable {
    /* ═══════════════════════════════════════════════════════════════════════
                                   ENUMS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Supported token types for exchange
    enum TokenType {
        ETH,
        USDC,
        USDT
    }

    /// @notice Price data source types
    enum PriceSource {
        CHAINLINK_ORACLE,
        EXTERNAL_DATA,
        FALLBACK
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                  STRUCTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Token configuration
    struct TokenConfig {
        address tokenAddress; // Token contract address (address(0) for ETH)
        AggregatorV3Interface priceFeed; // Chainlink price feed (if available)
        uint8 decimals; // Token decimals
        uint exchangeFee; // Exchange fee in basis points (100 = 1%)
        bool isEnabled; // Whether exchanges are enabled for this token
        bool hasOracle; // Whether Chainlink oracle is available
        string symbol; // Token symbol for events
    }

    /// @notice External price data
    struct ExternalPriceData {
        uint price; // Price in USD (18 decimals)
        uint updatedAt; // Last update timestamp
        address updatedBy; // Address that updated the price
        bool isValid; // Whether price data is valid
    }

    /// @notice Exchange statistics per token
    struct TokenStats {
        uint totalExchanged; // Total NLP exchanged for this token
        uint totalTokenSent; // Total tokens sent to users
        uint totalExchangeFeeCollected; // Total exchange fees collected
        uint totalOperationalFeeCollected; // Total operational fees collected
        uint exchangeCount; // Number of exchanges
    }

    /// @notice Operational fee configuration
    struct OperationalFeeConfig {
        uint feeRate; // Fee rate in basis points (100 = 1%)
        address feeRecipient; // Address to receive operational fees
        bool isEnabled; // Whether operational fee is enabled
    }

    /// @notice Price calculation result
    struct PriceCalculationResult {
        uint tokenUsdPrice; // Token price in USD (18 decimals)
        uint jpyUsdPrice; // JPY/USD price (18 decimals)
        PriceSource priceSource; // Price source used
    }

    /// @notice Token amount calculation result
    struct TokenAmountResult {
        uint tokenAmount; // Final token amount to send
        uint exchangeFee; // Exchange fee amount
        uint operationalFee; // Operational fee amount
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               IMMUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice NewLo Point token contract
    IERC20Extended public immutable nlpToken;

    /// @notice Chainlink JPY/USD price feed (if available)
    AggregatorV3Interface public immutable jpyUsdPriceFeed;

    /// @notice Whether JPY/USD oracle is available
    bool public immutable hasJpyOracle;

    /// @notice Treasury address for emergency withdrawals
    address public treasury;

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Exchange rate: 1 NLP = 1 JPY
    uint public constant NLP_TO_JPY_RATE = 1;

    /// @notice Price data staleness threshold (1 hour)
    uint public constant PRICE_STALENESS_THRESHOLD = 3600;

    /// @notice Absolute maximum fee rate (100%)
    uint public constant ABSOLUTE_MAX_FEE = 10000;

    /// @notice Maximum fee rate (5% initially, configurable)
    uint public maxFee = 500;

    /// @notice Access control roles
    bytes32 public constant CONFIG_MANAGER_ROLE = keccak256("CONFIG_MANAGER_ROLE");
    bytes32 public constant PRICE_UPDATER_ROLE = keccak256("PRICE_UPDATER_ROLE");
    bytes32 public constant EMERGENCY_MANAGER_ROLE = keccak256("EMERGENCY_MANAGER_ROLE");
    bytes32 public constant FEE_MANAGER_ROLE = keccak256("FEE_MANAGER_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Token configurations
    mapping(TokenType => TokenConfig) public tokenConfigs;

    /// @notice External price data for tokens
    mapping(TokenType => ExternalPriceData) public externalPrices;

    /// @notice External JPY/USD price data
    ExternalPriceData public jpyUsdExternalPrice;

    /// @notice Exchange statistics per token
    mapping(TokenType => TokenStats) public tokenStats;

    /// @notice User exchange amounts per token
    mapping(address => mapping(TokenType => uint)) public userExchangeAmount;

    /// @notice User received token amounts per token
    mapping(address => mapping(TokenType => uint)) public userTokenReceived;

    /// @notice Operational fee configuration per token
    mapping(TokenType => OperationalFeeConfig) public operationalFeeConfigs;

    /// @notice Collected operational fees per token (available for withdrawal)
    mapping(TokenType => uint) public collectedOperationalFees;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when NLP is exchanged for tokens
    event ExchangeExecuted(
        address indexed user,
        TokenType indexed tokenType,
        uint nlpAmount,
        uint tokenAmount,
        uint tokenUsdRate,
        uint jpyUsdRate,
        uint exchangeFee,
        uint operationalFee,
        PriceSource priceSource
    );

    /// @notice Emitted when gasless exchange is executed
    event GaslessExchangeExecuted(
        address indexed user,
        address indexed relayer,
        TokenType indexed tokenType,
        uint nlpAmount,
        uint tokenAmount,
        uint tokenUsdRate,
        uint jpyUsdRate,
        uint exchangeFee,
        uint operationalFee,
        PriceSource priceSource
    );

    /// @notice Emitted when token configuration is updated
    event TokenConfigUpdated(
        TokenType indexed tokenType, address tokenAddress, uint exchangeFee, bool isEnabled
    );

    /// @notice Emitted when operational fee configuration is updated
    event OperationalFeeConfigUpdated(
        TokenType indexed tokenType, uint feeRate, address feeRecipient, bool isEnabled
    );

    /// @notice Emitted when external price is updated
    event ExternalPriceUpdated(
        TokenType indexed tokenType, uint newPrice, uint updatedAt, address updatedBy
    );

    /// @notice Emitted when JPY/USD external price is updated
    event JPYUSDExternalPriceUpdated(uint newPrice, uint updatedAt, address updatedBy);

    /// @notice Emitted when operational fee is withdrawn
    event OperationalFeeWithdrawn(TokenType indexed tokenType, address indexed to, uint amount);

    /// @notice Emitted when maximum fee rate is updated
    event MaxFeeUpdated(uint oldMaxFee, uint newMaxFee, address updatedBy);

    /// @notice Emitted when emergency withdrawal is executed
    event EmergencyWithdraw(TokenType indexed tokenType, address indexed to, uint amount);

    /// @notice Emitted when treasury address is updated
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error InsufficientBalance(TokenType tokenType, uint required, uint available);
    error InvalidExchangeAmount(uint amount);
    error PriceDataStale(uint updatedAt, uint threshold);
    error InvalidPriceData(int price);
    error ExchangeFailed(address user, uint nlpAmount);
    error InvalidExchangeFee(uint fee, uint maxFee);
    error InvalidOperationalFee(uint fee, uint maxFee);
    error InvalidUser(address user);
    error PermitFailed(address user, uint nlpAmount, uint deadline);
    error TokenNotEnabled(TokenType tokenType);
    error InvalidTokenConfig(TokenType tokenType);
    error NoPriceDataAvailable(TokenType tokenType);
    error InvalidPriceUpdate(uint price);
    error InvalidFeeRecipient(address recipient);
    error InsufficientOperationalFee(TokenType tokenType, uint required, uint available);
    error InvalidMaxFee(uint fee, uint absoluteMaxFee);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the multi-token exchange contract
     * @param _nlpToken NewLo Point token contract address
     * @param _jpyUsdPriceFeed Chainlink JPY/USD price feed address (address(0) if not available)
     * @param _initialAdmin Initial admin of the contract
     */
    constructor(address _nlpToken, address _jpyUsdPriceFeed, address _initialAdmin) {
        require(_nlpToken != address(0), "NLP token address cannot be zero");
        require(_initialAdmin != address(0), "Initial admin cannot be zero");

        nlpToken = IERC20Extended(_nlpToken);

        if (_jpyUsdPriceFeed != address(0)) {
            jpyUsdPriceFeed = AggregatorV3Interface(_jpyUsdPriceFeed);
            hasJpyOracle = true;
        } else {
            hasJpyOracle = false;
        }

        // Set up access control roles
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(CONFIG_MANAGER_ROLE, _initialAdmin);
        _grantRole(PRICE_UPDATER_ROLE, _initialAdmin);
        _grantRole(EMERGENCY_MANAGER_ROLE, _initialAdmin);
        _grantRole(FEE_MANAGER_ROLE, _initialAdmin);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                        TOKEN CONFIGURATION FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Configure a token for exchange
     * @param tokenType Token type to configure
     * @param tokenAddress Token contract address (address(0) for ETH)
     * @param priceFeed Chainlink price feed address (address(0) if not available)
     * @param decimals Token decimals
     * @param exchangeFee Exchange fee in basis points
     * @param symbol Token symbol
     */
    function configureToken(
        TokenType tokenType,
        address tokenAddress,
        address priceFeed,
        uint8 decimals,
        uint exchangeFee,
        string memory symbol
    ) external onlyRole(CONFIG_MANAGER_ROLE) {
        if (exchangeFee > maxFee) {
            revert InvalidExchangeFee(exchangeFee, maxFee);
        }

        tokenConfigs[tokenType] = TokenConfig({
            tokenAddress: tokenAddress,
            priceFeed: priceFeed != address(0)
                ? AggregatorV3Interface(priceFeed)
                : AggregatorV3Interface(address(0)),
            decimals: decimals,
            exchangeFee: exchangeFee,
            isEnabled: true,
            hasOracle: priceFeed != address(0),
            symbol: symbol
        });

        emit TokenConfigUpdated(tokenType, tokenAddress, exchangeFee, true);
    }

    /**
     * @notice Enable/disable token for exchange
     * @param tokenType Token type to enable/disable
     * @param enabled Whether to enable the token
     */
    function setTokenEnabled(TokenType tokenType, bool enabled)
        external
        onlyRole(CONFIG_MANAGER_ROLE)
    {
        tokenConfigs[tokenType].isEnabled = enabled;
        emit TokenConfigUpdated(
            tokenType,
            tokenConfigs[tokenType].tokenAddress,
            tokenConfigs[tokenType].exchangeFee,
            enabled
        );
    }

    /**
     * @notice Update token exchange fee
     * @param tokenType Token type to update
     * @param newFee New exchange fee in basis points
     */
    function setTokenExchangeFee(TokenType tokenType, uint newFee)
        external
        onlyRole(CONFIG_MANAGER_ROLE)
    {
        if (newFee > maxFee) {
            revert InvalidExchangeFee(newFee, maxFee);
        }

        tokenConfigs[tokenType].exchangeFee = newFee;
        emit TokenConfigUpdated(
            tokenType,
            tokenConfigs[tokenType].tokenAddress,
            newFee,
            tokenConfigs[tokenType].isEnabled
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                      OPERATIONAL FEE MANAGEMENT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Configure operational fee for a token
     * @param tokenType Token type to configure
     * @param feeRate Fee rate in basis points (100 = 1%)
     * @param feeRecipient Address to receive operational fees
     * @param isEnabled Whether operational fee is enabled
     */
    function configureOperationalFee(
        TokenType tokenType,
        uint feeRate,
        address feeRecipient,
        bool isEnabled
    ) external onlyRole(FEE_MANAGER_ROLE) {
        if (feeRate > maxFee) {
            revert InvalidOperationalFee(feeRate, maxFee);
        }

        if (isEnabled && feeRecipient == address(0)) {
            revert InvalidFeeRecipient(feeRecipient);
        }

        operationalFeeConfigs[tokenType] = OperationalFeeConfig({
            feeRate: feeRate,
            feeRecipient: feeRecipient,
            isEnabled: isEnabled
        });

        emit OperationalFeeConfigUpdated(tokenType, feeRate, feeRecipient, isEnabled);
    }

    /**
     * @notice Withdraw collected operational fees
     * @param tokenType Token type to withdraw fees for
     * @param amount Amount to withdraw (0 for all available)
     */
    function withdrawOperationalFee(TokenType tokenType, uint amount)
        external
        onlyRole(FEE_MANAGER_ROLE)
    {
        OperationalFeeConfig memory config = operationalFeeConfigs[tokenType];
        require(config.isEnabled, "Operational fee not enabled");
        require(config.feeRecipient != address(0), "Invalid fee recipient");

        uint availableFee = collectedOperationalFees[tokenType];
        uint withdrawAmount = amount == 0 ? availableFee : amount;

        if (withdrawAmount > availableFee) {
            revert InsufficientOperationalFee(tokenType, withdrawAmount, availableFee);
        }

        collectedOperationalFees[tokenType] -= withdrawAmount;

        emit OperationalFeeWithdrawn(tokenType, config.feeRecipient, withdrawAmount);

        if (tokenType == TokenType.ETH) {
            (bool sent,) = config.feeRecipient.call{ value: withdrawAmount }("");
            require(sent, "ETH transfer failed");
        } else {
            TokenConfig memory tokenConfig = tokenConfigs[tokenType];
            IERC20Extended token = IERC20Extended(tokenConfig.tokenAddress);
            require(token.transfer(config.feeRecipient, withdrawAmount), "Token transfer failed");
        }
    }

    /**
     * @notice Get operational fee configuration
     * @param tokenType Token type to get config for
     * @return config Operational fee configuration
     */
    function getOperationalFeeConfig(TokenType tokenType)
        external
        view
        returns (OperationalFeeConfig memory config)
    {
        config = operationalFeeConfigs[tokenType];
    }

    /**
     * @notice Get collected operational fee amount
     * @param tokenType Token type to get collected fee for
     * @return amount Collected operational fee amount
     */
    function getCollectedOperationalFee(TokenType tokenType) external view returns (uint amount) {
        amount = collectedOperationalFees[tokenType];
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           EXTERNAL PRICE UPDATES
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Update external price data for a token
     * @param tokenType Token type to update
     * @param price New price in USD (18 decimals)
     */
    function updateExternalPrice(TokenType tokenType, uint price)
        external
        onlyRole(PRICE_UPDATER_ROLE)
    {
        if (price == 0) {
            revert InvalidPriceUpdate(price);
        }

        externalPrices[tokenType] = ExternalPriceData({
            price: price,
            updatedAt: block.timestamp,
            updatedBy: msg.sender,
            isValid: true
        });

        emit ExternalPriceUpdated(tokenType, price, block.timestamp, msg.sender);
    }

    /**
     * @notice Update external JPY/USD price data
     * @param price New JPY/USD price (18 decimals)
     */
    function updateJPYUSDExternalPrice(uint price) external onlyRole(PRICE_UPDATER_ROLE) {
        if (price == 0) {
            revert InvalidPriceUpdate(price);
        }

        jpyUsdExternalPrice = ExternalPriceData({
            price: price,
            updatedAt: block.timestamp,
            updatedBy: msg.sender,
            isValid: true
        });

        emit JPYUSDExternalPriceUpdated(price, block.timestamp, msg.sender);
    }

    /**
     * @notice Batch update multiple token prices
     * @param tokenTypes Array of token types to update
     * @param prices Array of new prices (18 decimals)
     * @param jpyUsdPrice JPY/USD price (18 decimals)
     */
    function batchUpdatePrices(
        TokenType[] calldata tokenTypes,
        uint[] calldata prices,
        uint jpyUsdPrice
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        require(tokenTypes.length == prices.length, "Array length mismatch");

        // Update JPY/USD price if provided
        if (jpyUsdPrice > 0) {
            jpyUsdExternalPrice = ExternalPriceData({
                price: jpyUsdPrice,
                updatedAt: block.timestamp,
                updatedBy: msg.sender,
                isValid: true
            });
            emit JPYUSDExternalPriceUpdated(jpyUsdPrice, block.timestamp, msg.sender);
        }

        // Update token prices
        for (uint i = 0; i < tokenTypes.length; i++) {
            TokenType tokenType = tokenTypes[i];
            uint price = prices[i];

            if (price == 0) {
                revert InvalidPriceUpdate(price);
            }

            externalPrices[tokenType] = ExternalPriceData({
                price: price,
                updatedAt: block.timestamp,
                updatedBy: msg.sender,
                isValid: true
            });

            emit ExternalPriceUpdated(tokenType, price, block.timestamp, msg.sender);
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            EXCHANGE FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Calculate prices for exchange
     * @param tokenType Type of token to exchange
     * @return result Price calculation result
     */
    function _calculatePrices(TokenType tokenType)
        public
        view
        returns (PriceCalculationResult memory result)
    {
        // Get prices
        (uint tokenUsdPrice, PriceSource tokenPriceSource) = _getTokenPrice(tokenType);
        (uint jpyUsdPrice, PriceSource jpyPriceSource) = _getJPYUSDPrice();

        // Use the more reliable price source for the event
        bool bothOracle = tokenPriceSource == PriceSource.CHAINLINK_ORACLE
            && jpyPriceSource == PriceSource.CHAINLINK_ORACLE;
        PriceSource priceSource =
            bothOracle ? PriceSource.CHAINLINK_ORACLE : PriceSource.EXTERNAL_DATA;

        result = PriceCalculationResult({
            tokenUsdPrice: tokenUsdPrice,
            jpyUsdPrice: jpyUsdPrice,
            priceSource: priceSource
        });
    }

    /**
     * @notice Calculate token amounts with proper decimal adjustment
     * @param tokenType Type of token to exchange
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param priceResult Price calculation result
     * @return result Token amount calculation result
     */
    function _calculateTokenAmounts(
        TokenType tokenType,
        uint nlpAmount,
        PriceCalculationResult memory priceResult
    ) public view returns (TokenAmountResult memory result) {
        TokenConfig memory config = tokenConfigs[tokenType];
        OperationalFeeConfig memory opFeeConfig = operationalFeeConfigs[tokenType];

        // Enhanced calculation with improved precision
        // Calculate gross amount in USD terms (18 decimals)
        uint grossAmountInUSD = nlpAmount * priceResult.jpyUsdPrice;

        // Calculate fees in USD terms first to avoid precision loss
        uint exchangeFeeInUSD = (grossAmountInUSD * config.exchangeFee) / 10000;
        uint operationalFeeInUSD = 0;
        if (opFeeConfig.isEnabled) {
            operationalFeeInUSD = (grossAmountInUSD * opFeeConfig.feeRate) / 10000;
        }

        // Calculate net amount in USD terms
        uint netAmountInUSD = grossAmountInUSD - exchangeFeeInUSD - operationalFeeInUSD;

        // Convert to target token amount with proper decimal adjustment
        uint tokenAmount;
        uint exchangeFee;
        uint operationalFee;

        // Adjust for token decimals before division to maintain precision
        if (config.decimals != 18) {
            if (config.decimals < 18) {
                uint decimalAdjustment = 10 ** (18 - config.decimals);
                tokenAmount = netAmountInUSD / (priceResult.tokenUsdPrice * decimalAdjustment);
                exchangeFee =
                    Math.mulDiv(exchangeFeeInUSD, 1, priceResult.tokenUsdPrice * decimalAdjustment);
                operationalFee = Math.mulDiv(
                    operationalFeeInUSD, 1, priceResult.tokenUsdPrice * decimalAdjustment
                );
            } else {
                uint decimalAdjustment = 10 ** (config.decimals - 18);
                tokenAmount =
                    Math.mulDiv(netAmountInUSD, decimalAdjustment, priceResult.tokenUsdPrice);
                exchangeFee =
                    Math.mulDiv(exchangeFeeInUSD, decimalAdjustment, priceResult.tokenUsdPrice);
                operationalFee =
                    Math.mulDiv(operationalFeeInUSD, decimalAdjustment, priceResult.tokenUsdPrice);
            }
        } else {
            tokenAmount = netAmountInUSD / priceResult.tokenUsdPrice;
            exchangeFee = exchangeFeeInUSD / priceResult.tokenUsdPrice;
            operationalFee = operationalFeeInUSD / priceResult.tokenUsdPrice;
        }

        result = TokenAmountResult({
            tokenAmount: tokenAmount,
            exchangeFee: exchangeFee,
            operationalFee: operationalFee
        });
    }

    /**
     * @notice Update statistics and user records
     * @param tokenType Type of token
     * @param nlpAmount Amount of NLP tokens exchanged
     * @param user User address
     * @param amountResult Token amount calculation result
     */
    function _updateStatistics(
        TokenType tokenType,
        uint nlpAmount,
        address user,
        TokenAmountResult memory amountResult
    ) internal {
        // Update statistics (CEI pattern)
        tokenStats[tokenType].totalExchanged += nlpAmount;
        tokenStats[tokenType].totalTokenSent += amountResult.tokenAmount;
        tokenStats[tokenType].totalExchangeFeeCollected += amountResult.exchangeFee;
        tokenStats[tokenType].totalOperationalFeeCollected += amountResult.operationalFee;
        tokenStats[tokenType].exchangeCount += 1;

        // Update operational fee collection
        if (amountResult.operationalFee > 0) {
            collectedOperationalFees[tokenType] += amountResult.operationalFee;
        }

        // Update user records
        userExchangeAmount[user][tokenType] += nlpAmount;
        userTokenReceived[user][tokenType] += amountResult.tokenAmount;
    }

    /**
     * @notice Execute token transfer and emit events
     * @param tokenType Type of token to transfer
     * @param nlpAmount Amount of NLP tokens exchanged
     * @param user User address
     * @param relayer Relayer address (address(0) for direct exchange)
     * @param priceResult Price calculation result
     * @param amountResult Token amount calculation result
     */
    function _executeTokenTransfer(
        TokenType tokenType,
        uint nlpAmount,
        address user,
        address relayer,
        PriceCalculationResult memory priceResult,
        TokenAmountResult memory amountResult
    ) internal {
        // Burn NLP tokens
        try nlpToken.burnFrom(user, nlpAmount) {
            // Burn successful
        } catch {
            revert ExchangeFailed(user, nlpAmount);
        }

        // Send tokens to user
        if (tokenType == TokenType.ETH) {
            Address.sendValue(payable(user), amountResult.tokenAmount);
        } else {
            TokenConfig memory config = tokenConfigs[tokenType];
            IERC20Extended token = IERC20Extended(config.tokenAddress);
            require(token.transfer(user, amountResult.tokenAmount), "Token transfer failed");
        }

        // Emit appropriate event
        if (relayer == address(0)) {
            emit ExchangeExecuted(
                user,
                tokenType,
                nlpAmount,
                amountResult.tokenAmount,
                priceResult.tokenUsdPrice,
                priceResult.jpyUsdPrice,
                amountResult.exchangeFee,
                amountResult.operationalFee,
                priceResult.priceSource
            );
        } else {
            emit GaslessExchangeExecuted(
                user,
                relayer,
                tokenType,
                nlpAmount,
                amountResult.tokenAmount,
                priceResult.tokenUsdPrice,
                priceResult.jpyUsdPrice,
                amountResult.exchangeFee,
                amountResult.operationalFee,
                priceResult.priceSource
            );
        }
    }

    /**
     * @notice Exchange NLP tokens for specified token using permit for gasless operation
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @param user User address (token owner)
     */
    function exchangeNLPWithPermit(
        TokenType tokenType,
        uint nlpAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address user
    ) external nonReentrant whenNotPaused {
        if (nlpAmount == 0) {
            revert InvalidExchangeAmount(nlpAmount);
        }

        if (user == address(0)) {
            revert InvalidUser(user);
        }

        TokenConfig memory config = tokenConfigs[tokenType];
        if (!config.isEnabled) {
            revert TokenNotEnabled(tokenType);
        }

        // Execute permit
        try nlpToken.permit(user, address(this), nlpAmount, deadline, v, r, s) {
            // Permit successful
        } catch {
            revert PermitFailed(user, nlpAmount, deadline);
        }

        // Execute exchange
        _executeExchange(tokenType, nlpAmount, user, msg.sender);
    }

    /**
     * @notice Exchange NLP tokens for specified token
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     */
    function exchangeNLP(TokenType tokenType, uint nlpAmount) external nonReentrant whenNotPaused {
        if (nlpAmount == 0) {
            revert InvalidExchangeAmount(nlpAmount);
        }

        TokenConfig memory config = tokenConfigs[tokenType];
        if (!config.isEnabled) {
            revert TokenNotEnabled(tokenType);
        }

        _executeExchange(tokenType, nlpAmount, msg.sender, address(0));
    }

    /**
     * @notice Internal function to execute exchange
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param user User address
     * @param relayer Relayer address (address(0) for direct exchange)
     */
    function _executeExchange(TokenType tokenType, uint nlpAmount, address user, address relayer)
        internal
    {
        // Calculate prices
        PriceCalculationResult memory priceResult = _calculatePrices(tokenType);

        // Calculate token amounts
        TokenAmountResult memory amountResult =
            _calculateTokenAmounts(tokenType, nlpAmount, priceResult);

        // Check balance
        if (tokenType == TokenType.ETH) {
            if (address(this).balance < amountResult.tokenAmount) {
                revert InsufficientBalance(
                    tokenType, amountResult.tokenAmount, address(this).balance
                );
            }
        } else {
            TokenConfig memory config = tokenConfigs[tokenType];
            IERC20Extended token = IERC20Extended(config.tokenAddress);
            if (token.balanceOf(address(this)) < amountResult.tokenAmount) {
                revert InsufficientBalance(
                    tokenType, amountResult.tokenAmount, token.balanceOf(address(this))
                );
            }
        }

        // Update statistics (CEI pattern)
        _updateStatistics(tokenType, nlpAmount, user, amountResult);

        // Execute token transfer and emit events
        _executeTokenTransfer(tokenType, nlpAmount, user, relayer, priceResult, amountResult);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              PRICE FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get token price from best available source
     * @param tokenType Token type to get price for
     * @return price Token price in USD (18 decimals)
     * @return source Price data source used
     */
    function _getTokenPrice(TokenType tokenType)
        public
        view
        returns (uint price, PriceSource source)
    {
        TokenConfig memory config = tokenConfigs[tokenType];

        // Try Chainlink oracle first
        if (config.hasOracle) {
            try this.getOraclePrice(address(config.priceFeed), 18) returns (uint oraclePrice) {
                return (oraclePrice, PriceSource.CHAINLINK_ORACLE);
            } catch {
                // Oracle failed, fall back to external data
            }
        }

        // Use external data
        ExternalPriceData memory externalData = externalPrices[tokenType];
        if (
            externalData.isValid
                && block.timestamp - externalData.updatedAt <= PRICE_STALENESS_THRESHOLD
        ) {
            return (externalData.price, PriceSource.EXTERNAL_DATA);
        }

        // No valid price data available
        revert NoPriceDataAvailable(tokenType);
    }

    /**
     * @notice Get JPY/USD price from best available source
     * @return price JPY/USD price (18 decimals)
     * @return source Price data source used
     */
    function _getJPYUSDPrice() public view returns (uint price, PriceSource source) {
        // Try Chainlink oracle first
        if (hasJpyOracle) {
            try this.getOraclePrice(address(jpyUsdPriceFeed), 18) returns (uint oraclePrice) {
                return (oraclePrice, PriceSource.CHAINLINK_ORACLE);
            } catch {
                // Oracle failed, fall back to external data
            }
        }

        // Use external data
        ExternalPriceData memory externalData = jpyUsdExternalPrice;
        if (
            externalData.isValid
                && block.timestamp - externalData.updatedAt <= PRICE_STALENESS_THRESHOLD
        ) {
            return (externalData.price, PriceSource.EXTERNAL_DATA);
        }

        // No valid price data available
        revert NoPriceDataAvailable(TokenType.ETH); // Use ETH as placeholder for JPY
    }

    /**
     * @notice Get price from Chainlink oracle (external function to enable try/catch)
     * @param priceFeed Price feed address
     * @param targetDecimals Target decimals for price
     * @return price Price normalized to target decimals
     */
    function getOraclePrice(address priceFeed, uint8 targetDecimals)
        external
        view
        returns (uint price)
    {
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeed);

        (uint80 roundId, int priceInt, uint startedAt, uint updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        // Enhanced validation as per security audit recommendations
        if (priceInt <= 0) {
            revert InvalidPriceData(priceInt);
        }

        if (updatedAt == 0) {
            revert InvalidPriceData(priceInt);
        }

        if (roundId == 0) {
            revert InvalidPriceData(priceInt);
        }

        // Check for stale price data
        if (answeredInRound < roundId) {
            revert PriceDataStale(updatedAt, PRICE_STALENESS_THRESHOLD);
        }

        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
            revert PriceDataStale(updatedAt, PRICE_STALENESS_THRESHOLD);
        }

        // Check if the round is complete
        if (startedAt == 0) {
            revert InvalidPriceData(priceInt);
        }

        // Convert to target decimals
        uint8 feedDecimals = feed.decimals();
        if (feedDecimals == targetDecimals) {
            price = uint(priceInt);
        } else if (feedDecimals < targetDecimals) {
            price = uint(priceInt) * (10 ** (targetDecimals - feedDecimals));
        } else {
            price = uint(priceInt) / (10 ** (feedDecimals - targetDecimals));
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get exchange quote for specified token
     * @param tokenType Token type to get quote for
     * @param nlpAmount Amount of NLP tokens to exchange
     * @return tokenAmount Amount of tokens that would be received
     * @return tokenUsdRate Token/USD price used
     * @return jpyUsdRate JPY/USD price used
     * @return exchangeFee Exchange fee amount in tokens
     * @return operationalFee Operational fee amount in tokens
     * @return priceSource Price data source used
     */
    function getExchangeQuote(TokenType tokenType, uint nlpAmount)
        external
        view
        returns (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee,
            PriceSource priceSource
        )
    {
        if (nlpAmount == 0 || !tokenConfigs[tokenType].isEnabled) {
            return (0, 0, 0, 0, 0, PriceSource.FALLBACK);
        }

        try this._calculatePrices(tokenType) returns (PriceCalculationResult memory priceResult) {
            try this._calculateTokenAmounts(tokenType, nlpAmount, priceResult) returns (
                TokenAmountResult memory amountResult
            ) {
                tokenAmount = amountResult.tokenAmount;
                tokenUsdRate = priceResult.tokenUsdPrice;
                jpyUsdRate = priceResult.jpyUsdPrice;
                exchangeFee = amountResult.exchangeFee;
                operationalFee = amountResult.operationalFee;
                priceSource = priceResult.priceSource;
            } catch {
                return (0, 0, 0, 0, 0, PriceSource.FALLBACK);
            }
        } catch {
            return (0, 0, 0, 0, 0, PriceSource.FALLBACK);
        }
    }

    /**
     * @notice Get current contract status
     * @return ethBalance Current ETH balance
     * @return isPaused Whether contract is paused
     * @return jpyUsdPrice Current JPY/USD price
     * @return jpyPriceSource JPY/USD price source
     */
    function getContractStatus()
        external
        view
        returns (uint ethBalance, bool isPaused, uint jpyUsdPrice, PriceSource jpyPriceSource)
    {
        ethBalance = address(this).balance;
        isPaused = paused();

        try this._getJPYUSDPrice() returns (uint price, PriceSource source) {
            jpyUsdPrice = price;
            jpyPriceSource = source;
        } catch {
            jpyUsdPrice = 0;
            jpyPriceSource = PriceSource.FALLBACK;
        }
    }

    /**
     * @notice Get token configuration
     * @param tokenType Token type to get config for
     * @return config Token configuration
     */
    function getTokenConfig(TokenType tokenType)
        external
        view
        returns (TokenConfig memory config)
    {
        config = tokenConfigs[tokenType];
    }

    /**
     * @notice Get token statistics
     * @param tokenType Token type to get stats for
     * @return stats Token statistics
     */
    function getTokenStats(TokenType tokenType) external view returns (TokenStats memory stats) {
        stats = tokenStats[tokenType];
    }

    /**
     * @notice Get user exchange history for specific token
     * @param user User address
     * @param tokenType Token type
     * @return exchangedNLP Total NLP exchanged for this token
     * @return receivedTokens Total tokens received
     */
    function getUserExchangeHistory(address user, TokenType tokenType)
        external
        view
        returns (uint exchangedNLP, uint receivedTokens)
    {
        exchangedNLP = userExchangeAmount[user][tokenType];
        receivedTokens = userTokenReceived[user][tokenType];
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ADMIN FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(EMERGENCY_MANAGER_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal of ETH to treasury
     * @param amount Amount to withdraw (0 for all)
     */
    function emergencyWithdrawETH(uint amount)
        external
        whenPaused
        nonReentrant
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        require(treasury != address(0), "Treasury not set");

        uint balance = address(this).balance;
        uint withdrawAmount = amount == 0 ? balance : amount;

        if (withdrawAmount > balance) {
            revert InsufficientBalance(TokenType.ETH, withdrawAmount, balance);
        }

        emit EmergencyWithdraw(TokenType.ETH, treasury, withdrawAmount);
        Address.sendValue(payable(treasury), withdrawAmount);
    }

    /**
     * @notice Emergency withdrawal of tokens to treasury
     * @param tokenType Token type to withdraw
     * @param amount Amount to withdraw (0 for all)
     */
    function emergencyWithdrawToken(TokenType tokenType, uint amount)
        external
        whenPaused
        nonReentrant
        onlyRole(EMERGENCY_MANAGER_ROLE)
    {
        require(treasury != address(0), "Treasury not set");
        require(tokenType != TokenType.ETH, "Use emergencyWithdrawETH for ETH");

        TokenConfig memory config = tokenConfigs[tokenType];
        require(config.tokenAddress != address(0), "Invalid token config");

        IERC20Extended token = IERC20Extended(config.tokenAddress);
        uint balance = token.balanceOf(address(this));
        uint withdrawAmount = amount == 0 ? balance : amount;

        if (withdrawAmount > balance) {
            revert InsufficientBalance(tokenType, withdrawAmount, balance);
        }

        emit EmergencyWithdraw(tokenType, treasury, withdrawAmount);
        require(token.transfer(treasury, withdrawAmount), "Token transfer failed");
    }

    /**
     * @notice Set treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newTreasury != address(0), "Treasury cannot be zero address");
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /**
     * @notice Update the maximum fee rate
     * @param newMaxFee New maximum fee rate in basis points (100 = 1%)
     */
    function updateMaxFee(uint newMaxFee) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newMaxFee > ABSOLUTE_MAX_FEE) {
            // Assuming 100% is the absolute max
            revert InvalidMaxFee(newMaxFee, ABSOLUTE_MAX_FEE);
        }
        uint oldMaxFee = maxFee;
        maxFee = newMaxFee;
        emit MaxFeeUpdated(oldMaxFee, newMaxFee, msg.sender);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              RECEIVE FUNCTION
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Receive ETH deposits
     */
    receive() external payable {
        // Allow ETH deposits for exchange operations
    }
}
