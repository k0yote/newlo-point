// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { SafeERC20 } from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

/**
 * @title MultiTokenDistribution
 * @author NewLo Team
 * @notice Multiple token distribution contract for NewLo ecosystem
 * @dev This contract allows administrators to distribute various ERC20 tokens to users
 *
 * @dev Key Features:
 *      - Support for multiple ERC20 tokens (WETH, USDC, USDT, etc.)
 *      - Configurable token support with activation/deactivation
 *      - Comprehensive distribution tracking and statistics
 *      - Emergency pause functionality
 *      - Safe token operations with SafeERC20
 *      - Administrative fund management
 *
 * @dev Security Features:
 *      - Reentrancy protection
 *      - Pausable for emergency stops
 *      - Owner-only administrative functions
 *      - SafeERC20 for secure token operations
 *      - Comprehensive input validation
 *      - CEI (Checks-Effects-Interactions) pattern
 */
contract MultiTokenDistribution is Ownable, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ═══════════════════════════════════════════════════════════════════════
                               STRUCTURES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Token configuration and statistics
    struct TokenInfo {
        address tokenAddress;      // ERC20 token contract address
        uint8 decimals;           // Token decimals for display purposes
        bool isActive;            // Whether token is currently supported
        uint256 totalDistributed; // Total amount distributed to all users
        uint256 totalUsers;       // Number of unique users who received this token
    }

    /// @notice Distribution record for tracking individual distributions
    struct DistributionRecord {
        uint256 amount;           // Amount distributed
        uint256 timestamp;        // When the distribution occurred
        string tokenSymbol;       // Token symbol for this distribution
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                STATE VARIABLES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Mapping of token symbols to their configurations
    mapping(string => TokenInfo) public supportedTokens;

    /// @notice Mapping of user addresses to token symbols to total received amounts
    mapping(address => mapping(string => uint256)) public userReceivedAmounts;

    /// @notice Mapping of user addresses to their distribution history
    mapping(address => DistributionRecord[]) public userDistributionHistory;

    /// @notice Array of all supported token symbols for enumeration
    string[] public tokenSymbols;

    /// @notice Total number of distributions executed
    uint256 public totalDistributions;

    /// @notice Total number of unique users who received tokens
    uint256 public totalUsers;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when a new token is added to the system
    event TokenAdded(string indexed symbol, address indexed tokenAddress, uint8 decimals);

    /// @notice Emitted when a token's status is updated
    event TokenStatusUpdated(string indexed symbol, bool isActive);

    /// @notice Emitted when tokens are distributed to a user
    event TokenDistributed(
        address indexed user,
        string indexed symbol,
        uint256 amount,
        uint256 timestamp
    );

    /// @notice Emitted when tokens are distributed to multiple users
    event BatchDistributionCompleted(
        string indexed symbol,
        uint256 totalAmount,
        uint256 userCount
    );

    /// @notice Emitted when emergency withdrawal is executed
    event EmergencyWithdraw(
        address indexed to,
        string indexed symbol,
        uint256 amount
    );

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error TokenNotSupported(string symbol);
    error TokenAlreadyExists(string symbol);
    error TokenNotActive(string symbol);
    error InvalidTokenAddress(address tokenAddress);
    error InvalidUser(address user);
    error InvalidAmount(uint256 amount);
    error InvalidSymbol(string symbol);
    error InsufficientBalance(string symbol, uint256 required, uint256 available);
    error InvalidArrayLength(uint256 usersLength, uint256 amountsLength);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the MultiTokenDistribution contract
     * @param _initialOwner Initial owner of the contract
     */
    constructor(address _initialOwner) Ownable(_initialOwner) {
        require(_initialOwner != address(0), "Initial owner cannot be zero");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          TOKEN MANAGEMENT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Add a new token to the distribution system
     * @param symbol Token symbol (e.g., "WETH", "USDC", "USDT")
     * @param tokenAddress Contract address of the ERC20 token
     * @param decimals Number of decimals for the token
     *
     * Requirements:
     * - Caller must be the owner
     * - Token symbol must not already exist
     * - Token address must not be zero
     * - Symbol must not be empty
     *
     * Emits:
     * - TokenAdded event
     */
    function addToken(
        string memory symbol,
        address tokenAddress,
        uint8 decimals
    ) external onlyOwner {
        if (bytes(symbol).length == 0) {
            revert InvalidSymbol(symbol);
        }
        if (tokenAddress == address(0)) {
            revert InvalidTokenAddress(tokenAddress);
        }
        if (supportedTokens[symbol].tokenAddress != address(0)) {
            revert TokenAlreadyExists(symbol);
        }

        supportedTokens[symbol] = TokenInfo({
            tokenAddress: tokenAddress,
            decimals: decimals,
            isActive: true,
            totalDistributed: 0,
            totalUsers: 0
        });

        tokenSymbols.push(symbol);
        emit TokenAdded(symbol, tokenAddress, decimals);
    }

    /**
     * @notice Update the active status of a token
     * @param symbol Token symbol to update
     * @param isActive New active status
     *
     * Requirements:
     * - Caller must be the owner
     * - Token must exist
     *
     * Emits:
     * - TokenStatusUpdated event
     */
    function setTokenStatus(string memory symbol, bool isActive) external onlyOwner {
        if (supportedTokens[symbol].tokenAddress == address(0)) {
            revert TokenNotSupported(symbol);
        }

        supportedTokens[symbol].isActive = isActive;
        emit TokenStatusUpdated(symbol, isActive);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          DISTRIBUTION FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Distribute tokens to a single user
     * @param symbol Token symbol to distribute
     * @param to Recipient address
     * @param amount Amount to distribute
     *
     * Requirements:
     * - Contract must not be paused
     * - Caller must be the owner
     * - Token must be supported and active
     * - Recipient must not be zero address
     * - Amount must be greater than 0
     * - Contract must have sufficient token balance
     *
     * Emits:
     * - TokenDistributed event
     */
    function distributeToken(
        string memory symbol,
        address to,
        uint256 amount
    ) external onlyOwner nonReentrant whenNotPaused {
        _validateDistribution(symbol, to, amount);

        TokenInfo storage token = supportedTokens[symbol];
        IERC20 tokenContract = IERC20(token.tokenAddress);

        // Check contract balance
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance < amount) {
            revert InsufficientBalance(symbol, amount, balance);
        }

        // Update user's first-time status
        bool isFirstTime = userReceivedAmounts[to][symbol] == 0;
        if (isFirstTime) {
            token.totalUsers++;
            if (_isFirstTimeUser(to)) {
                totalUsers++;
            }
        }

        // Update statistics
        token.totalDistributed += amount;
        userReceivedAmounts[to][symbol] += amount;
        totalDistributions++;

        // Add to user's distribution history
        userDistributionHistory[to].push(DistributionRecord({
            amount: amount,
            timestamp: block.timestamp,
            tokenSymbol: symbol
        }));

        // Transfer tokens
        tokenContract.safeTransfer(to, amount);

        emit TokenDistributed(to, symbol, amount, block.timestamp);
    }

    /**
     * @notice Distribute tokens to multiple users in a single transaction
     * @param symbol Token symbol to distribute
     * @param users Array of recipient addresses
     * @param amounts Array of amounts to distribute (must match users array length)
     *
     * Requirements:
     * - Contract must not be paused
     * - Caller must be the owner
     * - Token must be supported and active
     * - Users and amounts arrays must have the same length
     * - All recipients must be valid addresses
     * - All amounts must be greater than 0
     * - Contract must have sufficient token balance
     *
     * Emits:
     * - TokenDistributed event for each successful distribution
     * - BatchDistributionCompleted event
     */
    function batchDistributeToken(
        string memory symbol,
        address[] calldata users,
        uint256[] calldata amounts
    ) external onlyOwner nonReentrant whenNotPaused {
        if (users.length != amounts.length) {
            revert InvalidArrayLength(users.length, amounts.length);
        }
        if (supportedTokens[symbol].tokenAddress == address(0)) {
            revert TokenNotSupported(symbol);
        }
        if (!supportedTokens[symbol].isActive) {
            revert TokenNotActive(symbol);
        }

        TokenInfo storage token = supportedTokens[symbol];
        IERC20 tokenContract = IERC20(token.tokenAddress);

        // Calculate total amount needed
        uint256 totalAmount = 0;
        for (uint256 i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        // Check contract balance
        uint256 balance = tokenContract.balanceOf(address(this));
        if (balance < totalAmount) {
            revert InsufficientBalance(symbol, totalAmount, balance);
        }

        // Cache variables to optimize gas usage in loop
        uint256 currentTime = block.timestamp;
        uint256 newTotalUsers = 0;
        uint256 usersLength = users.length;

        // Execute distributions
        for (uint256 i = 0; i < usersLength; i++) {
            if (users[i] == address(0)) {
                revert InvalidUser(users[i]);
            }
            if (amounts[i] == 0) {
                revert InvalidAmount(amounts[i]);
            }

            // Update user's first-time status
            if (userReceivedAmounts[users[i]][symbol] == 0) {
                token.totalUsers++;
                if (_isFirstTimeUser(users[i])) {
                    newTotalUsers++;
                }
            }

            // Update statistics
            token.totalDistributed += amounts[i];
            userReceivedAmounts[users[i]][symbol] += amounts[i];

            // Add to user's distribution history
            userDistributionHistory[users[i]].push(DistributionRecord({
                amount: amounts[i],
                timestamp: currentTime,
                tokenSymbol: symbol
            }));

            // Transfer tokens
            tokenContract.safeTransfer(users[i], amounts[i]);
            emit TokenDistributed(users[i], symbol, amounts[i], currentTime);
        }

        // Update global counters outside the loop for gas optimization
        totalDistributions += usersLength;
        totalUsers += newTotalUsers;

        emit BatchDistributionCompleted(symbol, totalAmount, users.length);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          EMERGENCY FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Emergency withdraw tokens from the contract
     * @param symbol Token symbol to withdraw
     * @param to Address to receive the tokens
     * @param amount Amount to withdraw (0 means withdraw all)
     *
     * Requirements:
     * - Caller must be the owner
     * - Token must be supported
     * - Recipient must not be zero address
     *
     * Emits:
     * - EmergencyWithdraw event
     */
    function emergencyWithdraw(
        string memory symbol,
        address to,
        uint256 amount
    ) external onlyOwner {
        if (supportedTokens[symbol].tokenAddress == address(0)) {
            revert TokenNotSupported(symbol);
        }
        if (to == address(0)) {
            revert InvalidUser(to);
        }

        IERC20 tokenContract = IERC20(supportedTokens[symbol].tokenAddress);
        uint256 balance = tokenContract.balanceOf(address(this));

        if (amount == 0) {
            amount = balance;
        }

        if (amount > balance) {
            revert InsufficientBalance(symbol, amount, balance);
        }

        tokenContract.safeTransfer(to, amount);
        emit EmergencyWithdraw(to, symbol, amount);
    }

    /**
     * @notice Pause the contract (emergency stop)
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyOwner {
        _unpause();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get the number of supported tokens
     * @return Number of supported tokens
     */
    function getTokenCount() external view returns (uint256) {
        return tokenSymbols.length;
    }

    /**
     * @notice Get all supported token symbols
     * @return Array of token symbols
     */
    function getAllTokenSymbols() external view returns (string[] memory) {
        return tokenSymbols;
    }

    /**
     * @notice Get token balance of the contract
     * @param symbol Token symbol
     * @return Token balance
     */
    function getTokenBalance(string memory symbol) external view returns (uint256) {
        if (supportedTokens[symbol].tokenAddress == address(0)) {
            revert TokenNotSupported(symbol);
        }
        return IERC20(supportedTokens[symbol].tokenAddress).balanceOf(address(this));
    }

    /**
     * @notice Get user's distribution history
     * @param user User address
     * @return Array of distribution records
     */
    function getUserDistributionHistory(address user) external view returns (DistributionRecord[] memory) {
        return userDistributionHistory[user];
    }

    /**
     * @notice Get user's distribution history for a specific token
     * @param user User address
     * @param symbol Token symbol
     * @return Array of distribution records for the specified token
     */
    function getUserTokenHistory(address user, string memory symbol) external view returns (DistributionRecord[] memory) {
        DistributionRecord[] memory allHistory = userDistributionHistory[user];
        uint256 count = 0;

        // Count matching records
        for (uint256 i = 0; i < allHistory.length; i++) {
            if (keccak256(bytes(allHistory[i].tokenSymbol)) == keccak256(bytes(symbol))) {
                count++;
            }
        }

        // Create filtered array
        DistributionRecord[] memory filteredHistory = new DistributionRecord[](count);
        uint256 index = 0;
        for (uint256 i = 0; i < allHistory.length; i++) {
            if (keccak256(bytes(allHistory[i].tokenSymbol)) == keccak256(bytes(symbol))) {
                filteredHistory[index] = allHistory[i];
                index++;
            }
        }

        return filteredHistory;
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            INTERNAL FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @dev Validate distribution parameters
     * @param symbol Token symbol
     * @param to Recipient address
     * @param amount Amount to distribute
     */
    function _validateDistribution(string memory symbol, address to, uint256 amount) internal view {
        if (supportedTokens[symbol].tokenAddress == address(0)) {
            revert TokenNotSupported(symbol);
        }
        if (!supportedTokens[symbol].isActive) {
            revert TokenNotActive(symbol);
        }
        if (to == address(0)) {
            revert InvalidUser(to);
        }
        if (amount == 0) {
            revert InvalidAmount(amount);
        }
    }

    /**
     * @dev Check if user is receiving tokens for the first time
     * @param user User address
     * @return True if user has never received any tokens before
     */
    function _isFirstTimeUser(address user) internal view returns (bool) {
        uint256 symbolsLength = tokenSymbols.length;
        for (uint256 i = 0; i < symbolsLength; i++) {
            if (userReceivedAmounts[user][tokenSymbols[i]] > 0) {
                return false;
            }
        }
        return true;
    }
} 