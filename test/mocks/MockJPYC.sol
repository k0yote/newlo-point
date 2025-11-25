// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { ERC20Permit } from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";

/**
 * @title MockJPYC
 * @notice Mock JPYC token for testing SendJPYC contract
 * @dev Implements EIP-2612 (permit) and EIP-3009 (transferWithAuthorization)
 */
contract MockJPYC is ERC20, ERC20Permit {
    /* ═══════════════════════════════════════════════════════════════════════
                              EIP-3009 TYPE HASHES
    ═══════════════════════════════════════════════════════════════════════ */

    bytes32 public constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public constant RECEIVE_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "ReceiveWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    bytes32 public constant CANCEL_AUTHORIZATION_TYPEHASH =
        keccak256("CancelAuthorization(address authorizer,bytes32 nonce)");

    /* ═══════════════════════════════════════════════════════════════════════
                              EIP-3009 STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Mapping of authorizer address to nonce to authorization state
    mapping(address => mapping(bytes32 => bool)) private _authorizationStates;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    event AuthorizationUsed(address indexed authorizer, bytes32 indexed nonce);
    event AuthorizationCanceled(address indexed authorizer, bytes32 indexed nonce);

    /* ═══════════════════════════════════════════════════════════════════════
                                   ERRORS
    ═══════════════════════════════════════════════════════════════════════ */

    error AuthorizationNotYetValid();
    error AuthorizationExpired();
    error AuthorizationAlreadyUsed();
    error CallerMustBePayee();
    error InvalidSignature();

    /* ═══════════════════════════════════════════════════════════════════════
                                 CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    constructor() ERC20("JPY Coin", "JPYC") ERC20Permit("JPY Coin") { }

    /* ═══════════════════════════════════════════════════════════════════════
                              MINTING FOR TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function mint(address to, uint amount) external {
        _mint(to, amount);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              EIP-3009 FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Check if an authorization nonce has been used
     * @param authorizer The authorizer's address
     * @param nonce The nonce to check
     * @return True if the nonce has been used
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool) {
        return _authorizationStates[authorizer][nonce];
    }

    /**
     * @notice Execute a transfer with a signed authorization
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function transferWithAuthorization(
        address from,
        address to,
        uint value,
        uint validAfter,
        uint validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                from,
                to,
                value,
                validAfter,
                validBefore,
                nonce
            )
        );
        _validateSignature(from, structHash, v, r, s);

        _markAuthorizationAsUsed(from, nonce);
        _transfer(from, to, value);
    }

    /**
     * @notice Receive a transfer with a signed authorization
     * @dev The caller must be the payee
     * @param from Payer's address (Authorizer)
     * @param to Payee's address
     * @param value Amount to be transferred
     * @param validAfter The time after which this is valid (unix time)
     * @param validBefore The time before which this is valid (unix time)
     * @param nonce Unique nonce
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function receiveWithAuthorization(
        address from,
        address to,
        uint value,
        uint validAfter,
        uint validBefore,
        bytes32 nonce,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        if (to != msg.sender) revert CallerMustBePayee();
        _requireValidAuthorization(from, validAfter, validBefore, nonce);

        bytes32 structHash = keccak256(
            abi.encode(
                RECEIVE_WITH_AUTHORIZATION_TYPEHASH, from, to, value, validAfter, validBefore, nonce
            )
        );
        _validateSignature(from, structHash, v, r, s);

        _markAuthorizationAsUsed(from, nonce);
        _transfer(from, to, value);
    }

    /**
     * @notice Cancel an authorization
     * @param authorizer Authorizer's address
     * @param nonce Nonce of the authorization
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s)
        external
    {
        if (_authorizationStates[authorizer][nonce]) revert AuthorizationAlreadyUsed();

        bytes32 structHash = keccak256(abi.encode(CANCEL_AUTHORIZATION_TYPEHASH, authorizer, nonce));
        _validateSignature(authorizer, structHash, v, r, s);

        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationCanceled(authorizer, nonce);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              INTERNAL FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    function _requireValidAuthorization(
        address authorizer,
        uint validAfter,
        uint validBefore,
        bytes32 nonce
    ) internal view {
        if (block.timestamp <= validAfter) revert AuthorizationNotYetValid();
        if (block.timestamp >= validBefore) revert AuthorizationExpired();
        if (_authorizationStates[authorizer][nonce]) revert AuthorizationAlreadyUsed();
    }

    function _markAuthorizationAsUsed(address authorizer, bytes32 nonce) internal {
        _authorizationStates[authorizer][nonce] = true;
        emit AuthorizationUsed(authorizer, nonce);
    }

    function _validateSignature(address signer, bytes32 structHash, uint8 v, bytes32 r, bytes32 s)
        internal
        view
    {
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", _domainSeparatorV4(), structHash));
        address recoveredSigner = ecrecover(digest, v, r, s);
        if (recoveredSigner != signer || recoveredSigner == address(0)) revert InvalidSignature();
    }

    /**
     * @dev Expose the internal domain separator for tests
     */
    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return _domainSeparatorV4();
    }
}
