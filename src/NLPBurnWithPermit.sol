// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { ReentrancyGuard } from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import { Pausable } from "@openzeppelin/contracts/utils/Pausable.sol";
import { IERC20Extended } from "./interfaces/IERC20Extended.sol";

/**
 * @title NLPBurnWithPermit
 * @author NewLo Team
 * @notice Burn-only contract for NewLo Point (NLP) tokens using ERC20Permit for gasless transactions
 * @dev This contract allows users to burn their NLP tokens with permit signatures
 *
 * @dev Key Features:
 *      - Gasless burn using ERC20 Permit signatures
 *      - Direct burn functionality for users
 *      - Role-based access control
 *      - Comprehensive burn statistics tracking
 *      - Emergency pause functionality
 *      - Whitelist mode for controlled access
 *
 * @dev Security Features:
 *      - Reentrancy protection
 *      - Pausable for emergency stops
 *      - Comprehensive input validation
 *      - CEI (Checks-Effects-Interactions) pattern
 *      - Role-based access control
 *
 * @dev Access Control Roles:
 *      - DEFAULT_ADMIN_ROLE: Super admin with all permissions
 *      - OPERATOR_ROLE: Can execute permit-based burns on behalf of users
 *      - PAUSER_ROLE: Can pause/unpause contract
 *      - WHITELIST_MANAGER_ROLE: Can manage whitelist
 */
contract NLPBurnWithPermit is AccessControl, ReentrancyGuard, Pausable {
    /* ═══════════════════════════════════════════════════════════════════════
                                   ENUMS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Burn access control modes
    enum BurnMode {
        WHITELIST, // Only whitelisted addresses
        PUBLIC // Anyone can burn (default)
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              IMMUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice NewLo Point token contract
    IERC20Extended public immutable nlpToken;

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Access control roles
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                              MUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Total amount of NLP burned through this contract
    uint public totalBurned;

    /// @notice Total number of burn operations
    uint public burnCount;

    /// @notice User burn amounts
    mapping(address => uint) public userBurnAmount;

    /// @notice User burn count
    mapping(address => uint) public userBurnCount;

    /// @notice Current burn mode (defaults to PUBLIC)
    BurnMode public burnMode = BurnMode.PUBLIC;

    /// @notice Whitelist for burn access (used in WHITELIST mode)
    mapping(address => bool) public whitelist;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when NLP is burned directly
    event TokensBurned(address indexed user, uint amount);

    /// @notice Emitted when NLP is burned using permit (gasless)
    event TokensBurnedWithPermit(
        address indexed user, address indexed operator, uint amount, uint deadline
    );

    /// @notice Emitted when burn mode is updated
    event BurnModeUpdated(BurnMode oldMode, BurnMode newMode, address updatedBy);

    /// @notice Emitted when address is added/removed from whitelist
    event WhitelistUpdated(address indexed account, bool whitelisted, address updatedBy);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error InvalidBurnAmount(uint amount);
    error InvalidUser(address user);
    error PermitFailed(address user, uint amount, uint deadline);
    error BurnFailed(address user, uint amount);
    error ZeroAddress();
    error NotWhitelisted(address user);
    error InvalidBurnMode(BurnMode mode);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the NLP burn contract
     * @param _nlpToken NewLo Point token contract address
     * @param _initialAdmin Initial admin of the contract
     */
    constructor(address _nlpToken, address _initialAdmin) {
        if (_nlpToken == address(0)) revert ZeroAddress();
        if (_initialAdmin == address(0)) revert ZeroAddress();

        nlpToken = IERC20Extended(_nlpToken);

        // Set up access control roles
        _grantRole(DEFAULT_ADMIN_ROLE, _initialAdmin);
        _grantRole(OPERATOR_ROLE, _initialAdmin);
        _grantRole(PAUSER_ROLE, _initialAdmin);
        _grantRole(WHITELIST_MANAGER_ROLE, _initialAdmin);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                      ACCESS CONTROL MANAGEMENT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Set the burn mode
     * @param newMode New burn mode
     * @dev Only DEFAULT_ADMIN_ROLE can change the burn mode
     */
    function setBurnMode(BurnMode newMode) external onlyRole(DEFAULT_ADMIN_ROLE) {
        BurnMode oldMode = burnMode;
        burnMode = newMode;
        emit BurnModeUpdated(oldMode, newMode, msg.sender);
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
     * @notice Check if user can perform burn
     * @param user User address to check
     */
    function _checkBurnPermission(address user) internal view {
        // Gas optimization: most common case first
        if (burnMode == BurnMode.PUBLIC) {
            return; // No restrictions
        } else if (burnMode == BurnMode.WHITELIST) {
            if (!whitelist[user]) {
                revert NotWhitelisted(user);
            }
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            BURN FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Update burn statistics
     * @param user User address
     * @param amount Amount burned
     */
    function _updateBurnStats(address user, uint amount) internal {
        unchecked {
            totalBurned += amount;
            burnCount += 1;
            userBurnAmount[user] += amount;
            userBurnCount[user] += 1;
        }
    }

    /**
     * @notice Burn NLP tokens directly (user must have prior approval)
     * @param amount Amount of NLP tokens to burn
     * @dev User must approve this contract to spend their tokens before calling this function
     */
    function burn(uint amount) external nonReentrant whenNotPaused {
        if (amount == 0) {
            revert InvalidBurnAmount(amount);
        }

        // Check burn permission
        _checkBurnPermission(msg.sender);

        // Update statistics
        _updateBurnStats(msg.sender, amount);

        // Execute burn
        try nlpToken.burnFrom(msg.sender, amount) {
            emit TokensBurned(msg.sender, amount);
        } catch {
            revert BurnFailed(msg.sender, amount);
        }
    }

    /**
     * @notice Burn NLP tokens using permit signature (gasless transaction)
     * @param user User address (token owner)
     * @param amount Amount of NLP tokens to burn
     * @param deadline Permit deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     * @dev This function allows operators to burn tokens on behalf of users using their signature
     */
    function burnWithPermit(address user, uint amount, uint deadline, uint8 v, bytes32 r, bytes32 s)
        external
        nonReentrant
        whenNotPaused
        onlyRole(OPERATOR_ROLE)
    {
        if (amount == 0) {
            revert InvalidBurnAmount(amount);
        }

        if (user == address(0)) {
            revert InvalidUser(user);
        }

        // Check burn permission for operator (not user)
        // In WHITELIST mode, the operator (relayer) must be whitelisted, not the token owner
        _checkBurnPermission(msg.sender);

        // Execute permit
        try nlpToken.permit(user, address(this), amount, deadline, v, r, s) {
        // Permit successful
        }
        catch {
            revert PermitFailed(user, amount, deadline);
        }

        // Update statistics
        _updateBurnStats(user, amount);

        // Execute burn
        try nlpToken.burnFrom(user, amount) {
            emit TokensBurnedWithPermit(user, msg.sender, amount, deadline);
        } catch {
            revert BurnFailed(user, amount);
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get total burn statistics
     * @return _totalBurned Total amount burned
     * @return _burnCount Total number of burns
     */
    function getTotalBurnStats() external view returns (uint _totalBurned, uint _burnCount) {
        _totalBurned = totalBurned;
        _burnCount = burnCount;
    }

    /**
     * @notice Get user burn statistics
     * @param user User address
     * @return amount Total amount burned by user
     * @return count Number of burns by user
     */
    function getUserBurnStats(address user) external view returns (uint amount, uint count) {
        amount = userBurnAmount[user];
        count = userBurnCount[user];
    }

    /**
     * @notice Check if an address is whitelisted
     * @param account Address to check
     * @return True if whitelisted, false otherwise
     */
    function isWhitelisted(address account) external view returns (bool) {
        return whitelist[account];
    }

    /**
     * @notice Get current burn mode
     * @return Current burn mode
     */
    function getBurnMode() external view returns (BurnMode) {
        return burnMode;
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
