// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
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
 *      - Role-based access control for different operations
 *      - Configurable token support with activation/deactivation
 *      - Comprehensive distribution tracking and statistics
 *      - Emergency pause functionality
 *      - Safe token operations with SafeERC20
 *      - Administrative fund management
 *
 * @dev Security Features:
 *      - Reentrancy protection
 *      - Pausable for emergency stops
 *      - Role-based administrative functions
 *      - SafeERC20 for secure token operations
 *      - Comprehensive input validation
 *      - CEI (Checks-Effects-Interactions) pattern
 *
 * @dev Access Control Roles:
 *      - ADMIN_ROLE: Full administrative access, can grant/revoke roles
 *      - DISTRIBUTOR_ROLE: Can distribute tokens to users
 *      - TOKEN_MANAGER_ROLE: Can add/remove tokens and update their status
 *      - EMERGENCY_ROLE: Can pause/unpause contract and emergency withdraw
 */
contract MultiTokenDistribution is AccessControl, ReentrancyGuard, Pausable {
    using SafeERC20 for IERC20;

    /* ═══════════════════════════════════════════════════════════════════════
                               ROLES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Role for full administrative access
    bytes32 public constant ADMIN_ROLE = DEFAULT_ADMIN_ROLE;

    /// @notice Role for token distribution operations
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Role for token management operations
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");

    /// @notice Role for emergency operations
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                               STRUCTURES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Token configuration and statistics
    struct TokenInfo {
        address tokenAddress; // ERC20 token contract address
        uint8 decimals; // Token decimals for display purposes
        bool isActive; // Whether token is currently supported
        uint totalDistributed; // Total amount distributed to all users
        uint totalUsers; // Number of unique users who received this token
    }

    /// @notice Distribution record for tracking individual distributions
    struct DistributionRecord {
        uint amount; // Amount distributed
        uint timestamp; // When the distribution occurred
        string tokenSymbol; // Token symbol for this distribution
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                STATE VARIABLES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Mapping of token symbols to their configurations
    mapping(string => TokenInfo) public supportedTokens;

    /// @notice Mapping of user addresses to token symbols to total received amounts
    mapping(address => mapping(string => uint)) public userReceivedAmounts;

    /// @notice Mapping of user addresses to their distribution history
    mapping(address => DistributionRecord[]) public userDistributionHistory;

    /// @notice Array of all supported token symbols for enumeration
    string[] public tokenSymbols;

    /// @notice Total number of distributions executed
    uint public totalDistributions;

    /// @notice Total number of unique users who received tokens
    uint public totalUsers;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when a new token is added to the system
    event TokenAdded(string indexed symbol, address indexed tokenAddress, uint8 decimals);

    /// @notice Emitted when a token's status is updated
    event TokenStatusUpdated(string indexed symbol, bool isActive);

    /// @notice Emitted when tokens are distributed to a user
    event TokenDistributed(
        address indexed user, string indexed symbol, uint amount, uint timestamp
    );

    /// @notice Emitted when tokens are distributed to multiple users
    event BatchDistributionCompleted(string indexed symbol, uint totalAmount, uint userCount);

    /// @notice Emitted when emergency withdrawal is executed
    event EmergencyWithdraw(address indexed to, string indexed symbol, uint amount);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error TokenNotSupported(string symbol);
    error TokenAlreadyExists(string symbol);
    error TokenNotActive(string symbol);
    error InvalidTokenAddress(address tokenAddress);
    error InvalidUser(address user);
    error InvalidAmount(uint amount);
    error InvalidSymbol(string symbol);
    error InsufficientBalance(string symbol, uint required, uint available);
    error InvalidArrayLength(uint usersLength, uint amountsLength);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the MultiTokenDistribution contract
     * @param _admin Initial admin who will have all roles
     */
    constructor(address _admin) {
        require(_admin != address(0), "Admin cannot be zero address");

        // Grant all roles to the admin
        _grantRole(ADMIN_ROLE, _admin);
        _grantRole(DISTRIBUTOR_ROLE, _admin);
        _grantRole(TOKEN_MANAGER_ROLE, _admin);
        _grantRole(EMERGENCY_ROLE, _admin);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                             ROLE MANAGEMENT
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Grant a role to an account
     * @param role Role to grant
     * @param account Account to grant role to
     * @dev Only accounts with ADMIN_ROLE can grant roles
     */
    function grantRole(bytes32 role, address account) public override onlyRole(ADMIN_ROLE) {
        _grantRole(role, account);
    }

    /**
     * @notice Revoke a role from an account
     * @param role Role to revoke
     * @param account Account to revoke role from
     * @dev Only accounts with ADMIN_ROLE can revoke roles
     */
    function revokeRole(bytes32 role, address account) public override onlyRole(ADMIN_ROLE) {
        _revokeRole(role, account);
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
     * - Caller must have TOKEN_MANAGER_ROLE
     * - Token symbol must not already exist
     * - Token address must not be zero
     * - Symbol must not be empty
     *
     * Emits:
     * - TokenAdded event
     */
    function addToken(string memory symbol, address tokenAddress, uint8 decimals)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
    {
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
     * - Caller must have TOKEN_MANAGER_ROLE
     * - Token must exist
     *
     * Emits:
     * - TokenStatusUpdated event
     */
    function setTokenStatus(string memory symbol, bool isActive)
        external
        onlyRole(TOKEN_MANAGER_ROLE)
    {
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
     * - Caller must have DISTRIBUTOR_ROLE
     * - Token must be supported and active
     * - Recipient must not be zero address
     * - Amount must be greater than 0
     * - Contract must have sufficient token balance
     *
     * Emits:
     * - TokenDistributed event
     */
    function distributeToken(string memory symbol, address to, uint amount)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        nonReentrant
        whenNotPaused
    {
        _validateDistribution(symbol, to, amount);

        TokenInfo storage token = supportedTokens[symbol];
        IERC20 tokenContract = IERC20(token.tokenAddress);

        // Check contract balance
        uint balance = tokenContract.balanceOf(address(this));
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
        userDistributionHistory[to].push(
            DistributionRecord({ amount: amount, timestamp: block.timestamp, tokenSymbol: symbol })
        );

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
     * - Caller must have DISTRIBUTOR_ROLE
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
        uint[] calldata amounts
    ) external onlyRole(DISTRIBUTOR_ROLE) nonReentrant whenNotPaused {
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
        uint totalAmount = 0;
        for (uint i = 0; i < amounts.length; i++) {
            totalAmount += amounts[i];
        }

        // Check contract balance
        uint balance = tokenContract.balanceOf(address(this));
        if (balance < totalAmount) {
            revert InsufficientBalance(symbol, totalAmount, balance);
        }

        // Cache variables to optimize gas usage in loop
        uint currentTime = block.timestamp;
        uint newTotalUsers = 0;
        uint usersLength = users.length;

        // Execute distributions
        for (uint i = 0; i < usersLength; i++) {
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
            userDistributionHistory[users[i]].push(
                DistributionRecord({
                    amount: amounts[i],
                    timestamp: currentTime,
                    tokenSymbol: symbol
                })
            );

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
     * - Caller must have EMERGENCY_ROLE
     * - Token must be supported
     * - Recipient must not be zero address
     *
     * Emits:
     * - EmergencyWithdraw event
     */
    function emergencyWithdraw(string memory symbol, address to, uint amount)
        external
        onlyRole(EMERGENCY_ROLE)
    {
        if (supportedTokens[symbol].tokenAddress == address(0)) {
            revert TokenNotSupported(symbol);
        }
        if (to == address(0)) {
            revert InvalidUser(to);
        }

        IERC20 tokenContract = IERC20(supportedTokens[symbol].tokenAddress);
        uint balance = tokenContract.balanceOf(address(this));

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
     * @dev Only accounts with EMERGENCY_ROLE can pause
     */
    function pause() external onlyRole(EMERGENCY_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only accounts with EMERGENCY_ROLE can unpause
     */
    function unpause() external onlyRole(EMERGENCY_ROLE) {
        _unpause();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get the number of supported tokens
     * @return Number of supported tokens
     */
    function getTokenCount() external view returns (uint) {
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
    function getTokenBalance(string memory symbol) external view returns (uint) {
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
    function getUserDistributionHistory(address user)
        external
        view
        returns (DistributionRecord[] memory)
    {
        return userDistributionHistory[user];
    }

    /**
     * @notice Get user's distribution history for a specific token
     * @param user User address
     * @param symbol Token symbol
     * @return Array of distribution records for the specified token
     */
    function getUserTokenHistory(address user, string memory symbol)
        external
        view
        returns (DistributionRecord[] memory)
    {
        DistributionRecord[] memory allHistory = userDistributionHistory[user];
        uint count = 0;

        // Count matching records
        for (uint i = 0; i < allHistory.length; i++) {
            if (keccak256(bytes(allHistory[i].tokenSymbol)) == keccak256(bytes(symbol))) {
                count++;
            }
        }

        // Create filtered array
        DistributionRecord[] memory filteredHistory = new DistributionRecord[](count);
        uint index = 0;
        for (uint i = 0; i < allHistory.length; i++) {
            if (keccak256(bytes(allHistory[i].tokenSymbol)) == keccak256(bytes(symbol))) {
                filteredHistory[index] = allHistory[i];
                index++;
            }
        }

        return filteredHistory;
    }

    /**
     * @notice Check if an account has a specific role
     * @param role Role to check
     * @param account Account to check
     * @return True if account has the role
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return super.hasRole(role, account);
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
    function _validateDistribution(string memory symbol, address to, uint amount) internal view {
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
        uint symbolsLength = tokenSymbols.length;
        for (uint i = 0; i < symbolsLength; i++) {
            if (userReceivedAmounts[user][tokenSymbols[i]] > 0) {
                return false;
            }
        }
        return true;
    }
}
