// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IERC20Extended
 * @notice Extended ERC20 interface with burn functionality and permit support for NewLoPoint
 * @dev This interface includes the standard ERC20 functions plus burn capability and ERC20Permit
 */
interface IERC20Extended is IERC20 {
    /**
     * @notice Burns tokens from the caller's account
     * @param amount The amount of tokens to burn
     */
    function burn(uint amount) external;

    /**
     * @notice Burns tokens from a specific account (requires allowance)
     * @param from The account to burn tokens from
     * @param amount The amount of tokens to burn
     */
    function burnFrom(address from, uint amount) external;

    /**
     * @notice Sets allowance based on token owner's signed approval (ERC20Permit)
     * @param owner Token owner's address
     * @param spender Address allowed to spend tokens
     * @param value Amount of tokens to approve
     * @param deadline Signature expiration deadline
     * @param v ECDSA signature parameter
     * @param r ECDSA signature parameter
     * @param s ECDSA signature parameter
     */
    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    /**
     * @notice Returns the current nonce for owner (ERC20Permit)
     * @param owner The token owner's address
     * @return Current nonce value
     */
    function nonces(address owner) external view returns (uint256);

    /**
     * @notice Returns the domain separator used in permit signature (ERC20Permit)
     * @return Domain separator hash
     */
    function DOMAIN_SEPARATOR() external view returns (bytes32);
}
