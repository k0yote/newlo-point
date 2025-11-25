// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

/**
 * @title IJPYCToken
 * @author NewLo Team
 * @notice Interface for JPYC stablecoin with EIP-2612 (permit) and EIP-3009 support
 * @dev This interface defines the functions needed for gasless transfers
 */
interface IJPYCToken {
    /* ═══════════════════════════════════════════════════════════════════════
                              ERC20 STANDARD
    ═══════════════════════════════════════════════════════════════════════ */

    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address account) external view returns (uint);
    function transfer(address to, uint value) external returns (bool);
    function allowance(address owner, address spender) external view returns (uint);
    function approve(address spender, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    /* ═══════════════════════════════════════════════════════════════════════
                              EIP-2612 (PERMIT)
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Get the current nonce for an owner
     * @param owner The address to query the nonce for
     * @return The current nonce
     */
    function nonces(address owner) external view returns (uint);

    /**
     * @notice Get the domain separator used for permit signatures
     * @return The domain separator
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    /**
     * @notice Update allowance with a signed permit
     * @param owner Token owner's address (Authorizer)
     * @param spender Spender's address
     * @param value Amount of allowance
     * @param deadline Expiration time, seconds since the epoch
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /* ═══════════════════════════════════════════════════════════════════════
                              EIP-3009
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Check if an authorization nonce has been used
     * @param authorizer The authorizer's address
     * @param nonce The nonce to check
     * @return True if the nonce has been used
     */
    function authorizationState(address authorizer, bytes32 nonce) external view returns (bool);

    /**
     * @notice Execute a transfer with a signed authorization from the payer
     * @dev Anyone can call this function with a valid signature
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
    ) external;

    /**
     * @notice Receive a transfer with a signed authorization from the payer
     * @dev The caller must be the payee (to address) to prevent front-running
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
    ) external;

    /**
     * @notice Attempt to cancel an authorization
     * @dev Works only if the authorization is not yet used
     * @param authorizer Authorizer's address
     * @param nonce Nonce of the authorization
     * @param v v of the signature
     * @param r r of the signature
     * @param s s of the signature
     */
    function cancelAuthorization(address authorizer, bytes32 nonce, uint8 v, bytes32 r, bytes32 s)
        external;
}
