// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { ERC20Decimals } from "../src/tokens/ERC20Decimals.sol";

/**
 * @title MockTokensTest
 * @author NewLo Team
 * @notice Test suite for creating mock versions of popular tokens (WETH, USDC, USDT)
 * @dev This test demonstrates how to use ERC20Decimals to create test versions of real tokens
 *      with their correct decimal configurations for testing purposes
 */
contract MockTokensTest is Test {
    // Mock tokens with real-world specifications
    ERC20Decimals mockWETH; // 18 decimals - Wrapped Ether
    ERC20Decimals mockUSDC; // 6 decimals - USD Coin
    ERC20Decimals mockUSDT; // 6 decimals - Tether USD

    // Test users
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);
    address constant CHARLIE = address(0x3);

    function setUp() public {
        // Deploy mock tokens with real-world specifications
        mockWETH = new ERC20Decimals("Wrapped Ether (Mock)", "WETH", 18);
        mockUSDC = new ERC20Decimals("USD Coin (Mock)", "USDC", 6);
        mockUSDT = new ERC20Decimals("Tether USD (Mock)", "USDT", 6);
    }

    /**
     * @notice Test that mock tokens have correct specifications
     */
    function testMockTokenSpecifications() public view {
        // WETH specifications
        assertEq(mockWETH.name(), "Wrapped Ether (Mock)");
        assertEq(mockWETH.symbol(), "WETH");
        assertEq(mockWETH.decimals(), 18);

        // USDC specifications
        assertEq(mockUSDC.name(), "USD Coin (Mock)");
        assertEq(mockUSDC.symbol(), "USDC");
        assertEq(mockUSDC.decimals(), 6);

        // USDT specifications
        assertEq(mockUSDT.name(), "Tether USD (Mock)");
        assertEq(mockUSDT.symbol(), "USDT");
        assertEq(mockUSDT.decimals(), 6);
    }

    /**
     * @notice Test typical token amounts with correct decimal places
     */
    function testTypicalTokenAmounts() public view {
        // Test amount calculations with different decimals

        // WETH: 1 ETH = 1 * 10^18 wei
        uint oneETH = 1 * 10 ** mockWETH.decimals();
        assertEq(oneETH, 1000000000000000000); // 1e18

        // USDC: $1 = 1 * 10^6 units
        uint oneDollarUSDC = 1 * 10 ** mockUSDC.decimals();
        assertEq(oneDollarUSDC, 1000000); // 1e6

        // USDT: $1 = 1 * 10^6 units
        uint oneDollarUSDT = 1 * 10 ** mockUSDT.decimals();
        assertEq(oneDollarUSDT, 1000000); // 1e6

        // Verify USDC and USDT have same decimal representation
        assertEq(oneDollarUSDC, oneDollarUSDT);
    }

    /**
     * @notice Test token amount formatting for different use cases
     */
    function testTokenAmountFormatting() public view {
        // Common trading amounts

        // WETH amounts
        uint pointOneETH = 1 * 10 ** (mockWETH.decimals() - 1); // 0.1 ETH
        uint tenETH = 10 * 10 ** mockWETH.decimals(); // 10 ETH

        assertEq(pointOneETH, 100000000000000000); // 0.1e18
        assertEq(tenETH, 10000000000000000000); // 10e18

        // Stablecoin amounts
        uint tenDollars = 10 * 10 ** mockUSDC.decimals(); // $10
        uint thousandDollars = 1000 * 10 ** mockUSDC.decimals(); // $1000

        assertEq(tenDollars, 10000000); // 10e6
        assertEq(thousandDollars, 1000000000); // 1000e6
    }

    /**
     * @notice Test precision differences between tokens
     */
    function testPrecisionDifferences() public view {
        // Smallest unit for each token
        uint smallestWETH = 1; // 1 wei
        uint smallestUSDC = 1; // 1 micro-dollar (0.000001 USD)
        uint smallestUSDT = 1; // 1 micro-dollar (0.000001 USD)

        // Verify that stablecoins have less precision than WETH
        uint wethDecimals = mockWETH.decimals();
        uint usdcDecimals = mockUSDC.decimals();
        uint usdtDecimals = mockUSDT.decimals();

        assertTrue(wethDecimals > usdcDecimals);
        assertTrue(wethDecimals > usdtDecimals);
        assertEq(usdcDecimals, usdtDecimals);

        // Test precision conversion
        // 1 USDC unit represents 10^12 times larger value than 1 wei
        uint precisionDifference = 10 ** (wethDecimals - usdcDecimals);
        assertEq(precisionDifference, 1000000000000); // 1e12
    }

    /**
     * @notice Test that all tokens are properly deployed
     */
    function testTokenDeployment() public view {
        // All tokens should be deployed with non-zero addresses
        assertTrue(address(mockWETH) != address(0));
        assertTrue(address(mockUSDC) != address(0));
        assertTrue(address(mockUSDT) != address(0));

        // All tokens should have different addresses
        assertTrue(address(mockWETH) != address(mockUSDC));
        assertTrue(address(mockWETH) != address(mockUSDT));
        assertTrue(address(mockUSDC) != address(mockUSDT));

        // Initial supply should be zero
        assertEq(mockWETH.totalSupply(), 0);
        assertEq(mockUSDC.totalSupply(), 0);
        assertEq(mockUSDT.totalSupply(), 0);
    }

    /**
     * @notice Test realistic exchange rate calculations
     */
    function testExchangeRateCalculations() public view {
        // Example: If ETH = $2000, calculate token amounts
        uint ethPriceInUSD = 2000;

        // 1 ETH worth in USDC
        uint oneETHinUSDC = ethPriceInUSD * 10 ** mockUSDC.decimals();
        assertEq(oneETHinUSDC, 2000000000); // $2000 in USDC units (2000 * 1e6)

        // 0.5 ETH worth in USDT
        uint halfETHinUSDT = (ethPriceInUSD * 10 ** mockUSDT.decimals()) / 2;
        assertEq(halfETHinUSDT, 1000000000); // $1000 in USDT units (1000 * 1e6)

        // Test small amounts: $10 worth of ETH
        uint tenDollarsInETH = (10 * 10 ** mockWETH.decimals()) / ethPriceInUSD;
        assertEq(tenDollarsInETH, 5000000000000000); // 0.005 ETH (10/2000 * 1e18)
    }

    /**
     * @notice Demonstrate usage patterns for DeFi applications
     */
    function testDeFiUsagePatterns() public view {
        // Common DeFi amounts

        // Liquidity provision: $1000 USDC + equivalent ETH
        uint liquidityUSDC = 1000 * 10 ** mockUSDC.decimals();
        uint ethPrice = 2000; // $2000 per ETH
        uint liquidityETH = (1000 * 10 ** mockWETH.decimals()) / ethPrice;

        assertEq(liquidityUSDC, 1000000000); // 1000 USDC
        assertEq(liquidityETH, 500000000000000000); // 0.5 ETH

        // Lending: Borrow $500 USDT against 1 ETH collateral
        uint collateralETH = 1 * 10 ** mockWETH.decimals();
        uint borrowUSDT = 500 * 10 ** mockUSDT.decimals();

        assertEq(collateralETH, 1000000000000000000); // 1 ETH
        assertEq(borrowUSDT, 500000000); // 500 USDT

        // Trading: Swap 0.1 ETH for USDC
        uint tradeETH = 1 * 10 ** (mockWETH.decimals() - 1); // 0.1 ETH
        uint expectedUSDC =
            (tradeETH * ethPrice) / 10 ** mockWETH.decimals() * 10 ** mockUSDC.decimals();

        assertEq(tradeETH, 100000000000000000); // 0.1 ETH
        assertEq(expectedUSDC, 200000000); // $200 USDC
    }

    /**
     * @notice Test token compatibility with different protocols
     */
    function testProtocolCompatibility() public view {
        // Verify tokens implement ERC20 interface properly

        // All tokens should support standard ERC20 view functions
        assertEq(mockWETH.balanceOf(ALICE), 0);
        assertEq(mockUSDC.balanceOf(BOB), 0);
        assertEq(mockUSDT.balanceOf(CHARLIE), 0);

        assertEq(mockWETH.allowance(ALICE, BOB), 0);
        assertEq(mockUSDC.allowance(BOB, CHARLIE), 0);
        assertEq(mockUSDT.allowance(CHARLIE, ALICE), 0);

        // Verify consistent interface across all tokens
        assertTrue(bytes(mockWETH.name()).length > 0);
        assertTrue(bytes(mockUSDC.symbol()).length > 0);
        assertTrue(mockUSDT.decimals() <= 255);
    }
}
