// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { NewLoPoint } from "./NewLoPoint.sol";

/**
 * @title TokenDistributionV2
 * @author NewLo Team
 * @notice Ultra-efficient bulk distribution contract for NewLoPoint tokens using transfer-based approach
 * @dev This contract implements:
 *      - Transfer-based token distribution with 92% gas reduction compared to mint-based approach
 *      - Deposit-distribution-refill cycle management for operational efficiency
 *      - Whitelist system integration for secure operations while maintaining transfer restrictions
 *      - Comprehensive statistics tracking and monitoring capabilities
 *      - Anti-duplicate distribution protection with configurable time windows
 *      - Emergency controls and administrative functions
 *
 * @dev Operational Model:
 *      1. Administrator pre-deposits large amounts of tokens into this contract
 *      2. Contract distributes tokens efficiently using transfer operations
 *      3. Automatic balance monitoring with low-balance warnings
 *      4. Periodic refills as needed based on distribution patterns
 *
 * @dev Setup Requirements (Critical):
 *      1. Deploy TokenDistributionV2 contract
 *      2. Configure NewLoPoint token settings:
 *         - setWhitelistModeEnabled(true)  // Enable whitelist functionality
 *         - setWhitelistedAddress(thisContract, true)  // Add this contract to whitelist
 *      3. With transfersEnabled=false, only this contract can perform transfers
 *      4. Administrator deposits large token amounts into this contract
 *      5. Begin ultra-efficient distribution operations
 *
 * @dev Gas Efficiency Comparison (100 users distribution):
 *      - Mint-based approach: 7,709,344 gas
 *      - Transfer-based approach: 572,551 gas
 *      - Efficiency improvement: 92% reduction
 *
 * @dev Security Model:
 *      - Leverages NewLoPoint's whitelist system for access control
 *      - Operates even when transfersEnabled=false for general users
 *      - Maintains transfer restrictions for regular users
 *      - Preserves full administrative control for token managers
 *      - Implements comprehensive reentrancy and pause protections
 *
 * @dev Inheritance Chain:
 *      TokenDistributionV2
 *      ├── Ownable (administrative control)
 *      ├── ReentrancyGuard (reentrancy attack protection)
 *      └── Pausable (emergency halt functionality)
 */
contract TokenDistributionV2 is Ownable, ReentrancyGuard, Pausable {
    /* ═══════════════════════════════════════════════════════════════════════
                               IMMUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice The NewLoPoint token contract that this contract distributes
    NewLoPoint public immutable nlpToken;

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Maximum number of recipients per batch distribution (gas limit consideration)
    uint public constant MAX_BATCH_SIZE = 500;

    /// @notice Duration for which distribution history is maintained (in seconds)
    uint public constant DISTRIBUTION_HISTORY_PERIOD = 86400; // 24 hours

    /// @notice Balance threshold below which low balance warnings are emitted
    uint public constant LOW_BALANCE_THRESHOLD = 10000 * 10 ** 18; // 10,000 NLP

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Total amount of tokens distributed by this contract
    uint public totalDistributed;

    /// @notice Total number of distribution batches executed
    uint public totalDistributions;

    /// @notice Mapping of user addresses to their total received token amounts
    mapping(address => uint) public userTotalReceived;

    /// @notice Mapping of user addresses to their last distribution timestamp
    mapping(address => uint) public userLastReceived;

    /// @notice Mapping of day timestamps to total tokens distributed on that day
    mapping(uint => uint) public dailyDistributions;

    /// @notice Flag to enable/disable anti-duplicate distribution protection
    bool public antiDuplicateMode;

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

    /// @notice Emitted for each individual token distribution within a batch
    event TokenDistributed(
        address indexed recipient, uint amount, uint indexed batchId, uint timestamp
    );

    /// @notice Emitted when tokens are deposited into the contract
    event TokensDeposited(address indexed from, uint amount, uint newBalance);

    /// @notice Emitted when contract balance falls below the low balance threshold
    event LowBalanceWarning(uint currentBalance, uint threshold);

    /// @notice Emitted when anti-duplicate mode setting is changed
    event AntiDuplicateModeChanged(bool enabled);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error InvalidBatchSize(uint size, uint maxSize);
    error ArrayLengthMismatch(uint recipientsLength, uint amountsLength);
    error ZeroAmount(uint index);
    error ZeroAddress(uint index);
    error DuplicateDistribution(address recipient, uint lastReceived);
    error InsufficientContractBalance(uint required, uint available);
    error DepositFailed(uint amount);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initializes the TokenDistributionV2 contract
     * @param _nlpToken Address of the NewLoPoint token contract to distribute
     * @param _initialOwner Address that will become the owner of this contract
     *
     * Requirements:
     * - _nlpToken must not be the zero address
     * - _initialOwner must not be the zero address
     */
    constructor(address _nlpToken, address _initialOwner) Ownable(_initialOwner) {
        require(_nlpToken != address(0), "NLP token address cannot be zero");
        require(_initialOwner != address(0), "Initial owner cannot be zero");

        nlpToken = NewLoPoint(_nlpToken);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                             DEPOSIT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Deposits tokens into the contract for efficient distribution
     * @param amount Amount of tokens to deposit
     *
     * @dev Administrator pre-deposits large token amounts to enable efficient distribution
     *
     * Requirements:
     * - Only owner can call this function
     * - Amount must be greater than 0
     * - Administrator must have set sufficient allowance for this contract
     *
     * Emits:
     * - TokensDeposited event
     */
    function depositTokens(uint amount) external onlyOwner {
        require(amount > 0, "Amount must be greater than 0");

        bool success = nlpToken.transferFrom(msg.sender, address(this), amount);
        if (!success) {
            revert DepositFailed(amount);
        }

        uint newBalance = nlpToken.balanceOf(address(this));
        emit TokensDeposited(msg.sender, amount, newBalance);
    }

    /**
     * @notice Emergency withdrawal of tokens from the contract
     * @param amount Amount to withdraw (0 for full balance)
     * @param to Address to receive the withdrawn tokens
     *
     * Requirements:
     * - Only owner can call this function
     * - Recipient address must not be zero address
     * - Contract must have sufficient balance
     */
    function emergencyWithdraw(uint amount, address to) external onlyOwner {
        require(to != address(0), "Invalid address");

        uint withdrawAmount = amount == 0 ? nlpToken.balanceOf(address(this)) : amount;
        require(withdrawAmount <= nlpToken.balanceOf(address(this)), "Insufficient balance");

        nlpToken.transfer(to, withdrawAmount);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          BULK DISTRIBUTION FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Distributes equal amounts of tokens to multiple recipients (ultra-efficient version)
     * @param recipients Array of recipient addresses
     * @param amount Amount of tokens to distribute to each recipient
     * @return batchId ID of the executed distribution batch
     *
     * @dev Achieves 92% gas reduction compared to mint-based approach through transfer operations
     *
     * Requirements:
     * - Only owner can call this function
     * - Contract must not be paused
     * - Recipients array must not be empty and not exceed MAX_BATCH_SIZE
     * - Amount must be greater than 0
     * - Contract must have sufficient token balance
     * - If anti-duplicate mode is enabled, recipients must not have received tokens within 24 hours
     *
     * Emits:
     * - TokenDistributed event for each recipient
     * - BulkDistribution event for the batch
     * - LowBalanceWarning event if balance falls below threshold
     */
    function distributeEqual(address[] calldata recipients, uint amount)
        external
        onlyOwner
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
        uint contractBalance = nlpToken.balanceOf(address(this));

        if (contractBalance < totalRequired) {
            revert InsufficientContractBalance(totalRequired, contractBalance);
        }

        batchId = totalDistributions + 1;
        uint currentDay = block.timestamp / 86400;

        // Efficient batch transfer processing
        for (uint i = 0; i < recipientCount;) {
            address recipient = recipients[i];

            if (recipient == address(0)) {
                revert ZeroAddress(i);
            }

            // Duplicate distribution check
            if (antiDuplicateMode && _isDuplicateDistribution(recipient)) {
                revert DuplicateDistribution(recipient, userLastReceived[recipient]);
            }

            // Execute efficient transfer
            nlpToken.transfer(recipient, amount);

            // Update statistics
            userTotalReceived[recipient] += amount;
            userLastReceived[recipient] = block.timestamp;

            // Emit individual distribution event
            emit TokenDistributed(recipient, amount, batchId, block.timestamp);

            unchecked {
                ++i;
            }
        }

        // Update global statistics
        totalDistributed += totalRequired;
        totalDistributions = batchId;
        dailyDistributions[currentDay] += totalRequired;

        // Check balance and emit warning if needed
        uint remainingBalance = nlpToken.balanceOf(address(this));
        if (remainingBalance < LOW_BALANCE_THRESHOLD) {
            emit LowBalanceWarning(remainingBalance, LOW_BALANCE_THRESHOLD);
        }

        // Emit bulk distribution event
        emit BulkDistribution(
            batchId, recipientCount, totalRequired, remainingBalance, block.timestamp
        );
    }

    /**
     * @notice Distributes variable amounts of tokens to multiple recipients (ultra-efficient version)
     * @param recipients Array of recipient addresses
     * @param amounts Array of token amounts corresponding to each recipient
     * @return batchId ID of the executed distribution batch
     *
     * Requirements:
     * - Only owner can call this function
     * - Contract must not be paused
     * - Recipients and amounts arrays must have the same length
     * - Arrays must not be empty and not exceed MAX_BATCH_SIZE
     * - All amounts must be greater than 0
     * - Contract must have sufficient token balance for total distribution
     * - If anti-duplicate mode is enabled, recipients must not have received tokens within 24 hours
     *
     * Emits:
     * - TokenDistributed event for each recipient
     * - BulkDistribution event for the batch
     * - LowBalanceWarning event if balance falls below threshold
     */
    function distributeVariable(address[] calldata recipients, uint[] calldata amounts)
        external
        onlyOwner
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

        uint contractBalance = nlpToken.balanceOf(address(this));
        if (contractBalance < totalRequired) {
            revert InsufficientContractBalance(totalRequired, contractBalance);
        }

        batchId = totalDistributions + 1;
        uint currentDay = block.timestamp / 86400;

        // Efficient batch transfer processing
        for (uint i = 0; i < recipientCount;) {
            address recipient = recipients[i];
            uint amount = amounts[i];

            if (recipient == address(0)) {
                revert ZeroAddress(i);
            }

            if (amount == 0) {
                revert ZeroAmount(i);
            }

            // Duplicate distribution check
            if (antiDuplicateMode && _isDuplicateDistribution(recipient)) {
                revert DuplicateDistribution(recipient, userLastReceived[recipient]);
            }

            // Execute efficient transfer
            nlpToken.transfer(recipient, amount);

            // Update statistics
            userTotalReceived[recipient] += amount;
            userLastReceived[recipient] = block.timestamp;

            // Emit individual distribution event
            emit TokenDistributed(recipient, amount, batchId, block.timestamp);

            unchecked {
                ++i;
            }
        }

        // Update global statistics
        totalDistributed += totalRequired;
        totalDistributions = batchId;
        dailyDistributions[currentDay] += totalRequired;

        // Check balance and emit warning if needed
        uint remainingBalance = nlpToken.balanceOf(address(this));
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
     * @return balance Current token balance of the contract
     * @return isLowBalance True if balance is below the low balance threshold
     */
    function getContractBalance() external view returns (uint balance, bool isLowBalance) {
        balance = nlpToken.balanceOf(address(this));
        isLowBalance = balance < LOW_BALANCE_THRESHOLD;
    }

    /**
     * @notice Calculates maximum number of users that can receive distribution
     * @param amountPerUser Amount of tokens per user
     * @return maxUsers Maximum number of users that can be served with current balance
     */
    function getMaxDistributableUsers(uint amountPerUser) external view returns (uint maxUsers) {
        if (amountPerUser == 0) return 0;
        uint balance = nlpToken.balanceOf(address(this));
        maxUsers = balance / amountPerUser;
        if (maxUsers > MAX_BATCH_SIZE) {
            maxUsers = MAX_BATCH_SIZE;
        }
    }

    /**
     * @notice Returns comprehensive distribution statistics
     * @return _totalDistributed Total amount of tokens distributed
     * @return _totalDistributions Total number of distribution batches
     * @return _todayDistributed Amount distributed today
     * @return _contractBalance Current contract balance
     * @return _isLowBalance True if balance is below threshold
     * @return _isAntiDuplicateEnabled True if anti-duplicate mode is enabled
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
        uint balance = nlpToken.balanceOf(address(this));

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
     * @return totalReceived Total amount of tokens received by the user
     * @return lastReceived Timestamp of user's last token receipt
     * @return canReceiveToday True if user can receive tokens today (considering anti-duplicate settings)
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

    /* ═══════════════════════════════════════════════════════════════════════
                              SETUP FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Automated setup for efficient distribution operations (administrative function)
     * @dev Configures all necessary settings for this contract to operate efficiently
     * @dev Requires administrative privileges on the NewLoPoint token contract
     *
     * @param depositAmount Initial deposit amount (0 to skip deposit)
     *
     * Requirements:
     * - Only owner can call this function
     * - Caller must have WHITELIST_MANAGER_ROLE or DEFAULT_ADMIN_ROLE on NewLoPoint token
     *
     * Actions Performed:
     * 1. Enables whitelist mode on NewLoPoint token
     * 2. Adds this contract to the NewLoPoint whitelist
     * 3. Deposits specified amount if greater than 0
     *
     * Emits:
     * - TokensDeposited event if deposit amount > 0
     */
    function setupForEfficientDistribution(uint depositAmount) external onlyOwner {
        // Step 1: Enable whitelist mode on token contract
        try nlpToken.setWhitelistModeEnabled(true) {
            // Success - whitelist mode enabled
        } catch {
            // Already enabled or insufficient permissions - continue
        }

        // Step 2: Add this contract to whitelist
        try nlpToken.setWhitelistedAddress(address(this), true) {
            // Success - contract whitelisted
        } catch {
            // Insufficient permissions or already whitelisted
            revert(
                "Setup failed: Cannot whitelist this contract. Please ensure you have WHITELIST_MANAGER_ROLE on the token contract."
            );
        }

        // Step 3: Initial deposit if specified
        if (depositAmount > 0) {
            bool success = nlpToken.transferFrom(msg.sender, address(this), depositAmount);
            if (!success) {
                revert DepositFailed(depositAmount);
            }

            uint newBalance = nlpToken.balanceOf(address(this));
            emit TokensDeposited(msg.sender, depositAmount, newBalance);
        }
    }

    /**
     * @notice Checks the current setup status of the contract
     * @return isWhitelistModeEnabled True if whitelist mode is enabled on token contract
     * @return isContractWhitelisted True if this contract is whitelisted
     * @return contractBalance Current token balance of this contract
     * @return canDistribute True if contract is ready to perform distributions
     */
    function checkSetupStatus()
        external
        view
        returns (
            bool isWhitelistModeEnabled,
            bool isContractWhitelisted,
            uint contractBalance,
            bool canDistribute
        )
    {
        isWhitelistModeEnabled = nlpToken.whitelistModeEnabled();
        isContractWhitelisted = nlpToken.whitelistedAddresses(address(this));
        contractBalance = nlpToken.balanceOf(address(this));

        // Distribution is possible if:
        // 1. Global transfers are enabled, OR
        // 2. Whitelist mode is enabled AND this contract is whitelisted
        canDistribute =
            nlpToken.transfersEnabled() || (isWhitelistModeEnabled && isContractWhitelisted);
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
     * - Only owner can call this function
     *
     * Emits:
     * - AntiDuplicateModeChanged event
     */
    function setAntiDuplicateMode(bool enabled) external onlyOwner {
        antiDuplicateMode = enabled;
        emit AntiDuplicateModeChanged(enabled);
    }

    /**
     * @notice Pauses the contract, preventing all distribution operations
     *
     * Requirements:
     * - Only owner can call this function
     * - Contract must not already be paused
     */
    function pause() external onlyOwner {
        _pause();
    }

    /**
     * @notice Unpauses the contract, restoring distribution operations
     *
     * Requirements:
     * - Only owner can call this function
     * - Contract must be paused
     */
    function unpause() external onlyOwner {
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
     * @dev Returns false for users who have never received tokens (lastReceived == 0)
     */
    function _isDuplicateDistribution(address user) internal view returns (bool) {
        uint lastReceived = userLastReceived[user];
        if (lastReceived == 0) {
            return false;
        }
        return block.timestamp - lastReceived < DISTRIBUTION_HISTORY_PERIOD;
    }
}
