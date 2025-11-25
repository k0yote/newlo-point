// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {
    AccessControlUpgradeable
} from "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import {
    PausableUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/PausableUpgradeable.sol";
import {
    ReentrancyGuardUpgradeable
} from "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import {
    UUPSUpgradeable
} from "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import { IJPYCToken } from "./interfaces/IJPYCToken.sol";

/**
 * @title SendJPYC
 * @author NewLo Team
 * @notice A contract for gasless JPYC transfers using EIP-2612 (permit) and EIP-3009
 * @dev This contract allows operators to transfer JPYC on behalf of users using signed authorizations
 *
 * @dev Key Features:
 *      - EIP-2612 (permit): Two-step gasless transfer (permit + transferFrom)
 *      - EIP-3009 (transferWithAuthorization): One-step gasless transfer
 *      - UUPS upgradeable pattern
 *      - Role-based access control (OPERATOR, PAUSER)
 *      - Emergency pause functionality
 *      - Reentrancy protection
 *
 * @dev Access Control Roles:
 *      - DEFAULT_ADMIN_ROLE: Full system control, can grant/revoke roles
 *      - OPERATOR_ROLE: Can execute transfers on behalf of users
 *      - PAUSER_ROLE: Can pause/unpause the contract
 *
 * @dev Security Features:
 *      - Reentrancy protection on all transfer functions
 *      - Pausable functionality for emergency stops
 *      - Role separation for different administrative tasks
 *      - Input validation for all external functions
 */
contract SendJPYC is
    Initializable,
    AccessControlUpgradeable,
    PausableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    /* ═══════════════════════════════════════════════════════════════════════
                                   ROLES
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Role identifier for addresses that can execute transfers
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");

    /// @notice Role identifier for addresses that can pause/unpause the contract
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    /* ═══════════════════════════════════════════════════════════════════════
                                   STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice The JPYC token contract
    IJPYCToken public jpycToken;

    /// @notice Total number of transfers executed via permit
    uint public totalPermitTransfers;

    /// @notice Total number of transfers executed via transferWithAuthorization
    uint public totalAuthTransfers;

    /// @notice Total amount transferred via permit
    uint public totalPermitAmount;

    /// @notice Total amount transferred via transferWithAuthorization
    uint public totalAuthAmount;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when JPYC is transferred using permit + transferFrom
    event TransferWithPermit(
        address indexed from, address indexed to, uint value, address indexed operator
    );

    /// @notice Emitted when JPYC is transferred using transferWithAuthorization
    event TransferWithAuth(
        address indexed from,
        address indexed to,
        uint value,
        bytes32 indexed nonce,
        address operator
    );

    /// @notice Emitted when the JPYC token address is updated
    event JPYCTokenUpdated(address indexed oldToken, address indexed newToken);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Thrown when the JPYC token address is zero
    error ZeroAddress();

    /// @notice Thrown when the transfer amount is zero
    error ZeroAmount();

    /// @notice Thrown when the from address is zero
    error InvalidFromAddress();

    /// @notice Thrown when the to address is zero
    error InvalidToAddress();

    /// @notice Thrown when permit deadline has expired
    error PermitExpired();

    /// @notice Thrown when authorization time window is invalid
    error InvalidTimeWindow();

    /* ═══════════════════════════════════════════════════════════════════════
                                  MODIFIERS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Validates that the address is not zero
    modifier validAddress(address addr) {
        if (addr == address(0)) revert ZeroAddress();
        _;
    }

    /// @notice Validates that the amount is greater than zero
    modifier validAmount(uint amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                 CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                 INITIALIZER
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Initialize the contract
     * @param _jpycToken The JPYC token contract address
     * @param _admin The address that will receive the DEFAULT_ADMIN_ROLE
     */
    function initialize(address _jpycToken, address _admin) external initializer {
        if (_jpycToken == address(0)) revert ZeroAddress();
        if (_admin == address(0)) revert ZeroAddress();

        __AccessControl_init();
        __Pausable_init();
        __ReentrancyGuard_init();
        __UUPSUpgradeable_init();

        jpycToken = IJPYCToken(_jpycToken);

        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
        _grantRole(OPERATOR_ROLE, _admin);
        _grantRole(PAUSER_ROLE, _admin);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            EIP-2612 PERMIT TRANSFER
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Transfer JPYC using EIP-2612 permit signature
     * @dev This function executes permit + transferFrom in a single transaction
     * @param from The owner of the tokens (signer)
     * @param to The recipient of the tokens
     * @param value The amount of tokens to transfer
     * @param deadline The expiration time of the permit signature
     * @param v The v component of the signature
     * @param r The r component of the signature
     * @param s The s component of the signature
     */
    function sendWithPermit(
        address from,
        address to,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) validAmount(value) {
        if (from == address(0)) revert InvalidFromAddress();
        if (to == address(0)) revert InvalidToAddress();
        if (block.timestamp > deadline) revert PermitExpired();

        // Execute permit to approve this contract to spend tokens
        jpycToken.permit(from, address(this), value, deadline, v, r, s);

        // Transfer tokens from the owner to the recipient
        bool success = jpycToken.transferFrom(from, to, value);
        require(success, "Transfer failed");

        // Update statistics
        totalPermitTransfers++;
        totalPermitAmount += value;

        emit TransferWithPermit(from, to, value, msg.sender);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          EIP-3009 AUTHORIZATION TRANSFER
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Transfer JPYC using EIP-3009 transferWithAuthorization
     * @dev This function executes a direct transfer with a signed authorization
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce to prevent replay attacks
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function sendWithAuthorization(
        address from,
        address to,
        uint value,
        uint validAfter,
        uint validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE) validAmount(value) {
        if (from == address(0)) revert InvalidFromAddress();
        if (to == address(0)) revert InvalidToAddress();
        if (validAfter >= validBefore) revert InvalidTimeWindow();

        // Execute the transfer with authorization
        jpycToken.transferWithAuthorization(
            from, to, value, validAfter, validBefore, nonce, v, r, s
        );

        // Update statistics
        totalAuthTransfers++;
        totalAuthAmount += value;

        emit TransferWithAuth(from, to, value, nonce, msg.sender);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              ADMIN FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Update the JPYC token address
     * @param _newJpycToken The new JPYC token contract address
     */
    function setJPYCToken(address _newJpycToken)
        external
        onlyRole(DEFAULT_ADMIN_ROLE)
        validAddress(_newJpycToken)
    {
        address oldToken = address(jpycToken);
        jpycToken = IJPYCToken(_newJpycToken);
        emit JPYCTokenUpdated(oldToken, _newJpycToken);
    }

    /**
     * @notice Pause the contract
     * @dev Only accounts with PAUSER_ROLE can call this function
     */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    /**
     * @notice Unpause the contract
     * @dev Only accounts with PAUSER_ROLE can call this function
     */
    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get the current nonce for an owner (for EIP-2612 permit)
     * @param owner The address to query
     * @return The current nonce
     */
    function getPermitNonce(address owner) external view returns (uint) {
        return jpycToken.nonces(owner);
    }

    /**
     * @notice Check if an authorization nonce has been used (for EIP-3009)
     * @param authorizer The authorizer's address
     * @param nonce The nonce to check
     * @return True if the nonce has been used
     */
    function isAuthorizationUsed(address authorizer, bytes32 nonce) external view returns (bool) {
        return jpycToken.authorizationState(authorizer, nonce);
    }

    /**
     * @notice Get the domain separator for EIP-712 signatures
     * @return The domain separator
     */
    function getDomainSeparator() external view returns (bytes32) {
        return jpycToken.DOMAIN_SEPARATOR();
    }

    /**
     * @notice Get transfer statistics
     * @return permitTransfers Total number of permit transfers
     * @return authTransfers Total number of authorization transfers
     * @return permitAmount Total amount transferred via permit
     * @return authAmount Total amount transferred via authorization
     */
    function getStatistics()
        external
        view
        returns (uint permitTransfers, uint authTransfers, uint permitAmount, uint authAmount)
    {
        return (totalPermitTransfers, totalAuthTransfers, totalPermitAmount, totalAuthAmount);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              UUPS UPGRADE
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Authorize contract upgrades
     * @dev Only accounts with DEFAULT_ADMIN_ROLE can upgrade the contract
     * @param newImplementation The address of the new implementation
     */
    function _authorizeUpgrade(address newImplementation)
        internal
        override
        onlyRole(DEFAULT_ADMIN_ROLE)
    { }

    /* ═══════════════════════════════════════════════════════════════════════
                              STORAGE GAP
    ═══════════════════════════════════════════════════════════════════════ */

    /// @dev Reserved storage space for future upgrades
    uint[44] private __gap;
}
