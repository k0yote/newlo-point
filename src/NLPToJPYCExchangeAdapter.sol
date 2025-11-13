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
 *      - Operator-controlled burn and transfer functionality (backend operations only)
 *      - Configurable NLP to JPYC exchange rate (no oracle required)
 *      - Role-based access control for operations
 *      - Emergency pause functionality
 *      - Comprehensive event logging for off-chain tracking
 *
 * @dev Cross-Chain Exchange Flow:
 *      Since JPYC exists on Polygon network and NLP exists on Soneium network:
 *      1. User signs permit (frontend) - only user action
 *      2. Backend executes depositNLPWithPermit on Soneium (escrow NLP)
 *      3. Backend sends JPYC to user on Polygon network
 *      4a. SUCCESS: Backend burns escrowed NLP on Soneium
 *      4b. FAILURE: Backend refunds escrowed NLP to user on Soneium
 *
 * @dev Important Notes:
 *      - JPYC token does NOT exist on Soneium network
 *      - JPYC transfers happen on Polygon network via backend operational wallet
 *      - This contract only handles NLP escrow/burn/transfer on Soneium
 *      - Exchange rate is for calculation reference only, not enforced on-chain
 *      - ALL operations are backend-controlled via OPERATOR_ROLE
 *      - Users CANNOT directly deposit or withdraw (only via backend with permit)
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
 *      - OPERATOR_ROLE: Backend service that executes deposits, burns, and refunds
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

    /* ═══════════════════════════════════════════════════════════════════════
                                   STRUCTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice User escrow information
    struct UserEscrow {
        uint totalDeposited; // Total NLP deposited by user
        uint totalBurned; // Total NLP burned for user
        uint currentBalance; // Current escrowed NLP balance
        uint depositCount; // Number of deposits
        uint lastDepositTime; // Last deposit timestamp
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

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice User escrow balances
    mapping(address => UserEscrow) public userEscrows;

    /// @notice Exchange fee rate in basis points (100 = 1%)
    /// @dev This fee is deducted from NLP exchange amount
    uint public exchangeFeeRate;

    /// @notice Operational fee rate in basis points (100 = 1%)
    /// @dev This fee is deducted from NLP exchange amount for gasless transactions
    uint public operationalFeeRate;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

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

    /// @notice Emitted when gasless deposit with permit is executed
    event GaslessDepositExecuted(
        address indexed user, address indexed relayer, uint nlpAmount, uint jpycEquivalent
    );

    /// @notice Emitted when exchange fee rate is updated
    event ExchangeFeeRateUpdated(uint oldRate, uint newRate, address updatedBy);

    /// @notice Emitted when operational fee rate is updated
    event OperationalFeeRateUpdated(uint oldRate, uint newRate, address updatedBy);

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
    error InvalidAmount(uint amount);
    error NoEscrowBalance(address user);
    error PermitFailed(address user, uint nlpAmount, uint deadline);
    error InvalidFeeRate(uint rate);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the NLP to JPYC exchange adapter
     * @param _nlpToken NewLo Point token contract address on Soneium
     * @param _initialAdmin Initial admin of the contract
     * @param _exchangeFeeRate Exchange fee rate in basis points (100 = 1%, max 10000 = 100%)
     * @param _operationalFeeRate Operational fee rate in basis points (100 = 1%, max 10000 = 100%)
     * @dev JPYC token is NOT stored as it exists on Polygon network, not Soneium
     */
    constructor(
        address _nlpToken,
        address _initialAdmin,
        uint _exchangeFeeRate,
        uint _operationalFeeRate
    ) {
        if (_nlpToken == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();
        if (_exchangeFeeRate > 10000) revert InvalidFeeRate(_exchangeFeeRate);
        if (_operationalFeeRate > 10000) revert InvalidFeeRate(_operationalFeeRate);

        nlpToken = IERC20Extended(_nlpToken);
        exchangeFeeRate = _exchangeFeeRate;
        operationalFeeRate = _operationalFeeRate;

        // Set up access control roles
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(OPERATOR_ROLE, _initialAdmin);
        _grantRole(CONFIG_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ESCROW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Deposit NLP tokens using permit (gasless transaction)
     * @param nlpAmount Amount of NLP tokens to deposit
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @param user User address (token owner)
     * @dev Only callable by OPERATOR_ROLE (backend service)
     * @dev Allows gasless deposits via EIP-2612 permit
     */
    function depositNLPWithPermit(
        uint nlpAmount,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s,
        address user
    ) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) {
        if (nlpAmount == 0) revert ZeroAmount();
        if (nlpAmount < minDepositAmount) revert BelowMinimumDeposit(nlpAmount, minDepositAmount);
        if (user == address(0)) revert ZeroAddress();

        // Execute permit
        try nlpToken.permit(user, address(this), nlpAmount, deadline, v, r, s) {
        // Permit successful
        }
        catch {
            revert PermitFailed(user, nlpAmount, deadline);
        }

        UserEscrow storage escrow = userEscrows[user];

        // Update user escrow
        unchecked {
            escrow.totalDeposited += nlpAmount;
            escrow.currentBalance += nlpAmount;
            escrow.depositCount += 1;
            escrow.lastDepositTime = block.timestamp;
        }

        // Calculate JPYC equivalent for event
        uint jpycEquivalent = calculateJPYCAmount(nlpAmount);

        emit GaslessDepositExecuted(user, msg.sender, nlpAmount, jpycEquivalent);

        // Transfer NLP tokens from user to this contract
        if (!nlpToken.transferFrom(user, address(this), nlpAmount)) revert TransferFailed();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          OPERATOR FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Burn escrowed NLP tokens (called after successful JPYC transfer)
     * @param user User address whose NLP will be burned
     * @param nlpAmount Amount of NLP tokens to burn
     * @param reason Reason for burning (for off-chain tracking)
     * @dev Only callable by OPERATOR_ROLE (backend service)
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
     * @dev Only callable by OPERATOR_ROLE (backend service)
     * @dev Primarily used for refunds when JPYC transfer on Polygon fails
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

        emit EscrowedNLPTransferred(from, to, msg.sender, nlpAmount, reason);

        // Transfer NLP tokens to destination
        if (!nlpToken.transfer(to, nlpAmount)) revert TransferFailed();
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

    /**
     * @notice Update the exchange fee rate
     * @param newFeeRate New fee rate in basis points (100 = 1%, max 10000 = 100%)
     * @dev This is a reference value for off-chain JPYC calculation on Polygon
     */
    function updateExchangeFeeRate(uint newFeeRate) external onlyRole(CONFIG_ROLE) {
        if (newFeeRate > 10000) revert InvalidFeeRate(newFeeRate); // Max 100%
        uint oldRate = exchangeFeeRate;
        exchangeFeeRate = newFeeRate;
        emit ExchangeFeeRateUpdated(oldRate, newFeeRate, msg.sender);
    }

    /**
     * @notice Update the operational fee rate
     * @param newFeeRate New fee rate in basis points (100 = 1%, max 10000 = 100%)
     * @dev This fee is deducted from NLP exchange amount for gasless transactions
     */
    function updateOperationalFeeRate(uint newFeeRate) external onlyRole(CONFIG_ROLE) {
        if (newFeeRate > 10000) revert InvalidFeeRate(newFeeRate); // Max 100%
        uint oldRate = operationalFeeRate;
        operationalFeeRate = newFeeRate;
        emit OperationalFeeRateUpdated(oldRate, newFeeRate, msg.sender);
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
     * @notice Get exchange quote for specified NLP amount
     * @param tokenType Token type (must be JPYC, only supported type in this adapter)
     * @param nlpAmount Amount of NLP tokens
     * @return tokenAmount Net JPYC amount after fees (reference only for off-chain Polygon transfer)
     * @return rate Current NLP to JPYC rate numerator
     * @return denominator Rate denominator (always 100)
     * @return exchangeFee Exchange fee amount in JPYC
     * @return operationalFee Operational fee amount in JPYC
     * @dev This is for display purposes only. Actual JPYC transfer happens on Polygon.
     * @dev ABI compatible with NLPToMultiTokenExchange for frontend consistency
     * @dev tokenType parameter is included for ABI compatibility but must be JPYC
     */
    function getExchangeQuote(TokenType tokenType, uint nlpAmount)
        external
        view
        returns (
            uint tokenAmount,
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

        // Calculate gross JPYC amount
        uint grossJpycAmount = calculateJPYCAmount(nlpAmount);

        // Calculate exchange fee
        exchangeFee = (grossJpycAmount * exchangeFeeRate) / 10000;

        // Calculate operational fee
        operationalFee = (grossJpycAmount * operationalFeeRate) / 10000;

        // Calculate net JPYC amount after fees
        tokenAmount = grossJpycAmount - exchangeFee - operationalFee;

        rate = nlpToJpycRate;
        denominator = RATE_DENOMINATOR;
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
}
