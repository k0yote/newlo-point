// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @title IERC20Extended
 * @notice Extended ERC20 interface with burn functionality for NewLoPoint
 * @dev This interface includes the standard ERC20 functions plus burn capability
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
}
