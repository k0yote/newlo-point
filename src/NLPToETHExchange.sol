// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { AggregatorV3Interface } from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { IERC20Extended } from "./interfaces/IERC20Extended.sol";

/**
 * @title NLPToETHExchange
 * @author NewLo Team
 * @notice NewLo Point (NLP) から ETH への交換コントラクト
 * @dev This contract allows users to exchange NLP tokens for ETH using real-time price feeds
 *
 * @dev Key Features:
 *      - 1:1 NLP to JPY exchange rate
 *      - Real-time ETH/USD and JPY/USD price conversion using Chainlink oracles
 *      - Configurable exchange fees
 *      - Emergency pause functionality
 *      - Administrative fund management
 *      - Comprehensive exchange statistics
 *
 * @dev Exchange Formula:
 *      1. NLP → JPY (1:1 ratio)
 *      2. JPY → USD using JPY/USD price feed
 *      3. USD → ETH using ETH/USD price feed
 *      Formula: ethAmount = (nlpAmount * jpyUsdPrice) / ethUsdPrice - fees
 *
 * @dev Security Features:
 *      - Reentrancy protection
 *      - Pausable for emergency stops
 *      - Price staleness checks
 *      - Comprehensive input validation
 *      - CEI (Checks-Effects-Interactions) pattern
 */
contract NLPToETHExchange is Ownable, ReentrancyGuard, Pausable {
    /* ═══════════════════════════════════════════════════════════════════════
                               IMMUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice NewLo Point token contract
    IERC20Extended public immutable nlpToken;

    /// @notice Chainlink ETH/USD price feed
    AggregatorV3Interface public immutable ethUsdPriceFeed;

    /// @notice Chainlink JPY/USD price feed
    AggregatorV3Interface public immutable jpyUsdPriceFeed;

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Exchange rate: 1 NLP = 1 JPY
    uint public constant NLP_TO_JPY_RATE = 1;

    /// @notice Price data staleness threshold (1 hour)
    uint public constant PRICE_STALENESS_THRESHOLD = 3600;

    /// @notice Maximum exchange fee (5%)
    uint public constant MAX_FEE = 500;

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Exchange fee in basis points (100 = 1%)
    uint public exchangeFee = 0;

    /// @notice Total NLP tokens exchanged
    uint public totalExchanged;

    /// @notice Total ETH sent to users
    uint public totalETHSent;

    /// @notice User exchange amounts
    mapping(address => uint) public userExchangeAmount;

    /// @notice User received ETH amounts
    mapping(address => uint) public userETHReceived;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when NLP is exchanged for ETH
    event ExchangeExecuted(
        address indexed user,
        uint nlpAmount,
        uint ethAmount,
        uint ethUsdRate,
        uint jpyUsdRate,
        uint fee
    );

    /// @notice Emitted when exchange fee is updated
    event FeeUpdated(uint oldFee, uint newFee);

    /// @notice Emitted when ETH is withdrawn by admin
    event EmergencyWithdraw(address indexed to, uint amount);

    /// @notice Emitted when price data is stale
    event PriceStale(uint timestamp, uint threshold);

    /// @notice Emitted when NLP is exchanged for ETH using permit for gasless operation
    event GaslessExchangeExecuted(
        address indexed user,
        address indexed relayer,
        uint nlpAmount,
        uint ethAmount,
        uint ethUsdRate,
        uint jpyUsdRate,
        uint fee
    );

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error InsufficientETHBalance(uint required, uint available);
    error InvalidExchangeAmount(uint amount);
    error PriceDataStale(uint updatedAt, uint threshold);
    error InvalidPriceData(int price);
    error ExchangeFailed(address user, uint nlpAmount);
    error InvalidFee(uint fee, uint maxFee);
    error InvalidUser(address user);
    error PermitFailed(address user, uint nlpAmount, uint deadline);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the exchange contract
     * @param _nlpToken NewLo Point token contract address
     * @param _ethUsdPriceFeed Chainlink ETH/USD price feed address
     * @param _jpyUsdPriceFeed Chainlink JPY/USD price feed address
     * @param _initialOwner Initial owner of the contract
     */
    constructor(
        address _nlpToken,
        address _ethUsdPriceFeed,
        address _jpyUsdPriceFeed,
        address _initialOwner
    ) Ownable(_initialOwner) {
        require(_nlpToken != address(0), "NLP token address cannot be zero");
        require(_ethUsdPriceFeed != address(0), "ETH/USD price feed address cannot be zero");
        require(_jpyUsdPriceFeed != address(0), "JPY/USD price feed address cannot be zero");
        require(_initialOwner != address(0), "Initial owner cannot be zero");

        nlpToken = IERC20Extended(_nlpToken);
        ethUsdPriceFeed = AggregatorV3Interface(_ethUsdPriceFeed);
        jpyUsdPriceFeed = AggregatorV3Interface(_jpyUsdPriceFeed);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            EXCHANGE FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Exchange NLP tokens for ETH using permit for gasless operation
     * @param nlpAmount Amount of NLP tokens to exchange
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @param user User address (token owner)
     *
     * @dev Gasless Exchange Process:
     *      1. Validate input parameters
     *      2. Execute permit() to allow this contract to spend user's tokens
     *      3. Get current ETH/USD and JPY/USD prices
     *      4. Calculate ETH amount: (nlpAmount * jpyUsdPrice) / ethUsdPrice
     *      5. Apply exchange fee
     *      6. Burn NLP tokens from user
     *      7. Send ETH to user
     *      8. Update statistics
     *
     * Requirements:
     * - Contract must not be paused
     * - nlpAmount must be greater than 0
     * - User must have sufficient NLP tokens
     * - Permit signature must be valid and not expired
     * - Contract must have sufficient ETH balance
     * - Caller pays gas fees (typically a relayer operated by the team)
     */
    function exchangeNLPToETHWithPermit(
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

        // Execute permit to allow this contract to spend user's tokens
        // This eliminates the need for user to call approve() separately
        try nlpToken.permit(user, address(this), nlpAmount, deadline, v, r, s) {
            // Permit successful
        } catch {
            revert PermitFailed(user, nlpAmount, deadline);
        }

        // Get current prices from Chainlink oracles
        uint ethUsdPrice = getLatestETHPrice();
        uint jpyUsdPrice = getLatestJPYPrice();

        // Calculate required ETH amount
        // Formula: ethAmount = (nlpAmount * jpyUsdPrice) / ethUsdPrice
        uint ethAmountBeforeFee = (nlpAmount * jpyUsdPrice) / ethUsdPrice;

        // Calculate and apply fee
        uint fee = (ethAmountBeforeFee * exchangeFee) / 10000;
        uint ethAmountAfterFee = ethAmountBeforeFee - fee;

        // Check contract ETH balance
        if (address(this).balance < ethAmountAfterFee) {
            revert InsufficientETHBalance(ethAmountAfterFee, address(this).balance);
        }

        // Update statistics before external calls (CEI pattern)
        totalExchanged += nlpAmount;
        totalETHSent += ethAmountAfterFee;
        userExchangeAmount[user] += nlpAmount;
        userETHReceived[user] += ethAmountAfterFee;

        // Burn NLP tokens from user (using the permit approval)
        try nlpToken.burnFrom(user, nlpAmount) {
            // Burn successful
        } catch {
            revert ExchangeFailed(user, nlpAmount);
        }

        // Send ETH to user
        (bool ethSent,) = user.call{ value: ethAmountAfterFee }("");
        require(ethSent, "ETH transfer failed");

        // Emit gasless exchange event
        emit GaslessExchangeExecuted(
            user,
            msg.sender, // relayer
            nlpAmount,
            ethAmountAfterFee,
            ethUsdPrice,
            jpyUsdPrice,
            fee
        );
    }

    /**
     * @notice Exchange NLP tokens for ETH
     * @param nlpAmount Amount of NLP tokens to exchange
     *
     * @dev Exchange Process:
     *      1. Validate input amount
     *      2. Get current ETH/USD and JPY/USD prices
     *      3. Calculate ETH amount: (nlpAmount * jpyUsdPrice) / ethUsdPrice
     *      4. Apply exchange fee
     *      5. Burn NLP tokens from user
     *      6. Send ETH to user
     *      7. Update statistics
     *
     * Requirements:
     * - Contract must not be paused
     * - nlpAmount must be greater than 0
     * - User must have sufficient NLP tokens
     * - User must have approved this contract to spend NLP tokens
     * - Contract must have sufficient ETH balance
     */
    function exchangeNLPToETH(uint nlpAmount) external nonReentrant whenNotPaused {
        if (nlpAmount == 0) {
            revert InvalidExchangeAmount(nlpAmount);
        }

        address user = msg.sender;

        // Get current prices from Chainlink oracles
        uint ethUsdPrice = getLatestETHPrice();
        uint jpyUsdPrice = getLatestJPYPrice();

        // Calculate required ETH amount
        // Formula: ethAmount = (nlpAmount * jpyUsdPrice) / ethUsdPrice
        uint ethAmountBeforeFee = (nlpAmount * jpyUsdPrice) / ethUsdPrice;

        // Calculate and apply fee
        uint fee = (ethAmountBeforeFee * exchangeFee) / 10000;
        uint ethAmountAfterFee = ethAmountBeforeFee - fee;

        // Check contract ETH balance
        if (address(this).balance < ethAmountAfterFee) {
            revert InsufficientETHBalance(ethAmountAfterFee, address(this).balance);
        }

        // Update statistics before external calls (CEI pattern)
        totalExchanged += nlpAmount;
        totalETHSent += ethAmountAfterFee;
        userExchangeAmount[user] += nlpAmount;
        userETHReceived[user] += ethAmountAfterFee;

        // Burn NLP tokens from user
        try nlpToken.burnFrom(user, nlpAmount) {
            // Burn successful
        } catch {
            revert ExchangeFailed(user, nlpAmount);
        }

        // Send ETH to user
        (bool ethSent,) = user.call{ value: ethAmountAfterFee }("");
        require(ethSent, "ETH transfer failed");

        // Emit exchange event
        emit ExchangeExecuted(user, nlpAmount, ethAmountAfterFee, ethUsdPrice, jpyUsdPrice, fee);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get exchange quote without executing the exchange
     * @param nlpAmount Amount of NLP tokens to exchange
     * @return ethAmount Amount of ETH that would be received
     * @return ethUsdRate Current ETH/USD price used
     * @return jpyUsdRate Current JPY/USD price used
     * @return fee Fee amount in ETH
     */
    function getExchangeQuote(uint nlpAmount)
        external
        view
        returns (uint ethAmount, uint ethUsdRate, uint jpyUsdRate, uint fee)
    {
        if (nlpAmount == 0) {
            return (0, 0, 0, 0);
        }

        ethUsdRate = getLatestETHPrice();
        jpyUsdRate = getLatestJPYPrice();

        uint ethAmountBeforeFee = (nlpAmount * jpyUsdRate) / ethUsdRate;
        fee = (ethAmountBeforeFee * exchangeFee) / 10000;
        ethAmount = ethAmountBeforeFee - fee;
    }

    /**
     * @notice Get latest ETH/USD price from Chainlink
     * @return price ETH price in USD (18 decimals)
     */
    function getLatestETHPrice() public view returns (uint price) {
        (
            /* uint80 roundId */
            ,
            int priceInt,
            /* uint256 startedAt */
            ,
            uint updatedAt,
            /* uint80 answeredInRound */
        ) = ethUsdPriceFeed.latestRoundData();

        if (priceInt <= 0) {
            revert InvalidPriceData(int(priceInt));
        }

        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
            revert PriceDataStale(uint(updatedAt), PRICE_STALENESS_THRESHOLD);
        }

        // Convert Chainlink price to 18 decimals
        uint8 decimals = ethUsdPriceFeed.decimals();
        price = uint(priceInt) * (10 ** (18 - decimals));
    }

    /**
     * @notice Get latest JPY/USD price from Chainlink
     * @return price JPY price in USD (18 decimals)
     */
    function getLatestJPYPrice() public view returns (uint price) {
        (
            /* uint80 roundId */
            ,
            int priceInt,
            /* uint256 startedAt */
            ,
            uint updatedAt,
            /* uint80 answeredInRound */
        ) = jpyUsdPriceFeed.latestRoundData();

        if (priceInt <= 0) {
            revert InvalidPriceData(int(priceInt));
        }

        if (block.timestamp - updatedAt > PRICE_STALENESS_THRESHOLD) {
            revert PriceDataStale(uint(updatedAt), PRICE_STALENESS_THRESHOLD);
        }

        // Convert Chainlink price to 18 decimals
        uint8 decimals = jpyUsdPriceFeed.decimals();
        price = uint(priceInt) * (10 ** (18 - decimals));
    }

    /**
     * @notice Get contract status information
     * @return ethBalance Current ETH balance
     * @return currentETHPrice Current ETH/USD price
     * @return currentJPYPrice Current JPY/USD price
     * @return currentFee Current exchange fee
     * @return isPaused Whether contract is paused
     * @return totalExchangedAmount Total NLP exchanged
     * @return totalETHSentAmount Total ETH sent to users
     */
    function getContractStatus()
        external
        view
        returns (
            uint ethBalance,
            uint currentETHPrice,
            uint currentJPYPrice,
            uint currentFee,
            bool isPaused,
            uint totalExchangedAmount,
            uint totalETHSentAmount
        )
    {
        ethBalance = address(this).balance;
        currentETHPrice = getLatestETHPrice();
        currentJPYPrice = getLatestJPYPrice();
        currentFee = exchangeFee;
        isPaused = paused();
        totalExchangedAmount = totalExchanged;
        totalETHSentAmount = totalETHSent;
    }

    /**
     * @notice Get user exchange history
     * @param user User address
     * @return exchangedNLP Total NLP exchanged by user
     * @return receivedETH Total ETH received by user
     */
    function getUserExchangeHistory(address user)
        external
        view
        returns (uint exchangedNLP, uint receivedETH)
    {
        exchangedNLP = userExchangeAmount[user];
        receivedETH = userETHReceived[user];
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ADMIN FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Set exchange fee (admin only)
     * @param newFee New exchange fee in basis points (100 = 1%)
     *
     * Requirements:
     * - Caller must be owner
     * - Fee must not exceed MAX_FEE (5%)
     */
    function setExchangeFee(uint newFee) external onlyOwner {
        if (newFee > MAX_FEE) {
            revert InvalidFee(newFee, MAX_FEE);
        }

        uint oldFee = exchangeFee;
        exchangeFee = newFee;

        emit FeeUpdated(oldFee, newFee);
    }

    /**
     * @notice Pause the contract (admin only)
     * @dev Prevents all exchanges when paused
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract (admin only)
     * @dev Resumes normal exchange operations
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /**
     * @notice Emergency ETH withdrawal (admin only)
     * @param to Withdrawal destination address
     * @param amount Amount to withdraw (0 for all)
     *
     * Requirements:
     * - Caller must be owner
     * - Destination address must not be zero
     * - Amount must not exceed contract balance
     */
    function emergencyWithdrawETH(address payable to, uint amount) external onlyOwner {
        require(to != address(0), "Invalid address");

        uint withdrawAmount = amount == 0 ? address(this).balance : amount;
        require(withdrawAmount <= address(this).balance, "Insufficient balance");

        // Emit event before external call (following CEI pattern)
        emit EmergencyWithdraw(to, withdrawAmount);

        (bool sent,) = to.call{ value: withdrawAmount }("");
        require(sent, "ETH transfer failed");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              RECEIVE FUNCTION
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Receive ETH deposits
     * @dev Allows the contract to receive ETH for exchange operations
     */
    receive() external payable {
        // Allow ETH deposits for exchange operations
    }
}
