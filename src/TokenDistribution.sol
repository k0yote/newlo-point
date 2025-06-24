// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Ownable } from "@openzeppelin/contracts/access/Ownable.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { NewLoPoint } from "./NewLoPoint.sol";

/**
 * @title TokenDistribution
 * @author NewLo Team
 * @notice Gas-efficient bulk distribution contract for NewLoPoint tokens using mint-based approach
 * @dev This contract implements:
 *      - Efficient bulk token distribution to multiple users
 *      - Gas usage optimization through batch processing
 *      - Distribution statistics tracking and monitoring
 *      - Comprehensive access control and security features
 *      - Emergency pause functionality for operational safety
 *      - Anti-duplicate distribution protection with configurable settings
 *
 * @dev Security Features:
 *      - Reentrancy protection using OpenZeppelin's ReentrancyGuard
 *      - Pausable functionality for emergency situations
 *      - Owner-only administrative controls
 *      - Batch size limits to prevent gas limit issues
 *      - Optional duplicate distribution prevention
 *      - Comprehensive input validation
 *
 * @dev Gas Optimization Features:
 *      - Single transaction for multiple distributions
 *      - Efficient data structure usage
 *      - Elimination of unnecessary computations
 *      - Batch event emissions for reduced gas costs
 *      - Optimized loop structures with unchecked arithmetic
 *
 * @dev Inheritance Chain:
 *      TokenDistribution
 *      ├── Ownable (administrative control)
 *      ├── ReentrancyGuard (reentrancy attack protection)
 *      └── Pausable (emergency halt functionality)
 */
contract TokenDistribution is Ownable, ReentrancyGuard, Pausable {
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

    /// @notice Flag to enable/disable anti-duplicate distribution protection (prevents distributions within 24 hours)
    bool public antiDuplicateMode;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when a bulk distribution batch is executed
    event BulkDistribution(
        uint indexed batchId, uint recipientCount, uint totalAmount, uint timestamp
    );

    /// @notice Emitted for each individual token distribution within a batch
    event TokenDistributed(
        address indexed recipient, uint amount, uint indexed batchId, uint timestamp
    );

    /// @notice Emitted when anti-duplicate mode setting is changed
    event AntiDuplicateModeChanged(bool enabled);

    /// @notice Emitted when distribution statistics are reset
    event StatsReset(uint timestamp);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error InvalidBatchSize(uint size, uint maxSize);
    error ArrayLengthMismatch(uint recipientsLength, uint amountsLength);
    error ZeroAmount(uint index);
    error ZeroAddress(uint index);
    error DuplicateDistribution(address recipient, uint lastReceived);
    error DistributionFailed(address recipient, uint amount);
    error InsufficientMinterRole();

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initializes the TokenDistribution contract
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
                          BULK DISTRIBUTION FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Distributes equal amounts of tokens to multiple recipients using mint operations
     * @param recipients Array of recipient addresses
     * @param amount Amount of tokens to distribute to each recipient
     * @return batchId ID of the executed distribution batch
     *
     * @dev Uses mint operations for token distribution, optimized for equal-amount distributions
     *
     * Requirements:
     * - Contract must not be paused
     * - Recipients array must not be empty and not exceed MAX_BATCH_SIZE
     * - Amount must be greater than 0
     * - If anti-duplicate mode is enabled, recipients must not have received tokens within 24 hours
     * - This contract must have MINTER_ROLE on the NewLoPoint token
     * - Only owner can call this function
     *
     * Emits:
     * - TokenDistributed event for each recipient
     * - BulkDistribution event for the batch
     */
    function distributeEqual(address[] calldata recipients, uint amount)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint batchId)
    {
        // Check MINTER_ROLE permissions
        if (!nlpToken.hasRole(nlpToken.MINTER_ROLE(), address(this))) {
            revert InsufficientMinterRole();
        }
        uint recipientCount = recipients.length;

        if (recipientCount == 0 || recipientCount > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(recipientCount, MAX_BATCH_SIZE);
        }

        if (amount == 0) {
            revert ZeroAmount(0);
        }

        batchId = totalDistributions + 1;
        uint currentDay = block.timestamp / 86400;
        uint totalAmount = recipientCount * amount;

        // Batch processing for mint operations
        for (uint i = 0; i < recipientCount;) {
            address recipient = recipients[i];

            if (recipient == address(0)) {
                revert ZeroAddress(i);
            }

            // Duplicate distribution check
            if (antiDuplicateMode && _isDuplicateDistribution(recipient)) {
                revert DuplicateDistribution(recipient, userLastReceived[recipient]);
            }

            // Execute mint operation
            try nlpToken.mint(recipient, amount) {
                // Update statistics
                userTotalReceived[recipient] += amount;
                userLastReceived[recipient] = block.timestamp;

                // Emit individual distribution event
                emit TokenDistributed(recipient, amount, batchId, block.timestamp);
            } catch {
                revert DistributionFailed(recipient, amount);
            }

            unchecked {
                ++i;
            }
        }

        // Update global statistics
        totalDistributed += totalAmount;
        totalDistributions = batchId;
        dailyDistributions[currentDay] += totalAmount;

        // Emit bulk distribution event
        emit BulkDistribution(batchId, recipientCount, totalAmount, block.timestamp);
    }

    /**
     * @notice Distributes variable amounts of tokens to multiple recipients using mint operations
     * @param recipients Array of recipient addresses
     * @param amounts Array of token amounts corresponding to each recipient
     * @return batchId ID of the executed distribution batch
     *
     * @dev Provides more flexibility for distributions requiring different amounts per user (slightly higher gas usage)
     *
     * Requirements:
     * - Contract must not be paused
     * - Recipients and amounts arrays must have the same length
     * - Arrays must not be empty and not exceed MAX_BATCH_SIZE
     * - All amounts must be greater than 0
     * - If anti-duplicate mode is enabled, recipients must not have received tokens within 24 hours
     * - This contract must have MINTER_ROLE on the NewLoPoint token
     * - Only owner can call this function
     *
     * Emits:
     * - TokenDistributed event for each recipient
     * - BulkDistribution event for the batch
     */
    function distributeVariable(address[] calldata recipients, uint[] calldata amounts)
        external
        onlyOwner
        whenNotPaused
        nonReentrant
        returns (uint batchId)
    {
        // Check MINTER_ROLE permissions
        if (!nlpToken.hasRole(nlpToken.MINTER_ROLE(), address(this))) {
            revert InsufficientMinterRole();
        }
        uint recipientCount = recipients.length;

        if (recipientCount == 0 || recipientCount > MAX_BATCH_SIZE) {
            revert InvalidBatchSize(recipientCount, MAX_BATCH_SIZE);
        }

        if (recipientCount != amounts.length) {
            revert ArrayLengthMismatch(recipientCount, amounts.length);
        }

        batchId = totalDistributions + 1;
        uint currentDay = block.timestamp / 86400;
        uint totalAmount = 0;

        // Batch processing for mint operations
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

            // Execute mint operation
            try nlpToken.mint(recipient, amount) {
                // Update statistics
                userTotalReceived[recipient] += amount;
                userLastReceived[recipient] = block.timestamp;
                totalAmount += amount;

                // Emit individual distribution event
                emit TokenDistributed(recipient, amount, batchId, block.timestamp);
            } catch {
                revert DistributionFailed(recipient, amount);
            }

            unchecked {
                ++i;
            }
        }

        // Update global statistics
        totalDistributed += totalAmount;
        totalDistributions = batchId;
        dailyDistributions[currentDay] += totalAmount;

        // Emit bulk distribution event
        emit BulkDistribution(batchId, recipientCount, totalAmount, block.timestamp);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Returns comprehensive distribution statistics
     * @return _totalDistributed Total amount of tokens distributed
     * @return _totalDistributions Total number of distribution batches
     * @return _todayDistributed Amount of tokens distributed today
     * @return _isAntiDuplicateEnabled Current state of anti-duplicate mode
     */
    function getDistributionStats()
        external
        view
        returns (
            uint _totalDistributed,
            uint _totalDistributions,
            uint _todayDistributed,
            bool _isAntiDuplicateEnabled
        )
    {
        uint currentDay = block.timestamp / 86400;
        return (
            totalDistributed, totalDistributions, dailyDistributions[currentDay], antiDuplicateMode
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

    /**
     * @notice Returns the amount of tokens distributed on a specific day
     * @param dayTimestamp Timestamp representing the day to query
     * @return amount Amount of tokens distributed on that day
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
     * @notice Resets distribution statistics (emergency function)
     * @dev Warning: This operation is irreversible and should only be used in emergency situations
     *
     * Requirements:
     * - Only owner can call this function
     *
     * Emits:
     * - StatsReset event
     */
    function resetStats() external onlyOwner {
        totalDistributed = 0;
        totalDistributions = 0;
        emit StatsReset(block.timestamp);
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
        // Return false for first-time recipients (lastReceived == 0)
        if (lastReceived == 0) {
            return false;
        }
        return block.timestamp - lastReceived < DISTRIBUTION_HISTORY_PERIOD;
    }
}
