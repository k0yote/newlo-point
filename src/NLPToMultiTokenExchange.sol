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
 *      - Configurable NLP to JPY exchange rate
 *      - Multi-token support (ETH, USDC, USDT)
 *      - Oracle-based price management with JPY/USD external data support
 *      - Role-based access control for different administrative functions
 *      - Configurable exchange fees per token
 *      - Operational fee collection system
 *      - Emergency pause functionality
 *      - Administrative fund management
 *      - Comprehensive exchange statistics
 *      - Gasless exchange using permit
 *
 * @dev Exchange Formula:
 *      1. NLP → JPY (configurable rate using numerator/denominator)
 *      2. JPY → USD using JPY/USD price feed (oracle or external)
 *      3. USD → Target Token using token/USD price feed
 *      Formula: tokenAmount = (nlpAmount * nlpToJpyRate / denominator * jpyUsdPrice) / tokenUsdPrice - exchangeFee - operationalFee
 *
 * @dev Price Data Sources:
 *      - Chainlink Oracle for ETH/USDC/USDT (when available)
 *      - External JPY/USD data in Chainlink format (for Soneium environment)
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

    /* ═══════════════════════════════════════════════════════════════════════
                                  STRUCTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Round data structure matching Chainlink's latestRoundData
    struct RoundData {
        uint80 roundId;
        int answer;
        uint startedAt;
        uint updatedAt;
        uint80 answeredInRound;
    }

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

    /// @notice Chainlink ETH/USD price feed (always required)
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    /// @notice Chainlink JPY/USD price feed (updatable, address(0) if not available)
    AggregatorV3Interface public jpyUsdPriceFeed;

    /// @notice Chainlink USDC/USD price feed (updatable, address(0) if not available)
    AggregatorV3Interface public usdcUsdPriceFeed;

    /// @notice Chainlink USDT/USD price feed (updatable, address(0) if not available)
    AggregatorV3Interface public usdtUsdPriceFeed;

    /// @notice External JPY/USD round data (used when jpyUsdPriceFeed is address(0))
    RoundData public jpyUsdExternalRoundData;

    /// @notice Treasury address for emergency withdrawals
    address public treasury;

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Exchange rate numerator: NLP to JPY (90 for 0.9 JPY per NLP)
    uint public NLP_TO_JPY_RATE = 90;

    /// @notice Absolute maximum fee rate (100%)
    uint public constant ABSOLUTE_MAX_FEE = 10000;

    /// @notice Maximum fee rate (5% initially, configurable)
    uint public maxFee = 500;

    /// @notice Rate denominator for NLP to JPY conversion (e.g., 100 for 0.9 JPY per NLP)
    uint public constant NLP_TO_JPY_RATE_DENOMINATOR = 100;

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
        uint operationalFee
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
        uint operationalFee
    );

    /// @notice Emitted when token configuration is updated
    event TokenConfigUpdated(
        TokenType indexed tokenType, address tokenAddress, uint exchangeFee, bool isEnabled
    );

    /// @notice Emitted when operational fee configuration is updated
    event OperationalFeeConfigUpdated(
        TokenType indexed tokenType, uint feeRate, address feeRecipient, bool isEnabled
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

    /// @notice Emitted when JPY/USD oracle address is updated
    event JPYUSDOracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when USDC/USD oracle address is updated
    event USDCUSDOracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when USDT/USD oracle address is updated
    event USDTUSDOracleUpdated(address indexed oldOracle, address indexed newOracle);

    /// @notice Emitted when NLP to JPY exchange rate is updated
    event NLPToJPYRateUpdated(uint oldRate, uint newRate, address updatedBy);

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
    error NoPriceDataAvailable(TokenType tokenType);
    error InvalidFeeRecipient(address recipient);
    error InsufficientOperationalFee(TokenType tokenType, uint required, uint available);
    error InvalidMaxFee(uint fee, uint absoluteMaxFee);
    error ZeroAddress();
    error InvalidRateValue(uint rate);
    error OperationalFeeNotEnabled();
    error TransferFailed();
    error InvalidPriceAnswer(int answer);
    error InvalidTimestamp(uint timestamp);
    error TreasuryNotSet();
    error InvalidTokenType(TokenType tokenType);
    error InvalidTokenConfig();
    error SlippageToleranceExceeded(uint expectedAmount, uint actualAmount, uint minAmount);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the multi-token exchange contract
     * @param _nlpToken NewLo Point token contract address
     * @param _ethUsdPriceFeed Chainlink ETH/USD price feed address (required)
     * @param _jpyUsdPriceFeed Chainlink JPY/USD price feed address (address(0) if not available)
     * @param _usdcUsdPriceFeed Chainlink USDC/USD price feed address (address(0) if not available)
     * @param _usdtUsdPriceFeed Chainlink USDT/USD price feed address (address(0) if not available)
     * @param _initialAdmin Initial admin of the contract
     */
    constructor(
        address _nlpToken,
        address _ethUsdPriceFeed,
        address _jpyUsdPriceFeed,
        address _usdcUsdPriceFeed,
        address _usdtUsdPriceFeed,
        address _initialAdmin
    ) {
        if (_nlpToken == address(0)) revert ZeroAddress();
        if (_ethUsdPriceFeed == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();

        nlpToken = IERC20Extended(_nlpToken);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);

        if (_jpyUsdPriceFeed != address(0)) {
            jpyUsdPriceFeed = AggregatorV3Interface(_jpyUsdPriceFeed);
        }

        if (_usdcUsdPriceFeed != address(0)) {
            usdcUsdPriceFeed = AggregatorV3Interface(_usdcUsdPriceFeed);
        }

        if (_usdtUsdPriceFeed != address(0)) {
            usdtUsdPriceFeed = AggregatorV3Interface(_usdtUsdPriceFeed);
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
        if (!config.isEnabled) revert OperationalFeeNotEnabled();
        if (config.feeRecipient == address(0)) revert InvalidFeeRecipient(config.feeRecipient);

        uint availableFee = collectedOperationalFees[tokenType];
        uint withdrawAmount = amount == 0 ? availableFee : amount;

        if (withdrawAmount > availableFee) {
            revert InsufficientOperationalFee(tokenType, withdrawAmount, availableFee);
        }

        collectedOperationalFees[tokenType] -= withdrawAmount;

        emit OperationalFeeWithdrawn(tokenType, config.feeRecipient, withdrawAmount);

        if (tokenType == TokenType.ETH) {
            (bool sent,) = config.feeRecipient.call{ value: withdrawAmount }("");
            if (!sent) revert TransferFailed();
        } else {
            TokenConfig memory tokenConfig = tokenConfigs[tokenType];
            IERC20Extended token = IERC20Extended(tokenConfig.tokenAddress);
            if (!token.transfer(config.feeRecipient, withdrawAmount)) revert TransferFailed();
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
     * @notice Update JPY/USD external data in latestRoundData format (recommended for Soneium)
     * @param roundId Round ID
     * @param answer Price answer (8 decimals, like Chainlink format)
     * @param startedAt Round start timestamp
     * @param updatedAt Round update timestamp
     * @param answeredInRound Answered in round
     * @dev This function provides JPY/USD data in the same format as Chainlink oracles
     */
    function updateJPYUSDRoundData(
        uint80 roundId,
        int answer,
        uint startedAt,
        uint updatedAt,
        uint80 answeredInRound
    ) external onlyRole(PRICE_UPDATER_ROLE) {
        if (answer <= 0) revert InvalidPriceAnswer(answer);
        if (updatedAt == 0) revert InvalidTimestamp(updatedAt);
        if (startedAt == 0) revert InvalidTimestamp(startedAt);

        jpyUsdExternalRoundData = RoundData({
            roundId: roundId,
            answer: answer,
            startedAt: startedAt,
            updatedAt: updatedAt,
            answeredInRound: answeredInRound
        });

        emit JPYUSDExternalPriceUpdated(uint(answer), updatedAt, msg.sender);
    }

    /**
     * @notice Update JPY/USD oracle address (for future oracle support)
     * @param newJpyUsdPriceFeed New JPY/USD price feed address (address(0) to disable oracle)
     * @dev This allows updating the JPY/USD oracle when it becomes available on Soneium
     */
    function updateJPYUSDOracle(address newJpyUsdPriceFeed) external onlyRole(DEFAULT_ADMIN_ROLE) {
        address oldOracle = address(jpyUsdPriceFeed);

        if (newJpyUsdPriceFeed != address(0)) {
            jpyUsdPriceFeed = AggregatorV3Interface(newJpyUsdPriceFeed);
        } else {
            jpyUsdPriceFeed = AggregatorV3Interface(address(0));
        }

        emit JPYUSDOracleUpdated(oldOracle, newJpyUsdPriceFeed);
    }

    /**
     * @notice Update USDC/USD oracle address
     * @param newUsdcUsdPriceFeed New USDC/USD price feed address (address(0) to disable oracle)
     * @dev This allows updating the USDC/USD oracle address
     */
    function updateUSDCUSDOracle(address newUsdcUsdPriceFeed)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        address oldOracle = address(usdcUsdPriceFeed);

        if (newUsdcUsdPriceFeed != address(0)) {
            usdcUsdPriceFeed = AggregatorV3Interface(newUsdcUsdPriceFeed);
        } else {
            usdcUsdPriceFeed = AggregatorV3Interface(address(0));
        }

        emit USDCUSDOracleUpdated(oldOracle, newUsdcUsdPriceFeed);
    }

    /**
     * @notice Update USDT/USD oracle address
     * @param newUsdtUsdPriceFeed New USDT/USD price feed address (address(0) to disable oracle)
     * @dev This allows updating the USDT/USD oracle address
     */
    function updateUSDTUSDOracle(address newUsdtUsdPriceFeed)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        address oldOracle = address(usdtUsdPriceFeed);

        if (newUsdtUsdPriceFeed != address(0)) {
            usdtUsdPriceFeed = AggregatorV3Interface(newUsdtUsdPriceFeed);
        } else {
            usdtUsdPriceFeed = AggregatorV3Interface(address(0));
        }

        emit USDTUSDOracleUpdated(oldOracle, newUsdtUsdPriceFeed);
    }

    /**
     * @notice Update the NLP to JPY exchange rate numerator
     * @param newRate New exchange rate numerator (e.g., 90 for 0.9 JPY per NLP when denominator is 100)
     * @dev The actual rate is calculated as: newRate / NLP_TO_JPY_RATE_DENOMINATOR
     */
    function updateNLPToJPYRate(uint newRate) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newRate == 0) revert InvalidRateValue(newRate);
        uint oldRate = NLP_TO_JPY_RATE;
        NLP_TO_JPY_RATE = newRate;
        emit NLPToJPYRateUpdated(oldRate, newRate, msg.sender);
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
        // Get prices using optimized functions
        uint tokenUsdPrice = _getTokenPriceOptimized(tokenType);
        uint jpyUsdPrice = _getJPYUSDPriceOptimized();

        result = PriceCalculationResult({ tokenUsdPrice: tokenUsdPrice, jpyUsdPrice: jpyUsdPrice });
    }

    /**
     * @notice Calculate token amounts with optimized memory usage
     * @param tokenType Type of token to exchange
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param tokenUsdPrice Token price in USD (18 decimals)
     * @param jpyUsdPrice JPY/USD price (18 decimals)
     * @return result Token amount calculation result
     */
    function _calculateTokenAmountsOptimized(
        TokenType tokenType,
        uint nlpAmount,
        uint tokenUsdPrice,
        uint jpyUsdPrice
    ) internal view returns (TokenAmountResult memory result) {
        // Load config once and cache relevant values
        TokenConfig storage config = tokenConfigs[tokenType];
        uint exchangeFeeRate = config.exchangeFee;
        uint8 tokenDecimals = config.decimals;

        // Load operational fee config
        OperationalFeeConfig storage opFeeConfig = operationalFeeConfigs[tokenType];
        uint operationalFeeRate = opFeeConfig.isEnabled ? opFeeConfig.feeRate : 0;

        // Calculate JPY amount using cached NLP_TO_JPY_RATE
        uint jpyAmount;
        unchecked {
            jpyAmount = Math.mulDiv(nlpAmount, NLP_TO_JPY_RATE, NLP_TO_JPY_RATE_DENOMINATOR);
        }

        // Calculate gross USD amount
        uint grossAmountInUSD = Math.mulDiv(jpyAmount, jpyUsdPrice, 1e18);

        // Calculate total fee rate to reduce operations
        uint totalFeeRate = exchangeFeeRate + operationalFeeRate;
        uint totalFeeInUSD = (grossAmountInUSD * totalFeeRate) / 10000;

        // Calculate individual fees
        uint exchangeFeeInUSD = (grossAmountInUSD * exchangeFeeRate) / 10000;
        uint operationalFeeInUSD = totalFeeInUSD - exchangeFeeInUSD;

        // Calculate net amount
        uint netAmountInUSD = grossAmountInUSD - totalFeeInUSD;

        // Optimized token amount calculation
        if (tokenDecimals == 18) {
            // 18 decimals - direct calculation
            result.tokenAmount = Math.mulDiv(netAmountInUSD, 1e18, tokenUsdPrice);
            result.exchangeFee = Math.mulDiv(exchangeFeeInUSD, 1e18, tokenUsdPrice);
            result.operationalFee = Math.mulDiv(operationalFeeInUSD, 1e18, tokenUsdPrice);
        } else {
            // Non-18 decimals - use cached decimal multiplier
            uint decimalMultiplier = 10 ** tokenDecimals;
            result.tokenAmount = Math.mulDiv(netAmountInUSD, decimalMultiplier, tokenUsdPrice);
            result.exchangeFee = Math.mulDiv(exchangeFeeInUSD, decimalMultiplier, tokenUsdPrice);
            result.operationalFee =
                Math.mulDiv(operationalFeeInUSD, decimalMultiplier, tokenUsdPrice);
        }
    }

    /**
     * @notice Optimized execute exchange function
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param user User address
     * @param relayer Relayer address (address(0) for direct exchange)
     * @param minAmountOut Minimum amount of tokens to receive
     */
    function _executeExchangeOptimized(
        TokenType tokenType,
        uint nlpAmount,
        address user,
        address relayer,
        uint minAmountOut
    ) internal {
        // Get prices in one call
        uint tokenUsdPrice = _getTokenPriceOptimized(tokenType);
        uint jpyUsdPrice = _getJPYUSDPriceOptimized();

        // Calculate token amounts with optimized function
        TokenAmountResult memory amountResult =
            _calculateTokenAmountsOptimized(tokenType, nlpAmount, tokenUsdPrice, jpyUsdPrice);

        // Slippage protection check
        if (minAmountOut > 0 && amountResult.tokenAmount < minAmountOut) {
            revert SlippageToleranceExceeded(
                amountResult.tokenAmount, amountResult.tokenAmount, minAmountOut
            );
        }

        // Optimized balance check using storage reference
        if (tokenType == TokenType.ETH) {
            if (address(this).balance < amountResult.tokenAmount) {
                revert InsufficientBalance(
                    tokenType, amountResult.tokenAmount, address(this).balance
                );
            }
        } else {
            // Load token address once from storage
            address tokenAddress = tokenConfigs[tokenType].tokenAddress;
            IERC20Extended token = IERC20Extended(tokenAddress);
            uint contractBalance = token.balanceOf(address(this));
            if (contractBalance < amountResult.tokenAmount) {
                revert InsufficientBalance(tokenType, amountResult.tokenAmount, contractBalance);
            }
        }

        // Update statistics efficiently using storage references
        TokenStats storage stats = tokenStats[tokenType];
        unchecked {
            stats.totalExchanged += nlpAmount;
            stats.totalTokenSent += amountResult.tokenAmount;
            stats.totalExchangeFeeCollected += amountResult.exchangeFee;
            stats.totalOperationalFeeCollected += amountResult.operationalFee;
            stats.exchangeCount += 1;
        }

        // Update operational fee collection if applicable
        if (amountResult.operationalFee > 0) {
            unchecked {
                collectedOperationalFees[tokenType] += amountResult.operationalFee;
            }
        }

        // Update user records efficiently
        unchecked {
            userExchangeAmount[user][tokenType] += nlpAmount;
            userTokenReceived[user][tokenType] += amountResult.tokenAmount;
        }

        // Execute token transfer
        _executeTokenTransferOptimized(
            tokenType, nlpAmount, user, relayer, tokenUsdPrice, jpyUsdPrice, amountResult
        );
    }

    /**
     * @notice Optimized token transfer function
     */
    function _executeTokenTransferOptimized(
        TokenType tokenType,
        uint nlpAmount,
        address user,
        address relayer,
        uint tokenUsdPrice,
        uint jpyUsdPrice,
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
            // Use cached token address to avoid storage read
            address tokenAddress = tokenConfigs[tokenType].tokenAddress;
            IERC20Extended token = IERC20Extended(tokenAddress);
            if (!token.transfer(user, amountResult.tokenAmount)) revert TransferFailed();
        }

        // Emit appropriate event
        if (relayer == address(0)) {
            emit ExchangeExecuted(
                user,
                tokenType,
                nlpAmount,
                amountResult.tokenAmount,
                tokenUsdPrice,
                jpyUsdPrice,
                amountResult.exchangeFee,
                amountResult.operationalFee
            );
        } else {
            emit GaslessExchangeExecuted(
                user,
                relayer,
                tokenType,
                nlpAmount,
                amountResult.tokenAmount,
                tokenUsdPrice,
                jpyUsdPrice,
                amountResult.exchangeFee,
                amountResult.operationalFee
            );
        }
    }

    /**
     * @notice Exchange NLP tokens for specified token (legacy function without slippage protection)
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @dev This function is kept for backward compatibility. Consider using exchangeNLPWithSlippage for better protection.
     */
    function exchangeNLP(TokenType tokenType, uint nlpAmount) external nonReentrant whenNotPaused {
        if (nlpAmount == 0) {
            revert InvalidExchangeAmount(nlpAmount);
        }

        TokenConfig memory config = tokenConfigs[tokenType];
        if (!config.isEnabled) {
            revert TokenNotEnabled(tokenType);
        }

        _executeExchange(tokenType, nlpAmount, msg.sender, address(0), 0);
    }

    /**
     * @notice Exchange NLP tokens for specified token with slippage protection
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param minAmountOut Minimum amount of tokens to receive (slippage protection)
     */
    function exchangeNLPWithSlippage(TokenType tokenType, uint nlpAmount, uint minAmountOut)
        external
        nonReentrant
        whenNotPaused
    {
        if (nlpAmount == 0) {
            revert InvalidExchangeAmount(nlpAmount);
        }

        TokenConfig memory config = tokenConfigs[tokenType];
        if (!config.isEnabled) {
            revert TokenNotEnabled(tokenType);
        }

        _executeExchange(tokenType, nlpAmount, msg.sender, address(0), minAmountOut);
    }

    /**
     * @notice Exchange NLP tokens using permit (legacy function without slippage protection)
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @param user User address (token owner)
     * @dev This function is kept for backward compatibility. Consider using exchangeNLPWithPermitAndSlippage for better protection.
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
        _executeExchange(tokenType, nlpAmount, user, msg.sender, 0);
    }

    /**
     * @notice Exchange NLP tokens using permit with slippage protection
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param minAmountOut Minimum amount of tokens to receive (slippage protection)
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @param user User address (token owner)
     */
    function exchangeNLPWithPermitAndSlippage(
        TokenType tokenType,
        uint nlpAmount,
        uint minAmountOut,
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
        _executeExchange(tokenType, nlpAmount, user, msg.sender, minAmountOut);
    }

    /**
     * @notice Internal function to execute exchange with slippage protection (original version)
     * @param tokenType Type of token to receive
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param user User address
     * @param relayer Relayer address (address(0) for direct exchange)
     * @param minAmountOut Minimum amount of tokens to receive
     */
    function _executeExchange(
        TokenType tokenType,
        uint nlpAmount,
        address user,
        address relayer,
        uint minAmountOut
    ) internal {
        // Calculate prices
        PriceCalculationResult memory priceResult = _calculatePrices(tokenType);

        // Calculate token amounts
        TokenAmountResult memory amountResult =
            _calculateTokenAmounts(tokenType, nlpAmount, priceResult);

        // Slippage protection check (skip if minAmountOut is 0 for legacy compatibility)
        if (minAmountOut > 0 && amountResult.tokenAmount < minAmountOut) {
            revert SlippageToleranceExceeded(
                amountResult.tokenAmount, amountResult.tokenAmount, minAmountOut
            );
        }

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

    /**
     * @notice Calculate token amounts with proper decimal adjustment (original version)
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
        // First apply NLP to JPY conversion rate with decimal support
        // Formula: jpyAmount = (nlpAmount * NLP_TO_JPY_RATE) / NLP_TO_JPY_RATE_DENOMINATOR
        uint jpyAmount = Math.mulDiv(nlpAmount, NLP_TO_JPY_RATE, NLP_TO_JPY_RATE_DENOMINATOR);
        // JPY amount (18 decimals) * JPY/USD price (18 decimals) = 36 decimals
        // We need to normalize to 18 decimals (USD terms)
        uint grossAmountInUSD = Math.mulDiv(jpyAmount, priceResult.jpyUsdPrice, 1e18);

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

        // Use Math.mulDiv to maintain precision for small values
        // Adjust for token decimals before division to maintain precision
        if (config.decimals != 18) {
            // For all non-18 decimal tokens
            // netAmountInUSD (18 decimals) / tokenUsdPrice (18 decimals) * 10^tokenDecimals = token amount
            tokenAmount =
                Math.mulDiv(netAmountInUSD, 10 ** config.decimals, priceResult.tokenUsdPrice);
            exchangeFee =
                Math.mulDiv(exchangeFeeInUSD, 10 ** config.decimals, priceResult.tokenUsdPrice);
            operationalFee =
                Math.mulDiv(operationalFeeInUSD, 10 ** config.decimals, priceResult.tokenUsdPrice);
        } else {
            // For 18 decimals tokens, use Math.mulDiv for better precision
            // netAmountInUSD (18 decimals) / tokenUsdPrice (18 decimals) * 10^18 = token amount (18 decimals)
            tokenAmount = Math.mulDiv(netAmountInUSD, 1e18, priceResult.tokenUsdPrice);
            exchangeFee = Math.mulDiv(exchangeFeeInUSD, 1e18, priceResult.tokenUsdPrice);
            operationalFee = Math.mulDiv(operationalFeeInUSD, 1e18, priceResult.tokenUsdPrice);
        }

        result = TokenAmountResult({
            tokenAmount: tokenAmount,
            exchangeFee: exchangeFee,
            operationalFee: operationalFee
        });
    }

    /**
     * @notice Update statistics and user records (original version)
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
     * @notice Execute token transfer and emit events (original version)
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
            if (!token.transfer(user, amountResult.tokenAmount)) revert TransferFailed();
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
                amountResult.operationalFee
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
                amountResult.operationalFee
            );
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              PRICE FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get token price from oracle (internal optimized version)
     * @param tokenType Token type to get price for
     * @return price Token price in USD (18 decimals)
     */
    function _getTokenPriceOptimized(TokenType tokenType) internal view returns (uint price) {
        // Optimized conditional logic to reduce gas
        if (tokenType == TokenType.ETH) {
            return _getOraclePriceInternal(address(ethUsdPriceFeed));
        } else if (tokenType == TokenType.USDC) {
            if (address(usdcUsdPriceFeed) != address(0)) {
                return _getOraclePriceInternal(address(usdcUsdPriceFeed));
            }
        } else if (tokenType == TokenType.USDT) {
            if (address(usdtUsdPriceFeed) != address(0)) {
                return _getOraclePriceInternal(address(usdtUsdPriceFeed));
            }
        }

        revert NoPriceDataAvailable(tokenType);
    }

    /**
     * @notice Get price from oracle (internal optimized version)
     * @param priceFeedAddress Price feed address
     * @return price Price in 18 decimals
     */
    function _getOraclePriceInternal(address priceFeedAddress) internal view returns (uint price) {
        AggregatorV3Interface feed = AggregatorV3Interface(priceFeedAddress);

        (uint80 roundId, int priceInt, uint startedAt, uint updatedAt, uint80 answeredInRound) =
            feed.latestRoundData();

        // Optimized validation
        if (
            priceInt <= 0 || updatedAt == 0 || roundId == 0 || answeredInRound < roundId
                || startedAt == 0
        ) {
            revert InvalidPriceData(priceInt);
        }

        // Cache decimals call to avoid multiple external calls
        uint8 feedDecimals = feed.decimals();

        // Optimized decimal conversion
        unchecked {
            if (feedDecimals == 18) {
                price = uint(priceInt);
            } else if (feedDecimals < 18) {
                price = uint(priceInt) * (10 ** (18 - feedDecimals));
            } else {
                price = uint(priceInt) / (10 ** (feedDecimals - 18));
            }
        }
    }

    /**
     * @notice Get JPY/USD price (optimized version)
     * @return price JPY/USD price (18 decimals)
     */
    function _getJPYUSDPriceOptimized() internal view returns (uint price) {
        // Try oracle first if available
        if (address(jpyUsdPriceFeed) != address(0)) {
            try this.getOraclePrice(address(jpyUsdPriceFeed), 18) returns (uint oraclePrice) {
                return oraclePrice;
            } catch {
                // Fall through to external data
            }
        }

        // Use external round data with optimized access
        RoundData storage externalRoundData = jpyUsdExternalRoundData;
        if (externalRoundData.updatedAt > 0 && externalRoundData.answer > 0) {
            // Optimized decimal conversion (8 to 18 decimals)
            unchecked {
                return uint(externalRoundData.answer) * 1e10;
            }
        }

        revert NoPriceDataAvailable(TokenType.ETH);
    }

    /**
     * @notice Get token price from oracle (legacy version for compatibility)
     * @param tokenType Token type to get price for
     * @return price Token price in USD (18 decimals)
     */
    function _getTokenPrice(TokenType tokenType) public view returns (uint price) {
        return _getTokenPriceOptimized(tokenType);
    }

    /**
     * @notice Get JPY/USD price from oracle or external data (legacy version)
     * @return price JPY/USD price (18 decimals)
     */
    function _getJPYUSDPrice() public view returns (uint price) {
        return _getJPYUSDPriceOptimized();
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
            revert PriceDataStale(updatedAt, 0);
        }

        // Note: Removed staleness time check to allow flexible oracle update timing

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
     */
    function getExchangeQuote(TokenType tokenType, uint nlpAmount)
        external
        view
        returns (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee
        )
    {
        if (nlpAmount == 0 || !tokenConfigs[tokenType].isEnabled) {
            return (0, 0, 0, 0, 0);
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
            } catch {
                return (0, 0, 0, 0, 0);
            }
        } catch {
            return (0, 0, 0, 0, 0);
        }
    }

    /**
     * @notice Get current contract status
     * @return ethBalance Current ETH balance
     * @return isPaused Whether contract is paused
     * @return jpyUsdPrice Current JPY/USD price
     */
    function getContractStatus()
        external
        view
        returns (uint ethBalance, bool isPaused, uint jpyUsdPrice)
    {
        ethBalance = address(this).balance;
        isPaused = paused();

        try this.getLatestJPYPrice() returns (uint price) {
            jpyUsdPrice = price;
        } catch {
            jpyUsdPrice = 0;
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

    /**
     * @notice Get JPY/USD external round data
     * @return Round data structure matching Chainlink's latestRoundData
     * @dev This function returns the external JPY/USD data in latestRoundData format
     */
    function getJPYUSDExternalRoundData() external view returns (RoundData memory) {
        return jpyUsdExternalRoundData;
    }

    /**
     * @notice Get latest ETH/USD price from dedicated oracle
     * @return price ETH/USD price (18 decimals)
     * @dev This function always uses the dedicated ETH/USD oracle
     */
    function getLatestETHPrice() external view returns (uint price) {
        return this.getOraclePrice(address(ethUsdPriceFeed), 18);
    }

    /**
     * @notice Get latest JPY/USD price from oracle or external data
     * @return price JPY/USD price (18 decimals)
     * @dev This function uses oracle if available, otherwise external round data
     */
    function getLatestJPYPrice() external view returns (uint price) {
        return _getJPYUSDPriceOptimized();
    }

    /**
     * @notice Get the current NLP to JPY exchange rate numerator
     * @return rate The current exchange rate numerator
     */
    function getNLPToJPYRate() external view returns (uint rate) {
        return NLP_TO_JPY_RATE;
    }

    /**
     * @notice Get the rate denominator for NLP to JPY conversion
     * @return denominator The rate denominator
     */
    function getNLPToJPYRateDenominator() external pure returns (uint denominator) {
        return NLP_TO_JPY_RATE_DENOMINATOR;
    }

    /**
     * @notice Calculate the actual NLP to JPY exchange rate as a decimal
     * @param nlpAmount Amount of NLP tokens
     * @return jpyAmount Equivalent JPY amount
     * @dev For display purposes: actualRate = NLP_TO_JPY_RATE / NLP_TO_JPY_RATE_DENOMINATOR
     */
    function calculateJPYAmount(uint nlpAmount) external view returns (uint jpyAmount) {
        return Math.mulDiv(nlpAmount, NLP_TO_JPY_RATE, NLP_TO_JPY_RATE_DENOMINATOR);
    }

    /**
     * @notice Calculate minimum amount out with slippage tolerance
     * @param tokenType Token type to get quote for
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param slippageToleranceBps Slippage tolerance in basis points (e.g., 100 = 1%)
     * @return minAmountOut Minimum amount out considering slippage
     * @return quoteAmount Expected amount without slippage
     * @dev Use this function to calculate minAmountOut for slippage-protected exchanges
     */
    function calculateMinAmountOut(TokenType tokenType, uint nlpAmount, uint slippageToleranceBps)
        external
        view
        returns (uint minAmountOut, uint quoteAmount)
    {
        require(slippageToleranceBps <= 10000, "Slippage tolerance too high");

        if (nlpAmount == 0 || !tokenConfigs[tokenType].isEnabled) {
            return (0, 0);
        }

        try this._calculatePrices(tokenType) returns (PriceCalculationResult memory priceResult) {
            try this._calculateTokenAmounts(tokenType, nlpAmount, priceResult) returns (
                TokenAmountResult memory amountResult
            ) {
                quoteAmount = amountResult.tokenAmount;
                // Calculate minimum amount considering slippage
                minAmountOut = (quoteAmount * (10000 - slippageToleranceBps)) / 10000;
            } catch {
                return (0, 0);
            }
        } catch {
            return (0, 0);
        }
    }

    /**
     * @notice Get exchange quote with slippage calculation
     * @param tokenType Token type to get quote for
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param slippageToleranceBps Slippage tolerance in basis points (e.g., 100 = 1%)
     * @return tokenAmount Amount of tokens that would be received
     * @return tokenUsdRate Token/USD price used
     * @return jpyUsdRate JPY/USD price used
     * @return exchangeFee Exchange fee amount in tokens
     * @return operationalFee Operational fee amount in tokens
     * @return minAmountOut Minimum amount out considering slippage
     * @return maxSlippageAmount Maximum possible slippage amount
     */
    function getExchangeQuoteWithSlippage(
        TokenType tokenType,
        uint nlpAmount,
        uint slippageToleranceBps
    )
        external
        view
        returns (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee,
            uint minAmountOut,
            uint maxSlippageAmount
        )
    {
        require(slippageToleranceBps <= 10000, "Slippage tolerance too high");

        if (nlpAmount == 0 || !tokenConfigs[tokenType].isEnabled) {
            return (0, 0, 0, 0, 0, 0, 0);
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

                // Calculate slippage protection values
                minAmountOut = (tokenAmount * (10000 - slippageToleranceBps)) / 10000;
                maxSlippageAmount = tokenAmount - minAmountOut;
            } catch {
                return (0, 0, 0, 0, 0, 0, 0);
            }
        } catch {
            return (0, 0, 0, 0, 0, 0, 0);
        }
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
        if (treasury == address(0)) revert TreasuryNotSet();

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
        if (treasury == address(0)) revert TreasuryNotSet();
        if (tokenType == TokenType.ETH) revert InvalidTokenType(tokenType);

        TokenConfig memory config = tokenConfigs[tokenType];
        if (config.tokenAddress == address(0)) revert InvalidTokenConfig();

        IERC20Extended token = IERC20Extended(config.tokenAddress);
        uint balance = token.balanceOf(address(this));
        uint withdrawAmount = amount == 0 ? balance : amount;

        if (withdrawAmount > balance) {
            revert InsufficientBalance(tokenType, withdrawAmount, balance);
        }

        emit EmergencyWithdraw(tokenType, treasury, withdrawAmount);
        if (!token.transfer(treasury, withdrawAmount)) revert TransferFailed();
    }

    /**
     * @notice Set treasury address
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
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
