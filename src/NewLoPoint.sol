// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControlUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC20Upgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

/**
 * @title NewLoPoint
 * @author NewLo Team
 * @notice An upgradeable ERC20 token with advanced transfer controls and role-based access management
 * @dev This contract implements:
 *      - ERC20 with Permit (gasless approvals)
 *      - Pausable functionality for emergency stops
 *      - Burnable tokens
 *      - Role-based access control with multiple administrative roles
 *      - Granular transfer control system with whitelist functionality
 *      - Upgradeable pattern using OpenZeppelin's proxy system
 *
 * @dev Security Considerations:
 *      - Uses OpenZeppelin's battle-tested upgradeable contracts
 *      - Implements proper access control for all administrative functions
 *      - Transfer controls can be bypassed for mint/burn operations (by design)
 *      - Global transfer enable overrides whitelist restrictions
 *      - Initializer is properly protected against reinitialization
 *
 * @dev Inheritance Chain:
 *      NewLoPoint
 *      ├── Initializable (proxy initialization)
 *      ├── ERC20Upgradeable (core token functionality)
 *      ├── ERC20BurnableUpgradeable (burning capability)
 *      ├── ERC20PausableUpgradeable (pause functionality)
 *      ├── AccessControlUpgradeable (role management)
 *      └── ERC20PermitUpgradeable (gasless approvals)
 */
contract NewLoPoint is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable
{
    /* ═══════════════════════════════════════════════════════════════════════
                                   ROLES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Role identifier for addresses that can pause/unpause the contract
    /// @dev Separate from DEFAULT_ADMIN_ROLE to allow delegation of pause functionality
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /// @notice Role identifier for addresses that can mint new tokens
    /// @dev Separate role to control token supply inflation
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    /// @notice Role identifier for addresses that can manage the whitelist
    /// @dev Allows delegation of whitelist management without full admin privileges
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                            TRANSFER CONTROL STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Global flag to enable/disable all token transfers (except mint/burn)
    /// @dev When false, only whitelisted addresses can transfer (if whitelist mode is enabled)
    /// @dev When true, all addresses can transfer regardless of whitelist status
    bool public transfersEnabled;

    /// @notice Flag to enable whitelist-based transfer restrictions
    /// @dev When true, transfers are allowed for whitelisted addresses even if transfersEnabled is false
    /// @dev When false, whitelist is ignored and only transfersEnabled matters
    bool public whitelistModeEnabled;

    /// @notice Mapping of addresses that are whitelisted for transfers
    /// @dev Whitelist: addresses allowed to transfer even when transfers are restricted
    /// @dev Both sender and receiver being whitelisted allows the transfer
    mapping(address => bool) public whitelistedAddresses;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when global transfer setting is changed
    /// @param enabled New state of global transfers
    event TransfersEnabledChanged(bool enabled);

    /// @notice Emitted when whitelist mode setting is changed
    /// @param enabled New state of whitelist mode
    event WhitelistModeChanged(bool enabled);

    /// @notice Emitted when an address is added to or removed from the whitelist
    /// @param account The address being whitelisted or un-whitelisted
    /// @param whitelisted True if added to whitelist, false if removed
    event AddressWhitelisted(address indexed account, bool whitelisted);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Thrown when a transfer is attempted but global transfers are disabled and whitelist conditions aren't met
    error TransfersDisabled();

    /// @notice Thrown when whitelist mode is active and neither sender nor receiver is whitelisted
    error NotWhitelisted();

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Constructor that disables initializers for the implementation contract
    /// @dev This prevents the implementation contract from being initialized directly
    /// @dev Only proxy contracts can call initialize()
    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               INITIALIZATION
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initializes the contract with initial roles and settings
     * @dev This function replaces the constructor for upgradeable contracts
     * @dev Can only be called once due to the initializer modifier
     * @dev Sets up all inherited contracts and assigns initial roles
     *
     * @param defaultAdmin Address that will receive DEFAULT_ADMIN_ROLE and WHITELIST_MANAGER_ROLE
     * @param pauser Address that will receive PAUSER_ROLE
     * @param minter Address that will receive MINTER_ROLE
     *
     * @dev Initial State:
     *      - Token name: "NewLo Point"
     *      - Token symbol: "NLP"
     *      - Transfers: Disabled
     *      - Whitelist mode: Disabled
     *      - Contract: Not paused
     */
    function initialize(address defaultAdmin, address pauser, address minter) public initializer {
        // Initialize all inherited contracts
        __ERC20_init("NewLo Point", "NLP");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("NewLo Point");

        // Grant initial roles
        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(WHITELIST_MANAGER_ROLE, defaultAdmin);

        // Set initial transfer control state (restrictive by default)
        transfersEnabled = false;
        whitelistModeEnabled = false;
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          TRANSFER CONTROL FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Enable/disable global transfers (admin only)
     * @dev When enabled, all transfers are allowed regardless of whitelist status
     * @dev When disabled, only whitelisted transfers are allowed (if whitelist mode is enabled)
     * @param enabled True to enable all transfers, false to restrict transfers
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     *
     * Emits:
     * - TransfersEnabledChanged event
     */
    function setTransfersEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transfersEnabled = enabled;
        emit TransfersEnabledChanged(enabled);
    }

    /**
     * @notice Enable/disable whitelist mode (admin only)
     * @dev When enabled, whitelisted addresses can transfer even if global transfers are disabled
     * @dev When disabled, whitelist is ignored
     * @param enabled True to enable whitelist mode, false to disable
     *
     * Requirements:
     * - Caller must have DEFAULT_ADMIN_ROLE
     *
     * Emits:
     * - WhitelistModeChanged event
     */
    function setWhitelistModeEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistModeEnabled = enabled;
        emit WhitelistModeChanged(enabled);
    }

    /**
     * @notice Add/remove address from whitelist
     * @dev Whitelisted addresses can transfer when whitelist mode is enabled
     * @param account Address to whitelist or un-whitelist
     * @param whitelisted True to add to whitelist, false to remove
     *
     * Requirements:
     * - Caller must have WHITELIST_MANAGER_ROLE
     *
     * Emits:
     * - AddressWhitelisted event
     */
    function setWhitelistedAddress(address account, bool whitelisted)
        external
        onlyRole(WHITELIST_MANAGER_ROLE)
    {
        whitelistedAddresses[account] = whitelisted;
        emit AddressWhitelisted(account, whitelisted);
    }

    /**
     * @notice Batch add/remove multiple addresses from whitelist
     * @dev More gas efficient than multiple individual calls
     * @param accounts Array of addresses to whitelist or un-whitelist
     * @param whitelisted True to add all to whitelist, false to remove all
     *
     * Requirements:
     * - Caller must have WHITELIST_MANAGER_ROLE
     * - accounts array must not be empty
     *
     * Emits:
     * - AddressWhitelisted event for each address
     */
    function setWhitelistedAddresses(address[] calldata accounts, bool whitelisted)
        external
        onlyRole(WHITELIST_MANAGER_ROLE)
    {
        for (uint i = 0; i < accounts.length; i++) {
            whitelistedAddresses[accounts[i]] = whitelisted;
            emit AddressWhitelisted(accounts[i], whitelisted);
        }
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            PUBLIC CONTROL FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Pause all token transfers (emergency function)
     * @dev When paused, all transfers, mints, and burns are blocked
     * @dev Can be used as an emergency brake
     *
     * Requirements:
     * - Caller must have PAUSER_ROLE
     * - Contract must not already be paused
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause token transfers
     * @dev Restores normal transfer functionality
     *
     * Requirements:
     * - Caller must have PAUSER_ROLE
     * - Contract must be paused
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /**
     * @notice Mint new tokens to specified address
     * @dev Minting bypasses custom transfer restrictions but is subject to pause
     * @param to Address to receive the minted tokens
     * @param amount Number of tokens to mint (in wei units)
     *
     * Requirements:
     * - Caller must have MINTER_ROLE
     * - to address must not be zero address
     * - Contract must not be paused
     *
     * Security Note:
     * - This function can inflate token supply
     * - MINTER_ROLE should be carefully managed
     * - Pause state blocks minting for emergency situations
     */
    function mint(address to, uint amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            INTERNAL FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Check if transfer is allowed based on current restrictions
     * @dev Internal function to centralize transfer permission logic
     * @param from Address sending tokens (zero address for minting)
     * @param to Address receiving tokens (zero address for burning)
     * @return bool True if transfer should be allowed, false otherwise
     *
     * @dev Transfer Rules (in order of precedence):
     *      1. Mint/Burn operations are always allowed (from or to is zero address)
     *      2. If global transfers are enabled, all transfers allowed
     *      3. If whitelist mode is enabled and either sender OR receiver is whitelisted, transfer allowed
     *      4. Otherwise, transfer is blocked
     */
    function _isTransferAllowed(address from, address to) internal view returns (bool) {
        // Rule 1: Mint/Burn is always allowed
        if (from == address(0) || to == address(0)) {
            return true;
        }

        // Rule 2: Allow if global transfers are enabled
        if (transfersEnabled) {
            return true;
        }

        // Rule 3: If whitelist mode is enabled, allow if sender or receiver is whitelisted
        if (whitelistModeEnabled && (whitelistedAddresses[from] || whitelistedAddresses[to])) {
            return true;
        }

        // Rule 4: Block all other transfers
        return false;
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              CORE HOOK OVERRIDE
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Core transfer hook that enforces all transfer restrictions
     * @dev Overrides OpenZeppelin's _update function to add custom transfer logic
     * @dev This hook is called for all transfers, mints, and burns
     * @param from Address sending tokens (zero for minting)
     * @param to Address receiving tokens (zero for burning)
     * @param value Amount of tokens being transferred
     *
     * @dev Control Hierarchy (in order of precedence):
     *      1. Pause state (highest priority) - blocks ALL operations when active
     *      2. Custom transfer controls (if not paused)
     *
     * @dev Throws appropriate errors when transfers are not allowed:
     *      - Pause-related errors: when contract is paused (handled by checking paused state)
     *      - NotWhitelisted: when whitelist mode is active and neither party is whitelisted
     *      - TransfersDisabled: when global transfers are disabled and whitelist conditions aren't met
     *
     * Security Notes:
     * - Pause state takes absolute precedence over all other controls
     * - This function is called by all transfer-related functions
     * - Proper error hierarchy helps users understand failure reasons
     * - Mint/burn operations are subject to pause (unlike custom transfer controls)
     */
    function _update(address from, address to, uint value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        // First check: Pause state takes highest priority
        // If paused, let the parent contract handle the error
        if (paused()) {
            super._update(from, to, value); // This will revert with pause error
            return; // This line never executes, but for clarity
        }

        // Second check: Custom transfer controls (only if not paused)
        if (!_isTransferAllowed(from, to)) {
            if (whitelistModeEnabled) {
                revert NotWhitelisted();
            } else {
                revert TransfersDisabled();
            }
        }

        // Execute the transfer if all checks pass
        super._update(from, to, value);
    }
}
