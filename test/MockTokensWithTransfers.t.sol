// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

/**
 * @title MockTokensWithTransfersTest
 * @author NewLo Team
 * @notice Test suite demonstrating real token transfers using mint-enabled mock tokens
 * @dev Shows how to use ERC20DecimalsWithMint for comprehensive testing of DeFi scenarios
 *      with actual token balances and transfers
 */
contract MockTokensWithTransfersTest is Test {
    // Mock tokens with minting capability
    ERC20DecimalsWithMint mockWETH;
    ERC20DecimalsWithMint mockUSDC;
    ERC20DecimalsWithMint mockUSDT;

    // Test participants
    address constant ALICE = address(0x1);
    address constant BOB = address(0x2);
    address constant CHARLIE = address(0x3);
    address constant DEX = address(0x4);
    address constant LENDING_POOL = address(0x5);

    function setUp() public {
        // Deploy testable tokens with real specifications
        mockWETH = new ERC20DecimalsWithMint("Wrapped Ether (Test)", "WETH", 18);
        mockUSDC = new ERC20DecimalsWithMint("USD Coin (Test)", "USDC", 6);
        mockUSDT = new ERC20DecimalsWithMint("Tether USD (Test)", "USDT", 6);
    }

    /**
     * @notice Test basic minting and balance checking
     */
    function testBasicMinting() public {
        // Mint 10 ETH to Alice
        uint tenETH = mockWETH.parseAmount(10); // 10 * 10^18
        mockWETH.mint(ALICE, tenETH);

        assertEq(mockWETH.balanceOf(ALICE), tenETH);
        assertEq(mockWETH.getHumanAmount(mockWETH.balanceOf(ALICE)), 10);

        // Mint $1000 USDC to Bob
        uint thousandUSDC = mockUSDC.parseAmount(1000); // 1000 * 10^6
        mockUSDC.mint(BOB, thousandUSDC);

        assertEq(mockUSDC.balanceOf(BOB), thousandUSDC);
        assertEq(mockUSDC.getHumanAmount(mockUSDC.balanceOf(BOB)), 1000);

        // Mint $500 USDT to Charlie
        uint fiveHundredUSDT = mockUSDT.parseAmount(500); // 500 * 10^6
        mockUSDT.mint(CHARLIE, fiveHundredUSDT);

        assertEq(mockUSDT.balanceOf(CHARLIE), fiveHundredUSDT);
        assertEq(mockUSDT.getHumanAmount(mockUSDT.balanceOf(CHARLIE)), 500);
    }

    /**
     * @notice Test realistic DeFi scenario: DEX trading
     */
    function testDEXTrading() public {
        // Setup: Alice has 5 ETH, Bob has $10,000 USDC
        mockWETH.mint(ALICE, mockWETH.parseAmount(5));
        mockUSDC.mint(BOB, mockUSDC.parseAmount(10000));

        // Simulate ETH price = $2000
        uint ethPrice = 2000;

        // Alice wants to sell 1 ETH for USDC
        uint oneETH = mockWETH.parseAmount(1);
        uint expectedUSDC = mockUSDC.parseAmount(ethPrice); // $2000 USDC

        // Alice sends ETH to DEX
        vm.prank(ALICE);
        mockWETH.transfer(DEX, oneETH);

        // DEX sends USDC to Alice (Bob provides liquidity)
        vm.prank(BOB);
        mockUSDC.transfer(ALICE, expectedUSDC);

        // Verify final balances
        assertEq(mockWETH.balanceOf(ALICE), mockWETH.parseAmount(4)); // 4 ETH left
        assertEq(mockWETH.balanceOf(DEX), oneETH); // DEX has 1 ETH
        assertEq(mockUSDC.balanceOf(ALICE), expectedUSDC); // Alice has $2000 USDC
        assertEq(mockUSDC.balanceOf(BOB), mockUSDC.parseAmount(8000)); // Bob has $8000 left
    }

    /**
     * @notice Test lending scenario with multiple tokens
     */
    function testLendingScenario() public {
        // Setup: Alice has 2 ETH, wants to borrow USDT
        mockWETH.mint(ALICE, mockWETH.parseAmount(2));
        mockUSDT.mint(LENDING_POOL, mockUSDT.parseAmount(100000)); // Pool has $100k USDT

        // Alice deposits 2 ETH as collateral (worth $4000 at $2000/ETH)
        uint collateral = mockWETH.parseAmount(2);
        vm.prank(ALICE);
        mockWETH.transfer(LENDING_POOL, collateral);

        // Alice borrows $2000 USDT (50% LTV)
        uint borrowAmount = mockUSDT.parseAmount(2000);
        vm.prank(LENDING_POOL);
        mockUSDT.transfer(ALICE, borrowAmount);

        // Verify balances
        assertEq(mockWETH.balanceOf(ALICE), 0); // No ETH left
        assertEq(mockWETH.balanceOf(LENDING_POOL), collateral); // Pool has collateral
        assertEq(mockUSDT.balanceOf(ALICE), borrowAmount); // Alice has borrowed USDT
        assertEq(mockUSDT.balanceOf(LENDING_POOL), mockUSDT.parseAmount(98000)); // Pool has remaining USDT
    }

    /**
     * @notice Test liquidity provision scenario
     */
    function testLiquidityProvision() public {
        // Setup: Provide liquidity to WETH/USDC pool
        uint ethAmount = mockWETH.parseAmount(1); // 1 ETH
        uint usdcAmount = mockUSDC.parseAmount(2000); // $2000 USDC (1:2000 ratio)

        // Mint tokens to liquidity provider
        mockWETH.mint(ALICE, ethAmount);
        mockUSDC.mint(ALICE, usdcAmount);

        // Alice provides liquidity to DEX
        vm.startPrank(ALICE);
        mockWETH.transfer(DEX, ethAmount);
        mockUSDC.transfer(DEX, usdcAmount);
        vm.stopPrank();

        // Verify DEX has the liquidity
        assertEq(mockWETH.balanceOf(DEX), ethAmount);
        assertEq(mockUSDC.balanceOf(DEX), usdcAmount);
        assertEq(mockWETH.balanceOf(ALICE), 0);
        assertEq(mockUSDC.balanceOf(ALICE), 0);

        // Verify liquidity amounts in human-readable format
        assertEq(mockWETH.getHumanAmount(mockWETH.balanceOf(DEX)), 1);
        assertEq(mockUSDC.getHumanAmount(mockUSDC.balanceOf(DEX)), 2000);
    }

    /**
     * @notice Test batch minting for complex scenarios
     */
    function testBatchMinting() public {
        address[] memory users = new address[](3);
        uint[] memory amounts = new uint[](3);

        users[0] = ALICE;
        users[1] = BOB;
        users[2] = CHARLIE;

        // Distribute different amounts of USDC
        amounts[0] = mockUSDC.parseAmount(1000); // Alice: $1000
        amounts[1] = mockUSDC.parseAmount(2000); // Bob: $2000
        amounts[2] = mockUSDC.parseAmount(500); // Charlie: $500

        // Batch mint
        mockUSDC.batchMint(users, amounts);

        // Verify all balances
        assertEq(mockUSDC.balanceOf(ALICE), amounts[0]);
        assertEq(mockUSDC.balanceOf(BOB), amounts[1]);
        assertEq(mockUSDC.balanceOf(CHARLIE), amounts[2]);

        // Verify total supply
        uint expectedTotal = amounts[0] + amounts[1] + amounts[2];
        assertEq(mockUSDC.totalSupply(), expectedTotal);
    }

    /**
     * @notice Test multi-token arbitrage scenario
     */
    function testArbitrageScenario() public {
        // Setup: Price discrepancy between USDC and USDT
        // USDC/ETH rate: 1 ETH = $2000 USDC
        // USDT/ETH rate: 1 ETH = $1990 USDT (cheaper)

        mockUSDC.mint(ALICE, mockUSDC.parseAmount(2000));
        mockUSDT.mint(DEX, mockUSDT.parseAmount(100000));
        mockWETH.mint(DEX, mockWETH.parseAmount(50));

        // Step 1: Alice buys ETH with USDC
        uint usdcSpent = mockUSDC.parseAmount(2000);
        uint ethBought = mockWETH.parseAmount(1);

        vm.prank(ALICE);
        mockUSDC.transfer(DEX, usdcSpent);
        // DEX gives ETH to Alice
        vm.prank(DEX);
        mockWETH.transfer(ALICE, ethBought);

        // Step 2: Alice sells ETH for USDT (at better rate)
        uint usdtReceived = mockUSDT.parseAmount(1990);

        vm.prank(ALICE);
        mockWETH.transfer(DEX, ethBought);
        // DEX gives USDT to Alice
        vm.prank(DEX);
        mockUSDT.transfer(ALICE, usdtReceived);

        // Alice now has $1990 USDT (slight loss due to arbitrage cost)
        // In real scenario, the $10 difference would be profit if rates were inverted
        assertEq(mockUSDT.balanceOf(ALICE), usdtReceived);
        assertEq(mockUSDC.balanceOf(ALICE), 0);
        assertEq(mockWETH.balanceOf(ALICE), 0);
    }

    /**
     * @notice Test token burning and supply management
     */
    function testBurningAndSupply() public {
        // Mint tokens first
        uint mintAmount = mockUSDC.parseAmount(1000);
        mockUSDC.mint(ALICE, mintAmount);

        assertEq(mockUSDC.totalSupply(), mintAmount);
        assertEq(mockUSDC.balanceOf(ALICE), mintAmount);

        // Burn half the tokens
        uint burnAmount = mintAmount / 2;
        mockUSDC.burn(ALICE, burnAmount);

        assertEq(mockUSDC.totalSupply(), mintAmount - burnAmount);
        assertEq(mockUSDC.balanceOf(ALICE), mintAmount - burnAmount);
    }

    /**
     * @notice Test approval and transferFrom scenarios
     */
    function testApprovalAndTransferFrom() public {
        // Setup: Alice has WETH, wants to allow DEX to spend it
        uint amount = mockWETH.parseAmount(5);
        mockWETH.mint(ALICE, amount);

        // Alice approves DEX to spend 2 ETH
        uint approvalAmount = mockWETH.parseAmount(2);
        vm.prank(ALICE);
        mockWETH.approve(DEX, approvalAmount);

        assertEq(mockWETH.allowance(ALICE, DEX), approvalAmount);

        // DEX transfers 1 ETH from Alice to Bob
        uint transferAmount = mockWETH.parseAmount(1);
        vm.prank(DEX);
        mockWETH.transferFrom(ALICE, BOB, transferAmount);

        // Verify balances and remaining allowance
        assertEq(mockWETH.balanceOf(ALICE), amount - transferAmount); // 4 ETH
        assertEq(mockWETH.balanceOf(BOB), transferAmount); // 1 ETH
        assertEq(mockWETH.allowance(ALICE, DEX), approvalAmount - transferAmount); // 1 ETH allowance left
    }

    /**
     * @notice Test edge cases with different decimal precisions
     */
    function testDecimalPrecisionEdgeCases() public {
        // Test smallest units
        mockUSDC.mint(ALICE, 1); // 1 micro-dollar (0.000001 USD)
        mockWETH.mint(BOB, 1); // 1 wei

        assertEq(mockUSDC.balanceOf(ALICE), 1);
        assertEq(mockWETH.balanceOf(BOB), 1);

        // Test very large amounts
        uint largeUSDC = 1000000 * 10 ** mockUSDC.decimals(); // $1M USDC
        uint largeWETH = 1000 * 10 ** mockWETH.decimals(); // 1000 ETH

        mockUSDC.mint(CHARLIE, largeUSDC);
        mockWETH.mint(CHARLIE, largeWETH);

        assertEq(mockUSDC.getHumanAmount(mockUSDC.balanceOf(CHARLIE)), 1000000);
        assertEq(mockWETH.getHumanAmount(mockWETH.balanceOf(CHARLIE)), 1000);
    }
}
