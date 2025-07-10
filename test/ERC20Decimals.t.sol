// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { ERC20Decimals } from "../src/tokens/ERC20Decimals.sol";

/**
 * @title ERC20DecimalsTest
 * @author NewLo Team
 * @notice Test suite for ERC20Decimals contract
 * @dev Verifies custom decimals functionality and basic ERC20 operations
 */
contract ERC20DecimalsTest is Test {
    ERC20Decimals token6;
    ERC20Decimals token8;
    ERC20Decimals token18;

    address constant USER_A = address(0x1);
    address constant USER_B = address(0x2);

    function setUp() public {
        // Deploy tokens with different decimal configurations
        token6 = new ERC20Decimals("USDC Mock", "USDC", 6); // 6 decimals like USDC
        token8 = new ERC20Decimals("BTC Mock", "BTC", 8); // 8 decimals like Bitcoin
        token18 = new ERC20Decimals("ETH Mock", "ETH", 18); // 18 decimals like Ether
    }

    /**
     * @notice Test token metadata (name, symbol, decimals)
     */
    function testTokenMetadata() public view {
        // Test 6 decimal token
        assertEq(token6.name(), "USDC Mock");
        assertEq(token6.symbol(), "USDC");
        assertEq(token6.decimals(), 6);

        // Test 8 decimal token
        assertEq(token8.name(), "BTC Mock");
        assertEq(token8.symbol(), "BTC");
        assertEq(token8.decimals(), 8);

        // Test 18 decimal token
        assertEq(token18.name(), "ETH Mock");
        assertEq(token18.symbol(), "ETH");
        assertEq(token18.decimals(), 18);
    }

    /**
     * @notice Test different decimal configurations
     */
    function testCustomDecimals() public {
        // Create tokens with various decimal configurations
        ERC20Decimals token0 = new ERC20Decimals("Token0", "T0", 0);
        ERC20Decimals token2 = new ERC20Decimals("Token2", "T2", 2);
        ERC20Decimals token9 = new ERC20Decimals("Token9", "T9", 9);

        assertEq(token0.decimals(), 0);
        assertEq(token2.decimals(), 2);
        assertEq(token9.decimals(), 9);
    }

    /**
     * @notice Test that decimals are immutable after deployment
     */
    function testDecimalsImmutable() public view {
        // Decimals should remain constant for the token's lifetime
        assertEq(token6.decimals(), 6);
        assertEq(token8.decimals(), 8);
        assertEq(token18.decimals(), 18);

        // Multiple calls should return the same value
        assertEq(token6.decimals(), token6.decimals());
    }

    /**
     * @notice Test basic ERC20 functionality with custom decimals
     * @dev Verify that decimal configuration doesn't break standard ERC20 operations
     */
    function testBasicERC20Functionality() public {
        // Initial state
        assertEq(token6.totalSupply(), 0);
        assertEq(token6.balanceOf(USER_A), 0);
        assertEq(token6.balanceOf(USER_B), 0);

        // Note: This is a mock token, so we can't test mint/transfer without additional functionality
        // But we can verify the token exists and basic view functions work
        assertTrue(address(token6) != address(0));
        assertTrue(address(token8) != address(0));
        assertTrue(address(token18) != address(0));
    }

    /**
     * @notice Test edge case with maximum decimals
     */
    function testMaxDecimals() public {
        ERC20Decimals tokenMax = new ERC20Decimals("Max Decimals", "MAX", 255);
        assertEq(tokenMax.decimals(), 255);
    }

    /**
     * @notice Test fuzz testing for different decimal values
     */
    function testFuzzDecimals(uint8 decimals) public {
        ERC20Decimals fuzzToken = new ERC20Decimals("Fuzz Token", "FUZZ", decimals);
        assertEq(fuzzToken.decimals(), decimals);
        assertEq(fuzzToken.name(), "Fuzz Token");
        assertEq(fuzzToken.symbol(), "FUZZ");
    }
}
