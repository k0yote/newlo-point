// SPDX-License-Identifier: MIT
// Compatible with OpenZeppelin Contracts ^5.0.0
pragma solidity ^0.8.27;

import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/**
 * @title ERC20Decimals
 * @author NewLo Team
 * @notice ERC20 token with configurable decimals for testing purposes
 * @dev This contract extends ERC20 to allow custom decimal places
 *      Used primarily for testing scenarios where different decimal configurations are needed
 *
 * @dev Features:
 *      - Configurable decimals (overrides the default 18)
 *      - Standard ERC20 functionality with name and symbol
 *      - Immutable decimals set at deployment
 *      - Suitable for test environments and mock tokens
 *
 * @dev Usage Example:
 *      - Deploy with 6 decimals: new ERC20Decimals("USDC Mock", "USDC", 6)
 *      - Deploy with 8 decimals: new ERC20Decimals("BTC Mock", "BTC", 8)
 */
contract ERC20Decimals is ERC20 {
    /// @dev The number of decimals for this token (immutable after deployment)
    uint8 private immutable _decimals;

    /**
     * @notice Deploy ERC20 token with custom decimals
     * @param name_ The name of the token
     * @param symbol_ The symbol of the token
     * @param decimals_ The number of decimals for the token
     *
     * @dev All parameters are immutable after deployment
     * @dev Decimals parameter overrides the default ERC20 decimals (18)
     */
    constructor(string memory name_, string memory symbol_, uint8 decimals_)
        ERC20(name_, symbol_)
    {
        _decimals = decimals_;
    }

    /**
     * @notice Returns the number of decimals for this token
     * @return The number of decimals (overrides ERC20 default of 18)
     */
    function decimals() public view override returns (uint8) {
        return _decimals;
    }
}
