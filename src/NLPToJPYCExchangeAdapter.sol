// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { Math } from "@openzeppelin/contracts/utils/math/Math.sol";
import { IERC20Extended } from "./interfaces/IERC20Extended.sol";

/**
 * @title NLPToJPYCExchangeAdapter
 * @author NewLo Team
 * @notice Cross-chain exchange adapter for NLP (Soneium) to JPYC (Polygon) conversion
 * @dev This contract provides an escrow service for NLP tokens to facilitate cross-chain JPYC exchanges
 *
 * @dev Key Features:
 *      - User-specific NLP escrow system on Soneium
 *      - Operator-controlled burn and transfer functionality
 *      - Configurable NLP to JPYC exchange rate (no oracle required)
 *      - Role-based access control for operations
 *      - Emergency pause functionality
 *      - Comprehensive event logging for off-chain tracking
 *
 * @dev Cross-Chain Exchange Flow:
 *      Since JPYC exists on Polygon network and NLP exists on Soneium network:
 *      1. User deposits NLP tokens into escrow on Soneium (this contract)
 *      2. Off-chain system sends JPYC to user on Polygon network from operational wallet
 *      3a. SUCCESS: Operator burns escrowed NLP on Soneium
 *      3b. FAILURE: Operator returns escrowed NLP to user on Soneium
 *
 * @dev Important Notes:
 *      - JPYC token does NOT exist on Soneium network
 *      - JPYC transfers happen on Polygon network via operational wallet
 *      - This contract only handles NLP escrow/burn/transfer on Soneium
 *      - Exchange rate is for calculation reference only, not enforced on-chain
 *
 * @dev Security Features:
 *      - Reentrancy protection
 *      - Pausable for emergency stops
 *      - Role-based access control (ADMIN, OPERATOR, CONFIG)
 *      - Comprehensive input validation
 *      - CEI (Checks-Effects-Interactions) pattern
 *
 * @dev Access Control Roles:
 *      - DEFAULT_ADMIN_ROLE: Super admin with all permissions
 *      - OPERATOR_ROLE: Can burn and transfer escrowed NLP
 *      - CONFIG_ROLE: Can update exchange rate and configurations
 *      - PAUSER_ROLE: Can pause/unpause the contract
 */
contract NLPToJPYCExchangeAdapter is AccessControl, ReentrancyGuard, Pausable {
    /* ═══════════════════════════════════════════════════════════════════════
                                   ENUMS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Supported token type for exchange
    /// @dev Only JPYC is supported in this adapter (exists on Polygon network)
    enum TokenType {
        JPYC // Japanese Yen Coin on Polygon network
    }

    /// @notice Exchange access control modes
    enum ExchangeMode {
        WHITELIST, // Only whitelisted addresses can deposit
        PUBLIC // Anyone can deposit (default)
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                   STRUCTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice User escrow information
    struct UserEscrow {
        uint totalDeposited; // Total NLP deposited by user
        uint totalWithdrawn; // Total NLP withdrawn by user
        uint totalBurned; // Total NLP burned for user
        uint currentBalance; // Current escrowed NLP balance
        uint depositCount; // Number of deposits
        uint lastDepositTime; // Last deposit timestamp
    }

    /// @notice Exchange statistics
    struct ExchangeStats {
        uint totalDeposited; // Total NLP deposited across all users
        uint totalWithdrawn; // Total NLP withdrawn across all users
        uint totalBurned; // Total NLP burned across all users
        uint totalTransferred; // Total NLP transferred across all users
        uint activeUsers; // Number of users with active escrow balance
        uint totalTransactions; // Total number of transactions
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               IMMUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice NewLo Point token contract on Soneium network
    IERC20Extended public immutable nlpToken;

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Exchange rate numerator: NLP to JPYC (100 for 1 JPYC per NLP)
    uint public nlpToJpycRate = 100;

    /// @notice Rate denominator for NLP to JPYC conversion (e.g., 100 for 1.0 JPYC per NLP)
    uint public constant RATE_DENOMINATOR = 100;

    /// @notice Minimum deposit amount (to prevent dust attacks)
    uint public minDepositAmount = 1e18; // 1 NLP

    /// @notice Access control roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant CONFIG_ROLE = keccak256("CONFIG_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice User escrow balances
    mapping(address => UserEscrow) public userEscrows;

    /// @notice Global exchange statistics
    ExchangeStats public exchangeStats;

    /// @notice Treasury address for emergency withdrawals
    address public treasury;

    /// @notice Current exchange mode (defaults to PUBLIC)
    ExchangeMode public exchangeMode = ExchangeMode.PUBLIC;

    /// @notice Whitelist for deposit access (used in WHITELIST mode)
    mapping(address => bool) public whitelist;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when user deposits NLP into escrow on Soneium
    /// @param user User address who deposited
    /// @param nlpAmount Amount of NLP deposited
    /// @param currentBalance User's current escrow balance
    /// @param jpycEquivalent Equivalent JPYC amount (reference only, actual JPYC on Polygon)
    event Deposited(address indexed user, uint nlpAmount, uint currentBalance, uint jpycEquivalent);

    /// @notice Emitted when user withdraws NLP from escrow on Soneium
    event Withdrawn(address indexed user, uint nlpAmount, uint remainingBalance);

    /// @notice Emitted when operator burns escrowed NLP (after successful JPYC transfer on Polygon)
    /// @param user User who received JPYC on Polygon
    /// @param operator Operator who executed the burn
    /// @param nlpAmount Amount of NLP burned on Soneium
    /// @param jpycEquivalent Equivalent JPYC amount sent on Polygon (reference)
    /// @param reason Reason for burning (e.g., transaction hash on Polygon)
    event EscrowedNLPBurned(
        address indexed user,
        address indexed operator,
        uint nlpAmount,
        uint jpycEquivalent,
        string reason
    );

    /// @notice Emitted when operator transfers escrowed NLP back (after failed JPYC transfer)
    /// @param from Original user who deposited
    /// @param to Destination address (usually same as from for refunds)
    /// @param operator Operator who executed the transfer
    /// @param nlpAmount Amount of NLP transferred
    /// @param reason Reason for transfer (e.g., "JPYC transfer failed", "User refund")
    event EscrowedNLPTransferred(
        address indexed from,
        address indexed to,
        address indexed operator,
        uint nlpAmount,
        string reason
    );

    /// @notice Emitted when NLP to JPYC rate is updated
    event RateUpdated(uint oldRate, uint newRate, address updatedBy);

    /// @notice Emitted when minimum deposit amount is updated
    event MinDepositAmountUpdated(uint oldAmount, uint newAmount, address updatedBy);

    /// @notice Emitted when treasury address is updated
    event TreasuryUpdated(address indexed oldTreasury, address indexed newTreasury);

    /// @notice Emitted when emergency withdrawal is executed
    event EmergencyWithdraw(address indexed to, uint amount, address executor);

    /// @notice Emitted when exchange mode is updated
    event ExchangeModeUpdated(ExchangeMode oldMode, ExchangeMode newMode, address updatedBy);

    /// @notice Emitted when address is added/removed from whitelist
    event WhitelistUpdated(address indexed account, bool whitelisted, address updatedBy);

    /// @notice Emitted when gasless deposit with permit is executed
    event GaslessDepositExecuted(
        address indexed user, address indexed relayer, uint nlpAmount, uint jpycEquivalent
    );

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error ZeroAddress();
    error ZeroAmount();
    error InsufficientBalance(address user, uint requested, uint available);
    error BelowMinimumDeposit(uint amount, uint minimum);
    error InvalidRate(uint rate);
    error TransferFailed();
    error BurnFailed();
    error TreasuryNotSet();
    error InvalidAmount(uint amount);
    error NoEscrowBalance(address user);
    error NotWhitelisted(address user);
    error PermitFailed(address user, uint nlpAmount, uint deadline);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the NLP to JPYC exchange adapter
     * @param _nlpToken NewLo Point token contract address on Soneium
     * @param _initialAdmin Initial admin of the contract
     * @dev JPYC token is NOT stored as it exists on Polygon network, not Soneium
     */
    constructor(address _nlpToken, address _initialAdmin) {
        if (_nlpToken == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();

        nlpToken = IERC20Extended(_nlpToken);

        // Set up access control roles
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(OPERATOR_ROLE, _initialAdmin);
        _grantRole(CONFIG_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(WHITELIST_MANAGER_ROLE, _initialAdmin);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ESCROW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Deposit NLP tokens into escrow
     * @param nlpAmount Amount of NLP tokens to deposit
     * @dev User must approve this contract to spend NLP tokens first
     */
    function depositNLP(uint nlpAmount) external nonReentrant whenNotPaused {
        if (nlpAmount == 0) revert ZeroAmount();
        if (nlpAmount < minDepositAmount) revert BelowMinimumDeposit(nlpAmount, minDepositAmount);

        // Check deposit permission
        _checkExchangePermission(msg.sender);

        address user = msg.sender;
        UserEscrow storage escrow = userEscrows[user];

        // Track active users
        if (escrow.currentBalance == 0 && nlpAmount > 0) {
            unchecked {
                exchangeStats.activeUsers += 1;
            }
        }

        // Update user escrow
        unchecked {
            escrow.totalDeposited += nlpAmount;
            escrow.currentBalance += nlpAmount;
            escrow.depositCount += 1;
            escrow.lastDepositTime = block.timestamp;
        }

        // Update global statistics
        unchecked {
            exchangeStats.totalDeposited += nlpAmount;
            exchangeStats.totalTransactions += 1;
        }

        // Calculate JPYC equivalent for event
        uint jpycEquivalent = calculateJPYCAmount(nlpAmount);

        emit Deposited(user, nlpAmount, escrow.currentBalance, jpycEquivalent);

        // Transfer NLP tokens from user to this contract
        if (!nlpToken.transferFrom(user, address(this), nlpAmount)) revert TransferFailed();
    }

    /**
     * @notice Deposit NLP tokens using permit (gasless transaction)
     * @param nlpAmount Amount of NLP tokens to deposit
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @param user User address (token owner)
     * @dev Allows gasless deposits via EIP-2612 permit
     */
    function depositNLPWithPermit(
        uint nlpAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address user
    ) external nonReentrant whenNotPaused {
        if (nlpAmount == 0) revert ZeroAmount();
        if (nlpAmount < minDepositAmount) revert BelowMinimumDeposit(nlpAmount, minDepositAmount);
        if (user == address(0)) revert ZeroAddress();

        // Check deposit permission for relayer (operator)
        _checkExchangePermission(msg.sender);

        // Execute permit
        try nlpToken.permit(user, address(this), nlpAmount, deadline, v, r, s) {
        // Permit successful
        }
        catch {
            revert PermitFailed(user, nlpAmount, deadline);
        }

        UserEscrow storage escrow = userEscrows[user];

        // Track active users
        if (escrow.currentBalance == 0 && nlpAmount > 0) {
            unchecked {
                exchangeStats.activeUsers += 1;
            }
        }

        // Update user escrow
        unchecked {
            escrow.totalDeposited += nlpAmount;
            escrow.currentBalance += nlpAmount;
            escrow.depositCount += 1;
            escrow.lastDepositTime = block.timestamp;
        }

        // Update global statistics
        unchecked {
            exchangeStats.totalDeposited += nlpAmount;
            exchangeStats.totalTransactions += 1;
        }

        // Calculate JPYC equivalent for event
        uint jpycEquivalent = calculateJPYCAmount(nlpAmount);

        emit GaslessDepositExecuted(user, msg.sender, nlpAmount, jpycEquivalent);

        // Transfer NLP tokens from user to this contract
        if (!nlpToken.transferFrom(user, address(this), nlpAmount)) revert TransferFailed();
    }

    /**
     * @notice Withdraw NLP tokens from escrow
     * @param nlpAmount Amount of NLP tokens to withdraw (0 for all)
     * @dev User can only withdraw their own escrowed tokens
     */
    function withdrawNLP(uint nlpAmount) external nonReentrant whenNotPaused {
        address user = msg.sender;
        UserEscrow storage escrow = userEscrows[user];

        uint availableBalance = escrow.currentBalance;
        if (availableBalance == 0) revert NoEscrowBalance(user);

        uint withdrawAmount = nlpAmount == 0 ? availableBalance : nlpAmount;
        if (withdrawAmount > availableBalance) {
            revert InsufficientBalance(user, withdrawAmount, availableBalance);
        }

        // Update user escrow
        unchecked {
            escrow.totalWithdrawn += withdrawAmount;
            escrow.currentBalance -= withdrawAmount;
        }

        // Track active users
        if (escrow.currentBalance == 0) {
            unchecked {
                exchangeStats.activeUsers -= 1;
            }
        }

        // Update global statistics
        unchecked {
            exchangeStats.totalWithdrawn += withdrawAmount;
            exchangeStats.totalTransactions += 1;
        }

        emit Withdrawn(user, withdrawAmount, escrow.currentBalance);

        // Transfer NLP tokens back to user
        if (!nlpToken.transfer(user, withdrawAmount)) revert TransferFailed();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          OPERATOR FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Burn escrowed NLP tokens (called after successful JPYC transfer)
     * @param user User address whose NLP will be burned
     * @param nlpAmount Amount of NLP tokens to burn
     * @param reason Reason for burning (for off-chain tracking)
     * @dev Only callable by OPERATOR_ROLE
     */
    function burnEscrowedNLP(address user, uint nlpAmount, string calldata reason)
        external
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        if (user == address(0)) revert ZeroAddress();
        if (nlpAmount == 0) revert ZeroAmount();

        UserEscrow storage escrow = userEscrows[user];
        uint availableBalance = escrow.currentBalance;

        if (availableBalance == 0) revert NoEscrowBalance(user);
        if (nlpAmount > availableBalance) {
            revert InsufficientBalance(user, nlpAmount, availableBalance);
        }

        // Update user escrow
        unchecked {
            escrow.totalBurned += nlpAmount;
            escrow.currentBalance -= nlpAmount;
        }

        // Track active users
        if (escrow.currentBalance == 0) {
            unchecked {
                exchangeStats.activeUsers -= 1;
            }
        }

        // Update global statistics
        unchecked {
            exchangeStats.totalBurned += nlpAmount;
            exchangeStats.totalTransactions += 1;
        }

        // Calculate JPYC equivalent for event
        uint jpycEquivalent = calculateJPYCAmount(nlpAmount);

        emit EscrowedNLPBurned(user, msg.sender, nlpAmount, jpycEquivalent, reason);

        // Burn NLP tokens
        try nlpToken.burn(nlpAmount) {
        // Burn successful
        }
        catch {
            revert BurnFailed();
        }
    }

    /**
     * @notice Transfer escrowed NLP tokens (to return to user or transfer elsewhere)
     * @param from User address whose NLP will be transferred
     * @param to Destination address (typically the user for refunds)
     * @param nlpAmount Amount of NLP tokens to transfer
     * @param reason Reason for transfer (for off-chain tracking)
     * @dev Only callable by OPERATOR_ROLE
     */
    function transferEscrowedNLP(address from, address to, uint nlpAmount, string calldata reason)
        external
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        if (from == address(0)) revert ZeroAddress();
        if (to == address(0)) revert ZeroAddress();
        if (nlpAmount == 0) revert ZeroAmount();

        UserEscrow storage escrow = userEscrows[from];
        uint availableBalance = escrow.currentBalance;

        if (availableBalance == 0) revert NoEscrowBalance(from);
        if (nlpAmount > availableBalance) {
            revert InsufficientBalance(from, nlpAmount, availableBalance);
        }

        // Update user escrow
        unchecked {
            escrow.currentBalance -= nlpAmount;
        }

        // Track active users
        if (escrow.currentBalance == 0) {
            unchecked {
                exchangeStats.activeUsers -= 1;
            }
        }

        // Update global statistics
        unchecked {
            exchangeStats.totalTransferred += nlpAmount;
            exchangeStats.totalTransactions += 1;
        }

        emit EscrowedNLPTransferred(from, to, msg.sender, nlpAmount, reason);

        // Transfer NLP tokens to destination
        if (!nlpToken.transfer(to, nlpAmount)) revert TransferFailed();
    }

    /**
     * @notice Batch burn escrowed NLP tokens for multiple users
     * @param users Array of user addresses
     * @param nlpAmounts Array of NLP amounts to burn for each user
     * @param reason Reason for burning (applies to all)
     * @dev Only callable by OPERATOR_ROLE
     */
    function batchBurnEscrowedNLP(
        address[] calldata users,
        uint[] calldata nlpAmounts,
        string calldata reason
    ) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) {
        require(users.length == nlpAmounts.length, "Array length mismatch");

        for (uint i = 0; i < users.length; i++) {
            if (users[i] == address(0)) continue;
            if (nlpAmounts[i] == 0) continue;

            UserEscrow storage escrow = userEscrows[users[i]];
            uint availableBalance = escrow.currentBalance;

            if (availableBalance == 0) continue;
            if (nlpAmounts[i] > availableBalance) continue;

            // Update user escrow
            unchecked {
                escrow.totalBurned += nlpAmounts[i];
                escrow.currentBalance -= nlpAmounts[i];
            }

            // Track active users
            if (escrow.currentBalance == 0) {
                unchecked {
                    exchangeStats.activeUsers -= 1;
                }
            }

            // Update global statistics
            unchecked {
                exchangeStats.totalBurned += nlpAmounts[i];
                exchangeStats.totalTransactions += 1;
            }

            uint jpycEquivalent = calculateJPYCAmount(nlpAmounts[i]);
            emit EscrowedNLPBurned(users[i], msg.sender, nlpAmounts[i], jpycEquivalent, reason);

            // Burn NLP tokens
            try nlpToken.burn(nlpAmounts[i]) {
            // Burn successful
            }
            catch {
                revert BurnFailed();
            }
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                        CONFIGURATION FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Update the NLP to JPYC exchange rate
     * @param newRate New exchange rate numerator (e.g., 90 for 0.9 JPYC per NLP when denominator is 100)
     * @dev The actual rate is calculated as: newRate / RATE_DENOMINATOR
     */
    function updateNLPToJPYCRate(uint newRate) external onlyRole(CONFIG_ROLE) {
        if (newRate == 0) revert InvalidRate(newRate);
        uint oldRate = nlpToJpycRate;
        nlpToJpycRate = newRate;
        emit RateUpdated(oldRate, newRate, msg.sender);
    }

    /**
     * @notice Update the minimum deposit amount
     * @param newMinAmount New minimum deposit amount
     */
    function updateMinDepositAmount(uint newMinAmount) external onlyRole(CONFIG_ROLE) {
        if (newMinAmount == 0) revert InvalidAmount(newMinAmount);
        uint oldAmount = minDepositAmount;
        minDepositAmount = newMinAmount;
        emit MinDepositAmountUpdated(oldAmount, newMinAmount, msg.sender);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                      ACCESS CONTROL MANAGEMENT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Set the exchange mode
     * @param newMode New exchange mode
     * @dev Only CONFIG_ROLE can change the exchange mode
     */
    function setExchangeMode(ExchangeMode newMode) external onlyRole(CONFIG_ROLE) {
        ExchangeMode oldMode = exchangeMode;
        exchangeMode = newMode;
        emit ExchangeModeUpdated(oldMode, newMode, msg.sender);
    }

    /**
     * @notice Add or remove addresses from whitelist
     * @param accounts Array of addresses to update
     * @param whitelisted Array of whitelist status for each address
     * @dev Only WHITELIST_MANAGER_ROLE can manage the whitelist
     */
    function updateWhitelist(address[] calldata accounts, bool[] calldata whitelisted)
        external
        onlyRole(WHITELIST_MANAGER_ROLE)
    {
        require(accounts.length == whitelisted.length, "Array length mismatch");

        for (uint i = 0; i < accounts.length; i++) {
            whitelist[accounts[i]] = whitelisted[i];
            emit WhitelistUpdated(accounts[i], whitelisted[i], msg.sender);
        }
    }

    /**
     * @notice Check if user can perform deposit
     * @param user User address to check
     * @dev Gas-optimized: checks PUBLIC mode first
     */
    function _checkExchangePermission(address user) internal view {
        // Gas optimization: most common case first
        if (exchangeMode == ExchangeMode.PUBLIC) {
            return; // No restrictions
        } else if (exchangeMode == ExchangeMode.WHITELIST) {
            if (!whitelist[user]) {
                revert NotWhitelisted(user);
            }
        }
    }

    /**
     * @notice Set treasury address for emergency withdrawals
     * @param newTreasury New treasury address
     */
    function setTreasury(address newTreasury) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (newTreasury == address(0)) revert ZeroAddress();
        address oldTreasury = treasury;
        treasury = newTreasury;
        emit TreasuryUpdated(oldTreasury, newTreasury);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get user escrow information
     * @param user User address
     * @return escrow User escrow data
     */
    function getUserEscrow(address user) external view returns (UserEscrow memory escrow) {
        escrow = userEscrows[user];
    }

    /**
     * @notice Get global exchange statistics
     * @return stats Exchange statistics
     */
    function getExchangeStats() external view returns (ExchangeStats memory stats) {
        stats = exchangeStats;
    }

    /**
     * @notice Calculate JPYC amount for given NLP amount
     * @param nlpAmount Amount of NLP tokens
     * @return jpycAmount Equivalent JPYC amount
     */
    function calculateJPYCAmount(uint nlpAmount) public view returns (uint jpycAmount) {
        return Math.mulDiv(nlpAmount, nlpToJpycRate, RATE_DENOMINATOR);
    }

    /**
     * @notice Calculate NLP amount for given JPYC amount
     * @param jpycAmount Amount of JPYC tokens
     * @return nlpAmount Equivalent NLP amount
     */
    function calculateNLPAmount(uint jpycAmount) public view returns (uint nlpAmount) {
        return Math.mulDiv(jpycAmount, RATE_DENOMINATOR, nlpToJpycRate);
    }

    /**
     * @notice Get the current NLP to JPYC exchange rate
     * @return rate The current exchange rate numerator
     */
    function getNLPToJPYCRate() external view returns (uint rate) {
        return nlpToJpycRate;
    }

    /**
     * @notice Get the rate denominator for NLP to JPYC conversion
     * @return denominator The rate denominator
     */
    function getRateDenominator() external pure returns (uint denominator) {
        return RATE_DENOMINATOR;
    }

    /**
     * @notice Get current contract balance of NLP tokens
     * @return balance Current NLP balance
     */
    function getContractNLPBalance() external view returns (uint balance) {
        return nlpToken.balanceOf(address(this));
    }

    /**
     * @notice Get exchange quote for specified NLP amount
     * @param tokenType Token type (must be JPYC, only supported type in this adapter)
     * @param nlpAmount Amount of NLP tokens
     * @return jpycAmount Equivalent JPYC amount (reference only)
     * @return rate Current NLP to JPYC rate numerator
     * @return denominator Rate denominator (always 100)
     * @return exchangeFee Exchange fee amount (always 0, no fees in this adapter)
     * @return operationalFee Operational fee amount (always 0, no fees in this adapter)
     * @dev This is for display purposes only. Actual JPYC transfer happens on Polygon.
     * @dev ABI compatible with NLPToMultiTokenExchange for frontend consistency
     * @dev tokenType parameter is included for ABI compatibility but must be JPYC
     */
    function getExchangeQuote(TokenType tokenType, uint nlpAmount)
        external
        view
        returns (
            uint jpycAmount,
            uint rate,
            uint denominator,
            uint exchangeFee,
            uint operationalFee
        )
    {
        // TokenType validation (only JPYC is supported)
        require(tokenType == TokenType.JPYC, "Only JPYC is supported");

        if (nlpAmount == 0) {
            return (0, nlpToJpycRate, RATE_DENOMINATOR, 0, 0);
        }

        jpycAmount = calculateJPYCAmount(nlpAmount);
        rate = nlpToJpycRate;
        denominator = RATE_DENOMINATOR;
        exchangeFee = 0; // No exchange fee in this adapter
        operationalFee = 0; // No operational fee in this adapter
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ADMIN FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Pause the contract
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Emergency withdrawal of NLP tokens to treasury
     * @param amount Amount to withdraw (0 for all)
     * @dev Only callable when paused
     */
    function emergencyWithdrawNLP(uint amount)
        external
        whenPaused
        nonReentrant
        onlyRole(DEFAULT_ADMIN_ROLE)
    {
        if (treasury == address(0)) revert TreasuryNotSet();

        uint balance = nlpToken.balanceOf(address(this));
        uint withdrawAmount = amount == 0 ? balance : amount;

        if (withdrawAmount > balance) {
            revert InsufficientBalance(address(this), withdrawAmount, balance);
        }

        emit EmergencyWithdraw(treasury, withdrawAmount, msg.sender);

        if (!nlpToken.transfer(treasury, withdrawAmount)) revert TransferFailed();
    }
}
