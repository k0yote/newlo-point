// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import { ERC20Decimals } from "./ERC20Decimals.sol";

/**
 * @title ERC20DecimalsWithMint
 * @author NewLo Team
 * @notice ERC20 token with configurable decimals and minting functionality for testing
 * @dev This contract extends ERC20Decimals to add minting and burning capabilities
 *      Designed specifically for testing scenarios where token supply manipulation is needed
 *
 * @dev Features:
 *      - All features from ERC20Decimals (configurable decimals)
 *      - Public mint function for easy test token distribution
 *      - Public burn function for test scenario cleanup
 *      - Perfect for creating test versions of WETH, USDC, USDT with actual balances
 *
 * @dev Security Warning:
 *      - THIS IS FOR TESTING ONLY - No access control on mint/burn
 *      - DO NOT USE IN PRODUCTION
 *      - Anyone can mint/burn tokens
 *
 * @dev Usage Examples:
 *      - Create mock USDC: new ERC20DecimalsWithMint("USDC Mock", "USDC", 6)
 *      - Mint test tokens: mockUSDC.mint(user, 1000 * 10**6) // $1000 USDC
 *      - Test transfers: mockUSDC.transfer(recipient, amount)
 */
contract ERC20DecimalsWithMint is ERC20Decimals {
    /**
     * @notice Deploy testable ERC20 token with custom decimals and mint capability
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param decimals_ The number of decimals for the token
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20Decimals(name_, symbol_, decimals_)
    {
        // Constructor only calls parent - no additional logic needed
    }

    /**
     * @notice Mint tokens to any address
     * @param to Address to receive the minted tokens
     * @param amount Amount of tokens to mint (in token units, respecting decimals)
     *
     * @dev This function has no access control - FOR TESTING ONLY
     * @dev Amount should account for decimals (e.g., for USDC with 6 decimals,
     *      mint(user, 1000000) mints $1.00)
     *
     * Examples:
     * - Mint 1 WETH (18 decimals): mint(user, 1 * 10**18)
     * - Mint $100 USDC (6 decimals): mint(user, 100 * 10**6)
     * - Mint $50 USDT (6 decimals): mint(user, 50 * 10**6)
     */
    function mint(address to, uint amount) external {
        _mint(to, amount);
    }

    /**
     * @notice Burn tokens from any address
     * @param from Address to burn tokens from
     * @param amount Amount of tokens to burn
     *
     * @dev This function has no access control - FOR TESTING ONLY
     * @dev Useful for test cleanup or simulating token destruction
     *
     * Requirements:
     * - `from` must have at least `amount` tokens
     */
    function burn(address from, uint amount) external {
        _burn(from, amount);
    }

    /**
     * @notice Mint tokens to multiple addresses (batch mint)
     * @param recipients Array of addresses to receive tokens
     * @param amounts Array of amounts to mint to each recipient
     *
     * @dev Useful for setting up complex test scenarios
     * @dev Arrays must be the same length
     *
     * Requirements:
     * - recipients.length == amounts.length
     * - recipients.length > 0
     */
    function batchMint(address[] calldata recipients, uint[] calldata amounts) external {
        require(recipients.length == amounts.length, "Arrays length mismatch");
        require(recipients.length > 0, "Empty arrays");

        for (uint i = 0; i < recipients.length; i++) {
            _mint(recipients[i], amounts[i]);
        }
    }

    /**
     * @notice Get token amount in human-readable format
     * @param amount Token amount in wei/smallest unit
     * @return Human-readable amount as a scaled integer
     *
     * @dev Helper function for test readability
     * @dev For 6-decimal token: 1000000 wei → 1 (representing $1.00)
     * @dev For 18-decimal token: 1000000000000000000 wei → 1 (representing 1 ETH)
     */
    function getHumanAmount(uint amount) external view returns (uint) {
        return amount / (10 ** decimals());
    }

    /**
     * @notice Convert human-readable amount to token wei
     * @param humanAmount Amount in human-readable format (e.g., 100 for $100 or 1 for 1 ETH)
     * @return Token amount in wei/smallest unit
     *
     * @dev Helper function for test setup
     * @dev For 6-decimal token: 100 → 100000000 (representing $100.00)
     * @dev For 18-decimal token: 1 → 1000000000000000000 (representing 1 ETH)
     */
    function parseAmount(uint humanAmount) external view returns (uint) {
        return humanAmount * (10 ** decimals());
    }
}
