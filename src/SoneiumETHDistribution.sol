// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/**
 * @title SoneiumETHDistribution
 * @author NewLo Team
 * @notice Ultra-efficient bulk ETH distribution contract for Soneium network
 * @dev This contract implements:
 *      - Native ETH distribution with optimized gas usage
 *      - Deposit-distribution-refill cycle management for operational efficiency
 *      - Comprehensive statistics tracking and monitoring capabilities
 *      - Anti-duplicate distribution protection with configurable time windows
 *      - Role-based access control with multiple administrative roles
 *      - Emergency controls and administrative functions
 *
 * @dev Role-based Access Control:
 *      - DEFAULT_ADMIN_ROLE: Full administrative control, can grant/revoke all roles
 *      - DISTRIBUTOR_ROLE: Can execute distribution operations
 *      - DEPOSIT_MANAGER_ROLE: Can deposit and withdraw ETH
 *      - PAUSER_ROLE: Can pause/unpause contract operations
 *
 * @dev Operational Model:
 *      1. Administrator pre-deposits large amounts of ETH into this contract
 *      2. Contract distributes ETH efficiently using optimized batch operations
 *      3. Automatic balance monitoring with low-balance warnings
 *      4. Periodic refills as needed based on distribution patterns
 *
 * @dev Security Model:
 *      - Implements comprehensive reentrancy and pause protections
 *      - Role-based permissions for granular access control
 *      - Emergency withdrawal capabilities
 *      - Low balance monitoring and alerts
 *
 * @dev Inheritance Chain:
 *      SoneiumETHDistribution
 *      ├── AccessControl (role-based access control)
 *      ├── ReentrancyGuard (reentrancy attack protection)
 *      └── Pausable (emergency halt functionality)
 */
contract SoneiumETHDistribution is AccessControl, ReentrancyGuard, Pausable {
    /* ═══════════════════════════════════════════════════════════════════════
                                  ROLES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Role for executing distribution operations
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");

    /// @notice Role for managing ETH deposits and withdrawals
    bytes32 public constant DEPOSIT_MANAGER_ROLE = keccak256("DEPOSIT_MANAGER_ROLE");

    /// @notice Role for pausing and unpausing contract operations
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Maximum number of recipients per batch distribution (gas limit consideration)
    uint public constant MAX_BATCH_SIZE = 500;

    /// @notice Duration for which distribution history is maintained (in seconds)
    uint public constant DISTRIBUTION_HISTORY_PERIOD = 86400; // 24 hours

    /// @notice Balance threshold below which low balance warnings are emitted
    uint public constant LOW_BALANCE_THRESHOLD = 10 ether; // 10 ETH

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Total amount of ETH distributed by this contract
    uint public totalDistributed;

    /// @notice Total number of distribution batches executed
    uint public totalDistributions;

    /// @notice Mapping of user addresses to their total received ETH amounts
    mapping(address => uint) public userTotalReceived;

    /// @notice Mapping of user addresses to their last distribution timestamp
    mapping(address => uint) public userLastReceived;

    /// @notice Mapping of day timestamps to total ETH distributed on that day
    mapping(uint => uint) public dailyDistributions;

    /// @notice Flag to enable/disable anti-duplicate distribution protection
    bool public antiDuplicateMode;

    /// @notice Blacklist for malicious addresses (cannot receive distributions)
    mapping(address => bool) public blacklisted;

    /// @notice Authorized recipients for emergency withdrawals
    mapping(address => bool) public authorizedEmergencyRecipients;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when a bulk distribution batch is executed
    event BulkDistribution(
        uint indexed batchId,
        uint recipientCount,
        uint totalAmount,
        uint remainingBalance,
        uint timestamp
    );

    /// @notice Emitted for each individual ETH distribution within a batch
    event ETHDistributed(
        address indexed recipient, uint amount, uint indexed batchId, uint timestamp
    );

    /// @notice Emitted when ETH is deposited into the contract
    event ETHDeposited(address indexed from, uint amount, uint newBalance);

    /// @notice Emitted when contract balance falls below the low balance threshold
    event LowBalanceWarning(uint currentBalance, uint threshold);

    /// @notice Emitted when anti-duplicate mode setting is changed
    event AntiDuplicateModeChanged(bool enabled);

    /// @notice Emitted when ETH is withdrawn from the contract
    event ETHWithdrawn(address indexed to, uint amount, uint remainingBalance);

    /// @notice Emitted when an address is added to or removed from the blacklist
    event BlacklistUpdated(address indexed account, bool blacklisted);

    /// @notice Emitted when an address is authorized or deauthorized for emergency withdrawals
    event EmergencyRecipientUpdated(address indexed account, bool authorized);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error InvalidBatchSize(uint size, uint maxSize);
    error ArrayLengthMismatch(uint recipientsLength, uint amountsLength);
    error ZeroAmount(uint index);
    error ZeroAddress(uint index);
    error DuplicateDistribution(address recipient, uint lastReceived);
    error InsufficientContractBalance(uint required, uint available);
    error DistributionFailed(address recipient, uint amount);
    error WithdrawalFailed(address to, uint amount);
    error NoETHReceived();
    error BlacklistedAddress(address account);
    error UnauthorizedEmergencyRecipient(address account);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initializes the SoneiumETHDistribution contract
     * @param _defaultAdmin Address that will receive the DEFAULT_ADMIN_ROLE
     *
     * Requirements:
     * - _defaultAdmin must not be the zero address
     */
    constructor(address _defaultAdmin) {
        require(_defaultAdmin != address(0), "Default admin cannot be zero");

        // Grant DEFAULT_ADMIN_ROLE to the specified admin
        _grantRole(DEFAULT_ADMIN_ROLE, _defaultAdmin);

        // Authorize default admin for emergency withdrawals
        authorizedEmergencyRecipients[_defaultAdmin] = true;
    }

    /* ═══════════════════════════════════════════════════════════════════════
                             DEPOSIT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Deposits ETH into the contract for efficient distribution
     * @dev Allows receiving ETH via direct transfer or function call
     *
     * Requirements:
     * - Caller must have DEPOSIT_MANAGER_ROLE or be sending ETH via receive()
     * - Amount must be greater than 0
     *
     * Emits:
     * - ETHDeposited event
     */
    function depositETH() external payable onlyRole(DEPOSIT_MANAGER_ROLE) {
        if (msg.value == 0) {
            revert NoETHReceived();
        }

        uint newBalance = address(this).balance;
        emit ETHDeposited(msg.sender, msg.value, newBalance);
    }

    /**
     * @notice Allows the contract to receive ETH directly
     * @dev Enables simple ETH deposits without calling a specific function
     */
    receive() external payable {
        if (msg.value == 0) {
            revert NoETHReceived();
        }

        uint newBalance = address(this).balance;
        emit ETHDeposited(msg.sender, msg.value, newBalance);
    }

    /**
     * @notice Emergency withdrawal of ETH from the contract
     * @param amount Amount to withdraw (0 for full balance)
     * @param to Address to receive the withdrawn ETH
     *
     * Requirements:
     * - Caller must have DEPOSIT_MANAGER_ROLE
     * - Recipient address must not be zero address
     * - Contract must have sufficient balance
     */
    function emergencyWithdraw(uint amount, address payable to)
        external
        onlyRole(DEPOSIT_MANAGER_ROLE)
    {
        require(to != address(0), "Invalid address");

        // Security: Only allow withdrawals to authorized recipients
        if (!authorizedEmergencyRecipients[to]) {
            revert UnauthorizedEmergencyRecipient(to);
        }

        uint withdrawAmount = amount == 0 ? address(this).balance : amount;
        require(withdrawAmount <= address(this).balance, "Insufficient balance");

        (bool success,) = to.call{ value: withdrawAmount }("");
        if (!success) {
            revert WithdrawalFailed(to, withdrawAmount);
        }

        uint remainingBalance = address(this).balance;
        emit ETHWithdrawn(to, withdrawAmount, remainingBalance);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          BULK DISTRIBUTION FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Distributes equal amounts of ETH to multiple recipients (ultra-efficient version)
     * @param recipients Array of recipient addresses
     * @param amount Amount of ETH to distribute to each recipient
     * @return batchId ID of the executed distribution batch
     *
     * @dev Achieves high efficiency through optimized batch ETH transfers
     *
     * Requirements:
     * - Caller must have DISTRIBUTOR_ROLE
     * - Contract must not be paused
     * - Recipients array must not be empty and not exceed MAX_BATCH_SIZE
     * - Amount must be greater than 0
     * - Contract must have sufficient ETH balance
     * - If anti-duplicate mode is enabled, recipients must not have received ETH within 24 hours
     *
     * Emits:
     * - ETHDistributed event for each recipient
     * - BulkDistribution event for the batch
     * - LowBalanceWarning event if balance falls below threshold
     */
    function distributeEqual(address[] calldata recipients, uint amount)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint batchId)
    {
        uint recipientCount = recipients.length;

        if (recipientCount == 0 || recipientCount > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(recipientCount, MAX_BATCH_SIZE);
        }

        if (amount == 0) {
            revert ZeroAmount(0);
        }

        uint totalRequired = recipientCount * amount;
        uint contractBalance = address(this).balance;

        if (contractBalance < totalRequired) {
            revert InsufficientContractBalance(totalRequired, contractBalance);
        }

        batchId = totalDistributions + 1;
        uint currentDay = block.timestamp / 86400;

        // CEI Pattern: Update global state before external calls
        totalDistributed += totalRequired;
        totalDistributions = batchId;
        dailyDistributions[currentDay] += totalRequired;

        // Efficient batch ETH transfer processing
        for (uint i = 0; i < recipientCount;) {
            address recipient = recipients[i];

            if (recipient == address(0)) {
                revert ZeroAddress(i);
            }

            // Security: Check blacklist
            if (blacklisted[recipient]) {
                revert BlacklistedAddress(recipient);
            }

            // Duplicate distribution check
            if (antiDuplicateMode && _isDuplicateDistribution(recipient)) {
                revert DuplicateDistribution(recipient, userLastReceived[recipient]);
            }

            // CEI Pattern: Effects before Interactions
            // Store previous values in case of revert
            uint previousTotalReceived = userTotalReceived[recipient];
            uint previousLastReceived = userLastReceived[recipient];

            // Update statistics BEFORE external call
            userTotalReceived[recipient] += amount;
            userLastReceived[recipient] = block.timestamp;

            // Execute efficient ETH transfer
            (bool success,) = recipient.call{ value: amount }("");
            if (!success) {
                // Revert state changes if transfer fails
                userTotalReceived[recipient] = previousTotalReceived;
                userLastReceived[recipient] = previousLastReceived;
                revert DistributionFailed(recipient, amount);
            }

            // Emit individual distribution event
            emit ETHDistributed(recipient, amount, batchId, block.timestamp);

            unchecked {
                ++i;
            }
        }

        // Check balance and emit warning if needed
        uint remainingBalance = address(this).balance;
        if (remainingBalance < LOW_BALANCE_THRESHOLD) {
            emit LowBalanceWarning(remainingBalance, LOW_BALANCE_THRESHOLD);
        }

        // Emit bulk distribution event
        emit BulkDistribution(
            batchId, recipientCount, totalRequired, remainingBalance, block.timestamp
        );
    }

    /**
     * @notice Distributes variable amounts of ETH to multiple recipients (ultra-efficient version)
     * @param recipients Array of recipient addresses
     * @param amounts Array of ETH amounts corresponding to each recipient
     * @return batchId ID of the executed distribution batch
     *
     * Requirements:
     * - Caller must have DISTRIBUTOR_ROLE
     * - Contract must not be paused
     * - Recipients and amounts arrays must have the same length
     * - Arrays must not be empty and not exceed MAX_BATCH_SIZE
     * - All amounts must be greater than 0
     * - Contract must have sufficient ETH balance for total distribution
     * - If anti-duplicate mode is enabled, recipients must not have received ETH within 24 hours
     *
     * Emits:
     * - ETHDistributed event for each recipient
     * - BulkDistribution event for the batch
     * - LowBalanceWarning event if balance falls below threshold
     */
    function distributeVariable(address[] calldata recipients, uint[] calldata amounts)
        external
        onlyRole(DISTRIBUTOR_ROLE)
        whenNotPaused
        nonReentrant
        returns (uint batchId)
    {
        uint recipientCount = recipients.length;

        if (recipientCount == 0 || recipientCount > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(recipientCount, MAX_BATCH_SIZE);
        }

        if (recipientCount != amounts.length) {
            revert ArrayLengthMismatch(recipientCount, amounts.length);
        }

        // Calculate total required amount
        uint totalRequired = 0;
        for (uint i = 0; i < recipientCount; i++) {
            totalRequired += amounts[i];
        }

        uint contractBalance = address(this).balance;
        if (contractBalance < totalRequired) {
            revert InsufficientContractBalance(totalRequired, contractBalance);
        }

        batchId = totalDistributions + 1;
        uint currentDay = block.timestamp / 86400;

        // CEI Pattern: Update global state before external calls
        totalDistributed += totalRequired;
        totalDistributions = batchId;
        dailyDistributions[currentDay] += totalRequired;

        // Efficient batch ETH transfer processing
        for (uint i = 0; i < recipientCount;) {
            address recipient = recipients[i];
            uint amount = amounts[i];

            if (recipient == address(0)) {
                revert ZeroAddress(i);
            }

            if (amount == 0) {
                revert ZeroAmount(i);
            }

            // Security: Check blacklist
            if (blacklisted[recipient]) {
                revert BlacklistedAddress(recipient);
            }

            // Duplicate distribution check
            if (antiDuplicateMode && _isDuplicateDistribution(recipient)) {
                revert DuplicateDistribution(recipient, userLastReceived[recipient]);
            }

            // CEI Pattern: Effects before Interactions
            // Store previous values in case of revert
            uint previousTotalReceived = userTotalReceived[recipient];
            uint previousLastReceived = userLastReceived[recipient];

            // Update statistics BEFORE external call
            userTotalReceived[recipient] += amount;
            userLastReceived[recipient] = block.timestamp;

            // Execute efficient ETH transfer
            (bool success,) = recipient.call{ value: amount }("");
            if (!success) {
                // Revert state changes if transfer fails
                userTotalReceived[recipient] = previousTotalReceived;
                userLastReceived[recipient] = previousLastReceived;
                revert DistributionFailed(recipient, amount);
            }

            // Emit individual distribution event
            emit ETHDistributed(recipient, amount, batchId, block.timestamp);

            unchecked {
                ++i;
            }
        }

        // Check balance and emit warning if needed
        uint remainingBalance = address(this).balance;
        if (remainingBalance < LOW_BALANCE_THRESHOLD) {
            emit LowBalanceWarning(remainingBalance, LOW_BALANCE_THRESHOLD);
        }

        // Emit bulk distribution event
        emit BulkDistribution(
            batchId, recipientCount, totalRequired, remainingBalance, block.timestamp
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Returns contract balance information
     * @return balance Current ETH balance of the contract
     * @return isLowBalance True if balance is below the low balance threshold
     */
    function getContractBalance() external view returns (uint balance, bool isLowBalance) {
        balance = address(this).balance;
        isLowBalance = balance < LOW_BALANCE_THRESHOLD;
    }

    /**
     * @notice Calculates maximum number of users that can receive distribution
     * @param amountPerUser Amount of ETH per user
     * @return maxUsers Maximum number of users that can be served with current balance
     */
    function getMaxDistributableUsers(uint amountPerUser) external view returns (uint maxUsers) {
        if (amountPerUser == 0) return 0;
        uint balance = address(this).balance;
        maxUsers = balance / amountPerUser;
        if (maxUsers > MAX_BATCH_SIZE) {
            maxUsers = MAX_BATCH_SIZE;
        }
    }

    /**
     * @notice Returns comprehensive distribution statistics
     * @return _totalDistributed Total amount of ETH distributed
     * @return _totalDistributions Total number of distribution batches
     * @return _todayDistributed Amount of ETH distributed today
     * @return _contractBalance Current contract ETH balance
     * @return _isLowBalance True if balance is below threshold
     * @return _isAntiDuplicateEnabled Current state of anti-duplicate mode
     */
    function getDistributionStats()
        external
        view
        returns (
            uint _totalDistributed,
            uint _totalDistributions,
            uint _todayDistributed,
            uint _contractBalance,
            bool _isLowBalance,
            bool _isAntiDuplicateEnabled
        )
    {
        uint currentDay = block.timestamp / 86400;
        uint balance = address(this).balance;

        return (
            totalDistributed,
            totalDistributions,
            dailyDistributions[currentDay],
            balance,
            balance < LOW_BALANCE_THRESHOLD,
            antiDuplicateMode
        );
    }

    /**
     * @notice Returns distribution information for a specific user
     * @param user Address of the user to query
     * @return totalReceived Total amount of ETH received by the user
     * @return lastReceived Timestamp of user's last ETH receipt
     * @return canReceiveToday True if user can receive ETH today (considering anti-duplicate settings)
     */
    function getUserDistributionInfo(address user)
        external
        view
        returns (uint totalReceived, uint lastReceived, bool canReceiveToday)
    {
        totalReceived = userTotalReceived[user];
        lastReceived = userLastReceived[user];
        canReceiveToday = !antiDuplicateMode || !_isDuplicateDistribution(user);
    }

    /**
     * @notice Returns the amount of ETH distributed on a specific day
     * @param dayTimestamp Timestamp representing the day to query
     * @return amount Amount of ETH distributed on that day
     */
    function getDailyDistribution(uint dayTimestamp) external view returns (uint amount) {
        uint day = dayTimestamp / 86400;
        return dailyDistributions[day];
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               ADMIN FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Enables or disables anti-duplicate distribution mode
     * @param enabled True to enable anti-duplicate mode, false to disable
     *
     * @dev When enabled, prevents users from receiving distributions within 24 hours of their last receipt
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     *
     * Emits:
     * - AntiDuplicateModeChanged event
     */
    function setAntiDuplicateMode(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        antiDuplicateMode = enabled;
        emit AntiDuplicateModeChanged(enabled);
    }

    /**
     * @notice Pauses the contract, preventing all distribution operations
     *
     * Requirements:
     * - Caller must have PAUSER_ROLE
     * - Contract must not already be paused
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpauses the contract, restoring distribution operations
     *
     * Requirements:
     * - Caller must have PAUSER_ROLE
     * - Contract must be paused
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            INTERNAL FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Checks if a distribution to a user would be a duplicate within the time window
     * @param user Address of the user to check
     * @return bool True if distribution would be duplicate, false otherwise
     *
     * @dev Returns false for users who have never received ETH (lastReceived == 0)
     */
    function _isDuplicateDistribution(address user) internal view returns (bool) {
        uint lastReceived = userLastReceived[user];
        if (lastReceived == 0) {
            return false;
        }
        return block.timestamp - lastReceived < DISTRIBUTION_HISTORY_PERIOD;
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          SECURITY MANAGEMENT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Adds or removes an address from the blacklist
     * @param account Address to be blacklisted or unblacklisted
     * @param isBlacklisted True to blacklist, false to unblacklist
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     * - Account must not be zero address
     *
     * Emits:
     * - BlacklistUpdated event
     */
    function setBlacklisted(address account, bool isBlacklisted)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(account != address(0), "Cannot blacklist zero address");

        blacklisted[account] = isBlacklisted;
        emit BlacklistUpdated(account, isBlacklisted);
    }

    /**
     * @notice Authorizes or deauthorizes an address for emergency withdrawals
     * @param account Address to be authorized or deauthorized
     * @param isAuthorized True to authorize, false to deauthorize
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     * - Account must not be zero address
     *
     * Emits:
     * - EmergencyRecipientUpdated event
     */
    function setEmergencyRecipient(address account, bool isAuthorized)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        require(account != address(0), "Cannot authorize zero address");

        authorizedEmergencyRecipients[account] = isAuthorized;
        emit EmergencyRecipientUpdated(account, isAuthorized);
    }

    /**
     * @notice Batch operation to set multiple addresses as blacklisted/unblacklisted
     * @param accounts Array of addresses to update
     * @param isBlacklisted True to blacklist, false to unblacklist
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     * - Arrays must not be empty and not exceed MAX_BATCH_SIZE
     *
     * Emits:
     * - BlacklistUpdated event for each address
     */
    function batchSetBlacklisted(address[] calldata accounts, bool isBlacklisted)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint length = accounts.length;
        require(length > 0 && length <= MAX_BATCH_SIZE, "Invalid batch size");

        for (uint i = 0; i < length; i++) {
            address account = accounts[i];
            require(account != address(0), "Cannot blacklist zero address");

            blacklisted[account] = isBlacklisted;
            emit BlacklistUpdated(account, isBlacklisted);
        }
    }

    /**
     * @notice Batch operation to set multiple addresses as emergency recipients
     * @param accounts Array of addresses to update
     * @param isAuthorized True to authorize, false to deauthorize
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     * - Arrays must not be empty and not exceed MAX_BATCH_SIZE
     *
     * Emits:
     * - EmergencyRecipientUpdated event for each address
     */
    function batchSetEmergencyRecipients(address[] calldata accounts, bool isAuthorized)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        uint length = accounts.length;
        require(length > 0 && length <= MAX_BATCH_SIZE, "Invalid batch size");

        for (uint i = 0; i < length; i++) {
            address account = accounts[i];
            require(account != address(0), "Cannot authorize zero address");

            authorizedEmergencyRecipients[account] = isAuthorized;
            emit EmergencyRecipientUpdated(account, isAuthorized);
        }
    }
}
