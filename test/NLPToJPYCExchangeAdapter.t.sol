// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { NLPToJPYCExchangeAdapter } from "../src/NLPToJPYCExchangeAdapter.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NLPToJPYCExchangeAdapterTest
 * @author NewLo Team
 * @notice Comprehensive test suite for NLPToJPYCExchangeAdapter contract
 * @dev This test suite covers:
 *      - Initial state and deployment verification
 *      - Escrow deposit and withdrawal functionality
 *      - Operator burn and transfer operations
 *      - Role-based access control
 *      - Batch operations
 *      - Edge cases and security considerations
 *      - Emergency functions
 *
 * @dev Test Coverage Areas:
 *      - ✅ Initialization and role assignment
 *      - ✅ Escrow deposit operations
 *      - ✅ Escrow withdrawal operations
 *      - ✅ Operator burn functionality
 *      - ✅ Operator transfer functionality
 *      - ✅ Batch burn operations
 *      - ✅ Rate updates and configuration
 *      - ✅ Pause/unpause functionality
 *      - ✅ Emergency withdrawal
 *      - ✅ Event emission verification
 *      - ✅ Error condition testing
 *
 * @dev Security Test Focus:
 *      - Only operators can burn/transfer escrowed tokens
 *      - Users can only withdraw their own tokens
 *      - Proper balance tracking
 *      - Reentrancy protection
 *      - Pause functionality works correctly
 */
contract NLPToJPYCExchangeAdapterTest is Test {
    /* ═══════════════════════════════════════════════════════════════════════
                               TEST CONTRACTS
    ═══════════════════════════════════════════════════════════════════════ */

    NewLoPoint nlpImpl;
    NewLoPoint nlpToken;
    ProxyAdmin nlpAdmin;
    TransparentUpgradeableProxy nlpProxy;

    NLPToJPYCExchangeAdapter adapter;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST ACTORS
    ═══════════════════════════════════════════════════════════════════════ */

    address constant ADMIN = address(0x1);
    address constant OPERATOR = address(0x2);
    address constant TREASURY = address(0x3);
    address constant USER_A = address(0x4);
    address constant USER_B = address(0x5);
    address constant UNAUTHORIZED = address(0x6);

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    uint constant INITIAL_NLP_BALANCE = 10000e18;
    uint constant DEFAULT_DEPOSIT = 100e18;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST SETUP
    ═══════════════════════════════════════════════════════════════════════ */

    function setUp() public {
        // Deploy NLP Token
        nlpImpl = new NewLoPoint();
        nlpAdmin = new ProxyAdmin(ADMIN);
        bytes memory nlpData =
            abi.encodeWithSelector(nlpImpl.initialize.selector, ADMIN, ADMIN, ADMIN);
        nlpProxy = new TransparentUpgradeableProxy(address(nlpImpl), address(nlpAdmin), nlpData);
        nlpToken = NewLoPoint(address(nlpProxy));

        // Deploy adapter (no JPYC token needed - it's on Polygon)
        adapter = new NLPToJPYCExchangeAdapter(address(nlpToken), ADMIN);

        // Setup roles
        vm.startPrank(ADMIN);
        adapter.grantRole(adapter.OPERATOR_ROLE(), OPERATOR);
        adapter.setTreasury(TREASURY);

        // Enable global transfers for NLP
        nlpToken.setTransfersEnabled(true);

        // Mint NLP tokens to users
        nlpToken.mint(USER_A, INITIAL_NLP_BALANCE);
        nlpToken.mint(USER_B, INITIAL_NLP_BALANCE);
        vm.stopPrank();

        // Label addresses for better trace output
        vm.label(ADMIN, "ADMIN");
        vm.label(OPERATOR, "OPERATOR");
        vm.label(TREASURY, "TREASURY");
        vm.label(USER_A, "USER_A");
        vm.label(USER_B, "USER_B");
        vm.label(UNAUTHORIZED, "UNAUTHORIZED");
        vm.label(address(adapter), "NLPToJPYCExchangeAdapter");
        vm.label(address(nlpToken), "NLPToken");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           INITIALIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Initialization() public view {
        assertEq(address(adapter.nlpToken()), address(nlpToken), "NLP token address mismatch");
        assertEq(adapter.nlpToJpycRate(), 100, "Initial rate should be 100");
        assertEq(adapter.minDepositAmount(), 1e18, "Min deposit should be 1e18");
        assertTrue(
            adapter.hasRole(adapter.DEFAULT_ADMIN_ROLE(), ADMIN),
            "ADMIN should have DEFAULT_ADMIN_ROLE"
        );
        assertTrue(
            adapter.hasRole(adapter.OPERATOR_ROLE(), OPERATOR), "OPERATOR should have OPERATOR_ROLE"
        );
    }

    function testRevert_InitializationWithZeroAddress() public {
        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        new NLPToJPYCExchangeAdapter(address(0), ADMIN);

        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        new NLPToJPYCExchangeAdapter(address(nlpToken), address(0));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           DEPOSIT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DepositNLP() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);

        uint jpycEquivalent = adapter.calculateJPYCAmount(DEFAULT_DEPOSIT);

        vm.expectEmit(true, false, false, true);
        emit NLPToJPYCExchangeAdapter.Deposited(
            USER_A, DEFAULT_DEPOSIT, DEFAULT_DEPOSIT, jpycEquivalent
        );

        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Check balances
        assertEq(
            nlpToken.balanceOf(address(adapter)), DEFAULT_DEPOSIT, "Adapter should receive NLP"
        );
        assertEq(
            nlpToken.balanceOf(USER_A),
            INITIAL_NLP_BALANCE - DEFAULT_DEPOSIT,
            "User balance should decrease"
        );

        // Check escrow data
        (
            uint totalDeposited,
            uint totalWithdrawn,
            uint totalBurned,
            uint currentBalance,
            uint depositCount,
            uint lastDepositTime
        ) = adapter.userEscrows(USER_A);

        assertEq(totalDeposited, DEFAULT_DEPOSIT, "Total deposited mismatch");
        assertEq(totalWithdrawn, 0, "Total withdrawn should be 0");
        assertEq(totalBurned, 0, "Total burned should be 0");
        assertEq(currentBalance, DEFAULT_DEPOSIT, "Current balance mismatch");
        assertEq(depositCount, 1, "Deposit count should be 1");
        assertEq(lastDepositTime, block.timestamp, "Last deposit time mismatch");

        // Check global stats
        (uint totalDeposited_,,,, uint activeUsers, uint totalTransactions) =
            adapter.exchangeStats();

        assertEq(totalDeposited_, DEFAULT_DEPOSIT, "Global total deposited mismatch");
        assertEq(activeUsers, 1, "Active users should be 1");
        assertEq(totalTransactions, 1, "Total transactions should be 1");
    }

    function test_DepositNLP_Multiple() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT * 3);

        adapter.depositNLP(DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        (,,, uint currentBalance, uint depositCount,) = adapter.userEscrows(USER_A);

        assertEq(currentBalance, DEFAULT_DEPOSIT * 3, "Current balance should be 3x deposit");
        assertEq(depositCount, 3, "Deposit count should be 3");
    }

    function testRevert_DepositZeroAmount() public {
        vm.startPrank(USER_A);
        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAmount.selector);
        adapter.depositNLP(0);
        vm.stopPrank();
    }

    function testRevert_DepositBelowMinimum() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), 0.5e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.BelowMinimumDeposit.selector, 0.5e18, 1e18
            )
        );
        adapter.depositNLP(0.5e18);
        vm.stopPrank();
    }

    function testRevert_DepositWithoutApproval() public {
        vm.startPrank(USER_A);
        vm.expectRevert(); // ERC20 insufficient allowance
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();
    }

    function testFuzz_DepositNLP(uint96 amount) public {
        vm.assume(amount >= 1e18 && amount <= INITIAL_NLP_BALANCE);

        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), amount);
        adapter.depositNLP(amount);
        vm.stopPrank();

        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, amount, "Current balance should match deposit");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           WITHDRAWAL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_WithdrawNLP() public {
        // First deposit
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);

        uint withdrawAmount = DEFAULT_DEPOSIT / 2;

        vm.expectEmit(true, false, false, true);
        emit NLPToJPYCExchangeAdapter.Withdrawn(
            USER_A, withdrawAmount, DEFAULT_DEPOSIT - withdrawAmount
        );

        adapter.withdrawNLP(withdrawAmount);
        vm.stopPrank();

        // Check balances
        assertEq(
            nlpToken.balanceOf(address(adapter)),
            DEFAULT_DEPOSIT - withdrawAmount,
            "Adapter balance should decrease"
        );
        assertEq(
            nlpToken.balanceOf(USER_A),
            INITIAL_NLP_BALANCE - withdrawAmount,
            "User balance should increase"
        );

        // Check escrow data
        (, uint totalWithdrawn,, uint currentBalance,,) = adapter.userEscrows(USER_A);

        assertEq(totalWithdrawn, withdrawAmount, "Total withdrawn mismatch");
        assertEq(currentBalance, DEFAULT_DEPOSIT - withdrawAmount, "Current balance mismatch");
    }

    function test_WithdrawNLP_All() public {
        // First deposit
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);

        // Withdraw all (pass 0)
        adapter.withdrawNLP(0);
        vm.stopPrank();

        // Check balances
        assertEq(nlpToken.balanceOf(address(adapter)), 0, "Adapter should have no NLP");
        assertEq(nlpToken.balanceOf(USER_A), INITIAL_NLP_BALANCE, "User should have all NLP back");

        // Check escrow data
        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, 0, "Current balance should be 0");

        // Check global stats
        (,,,, uint activeUsers,) = adapter.exchangeStats();
        assertEq(activeUsers, 0, "Active users should be 0");
    }

    function testRevert_WithdrawNLP_NoBalance() public {
        vm.startPrank(USER_A);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.NoEscrowBalance.selector, USER_A)
        );
        adapter.withdrawNLP(1e18);
        vm.stopPrank();
    }

    function testRevert_WithdrawNLP_InsufficientBalance() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.InsufficientBalance.selector,
                USER_A,
                DEFAULT_DEPOSIT * 2,
                DEFAULT_DEPOSIT
            )
        );
        adapter.withdrawNLP(DEFAULT_DEPOSIT * 2);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           BURN TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_BurnEscrowedNLP() public {
        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        uint burnAmount = DEFAULT_DEPOSIT / 2;
        uint jpycEquivalent = adapter.calculateJPYCAmount(burnAmount);
        string memory reason = "Exchange completed";

        vm.startPrank(OPERATOR);
        vm.expectEmit(true, true, false, true);
        emit NLPToJPYCExchangeAdapter.EscrowedNLPBurned(
            USER_A, OPERATOR, burnAmount, jpycEquivalent, reason
        );

        adapter.burnEscrowedNLP(USER_A, burnAmount, reason);
        vm.stopPrank();

        // Check escrow data
        (,, uint totalBurned, uint currentBalance,,) = adapter.userEscrows(USER_A);

        assertEq(totalBurned, burnAmount, "Total burned mismatch");
        assertEq(currentBalance, DEFAULT_DEPOSIT - burnAmount, "Current balance mismatch");

        // Check global stats
        (,, uint globalBurned,,,) = adapter.exchangeStats();
        assertEq(globalBurned, burnAmount, "Global burned mismatch");
    }

    function test_BurnEscrowedNLP_All() public {
        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        vm.prank(OPERATOR);
        adapter.burnEscrowedNLP(USER_A, DEFAULT_DEPOSIT, "Full burn");

        // Check escrow data
        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, 0, "Current balance should be 0");

        // Check global stats
        (,,,, uint activeUsers,) = adapter.exchangeStats();
        assertEq(activeUsers, 0, "Active users should be 0");
    }

    function testRevert_BurnEscrowedNLP_Unauthorized() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.burnEscrowedNLP(USER_A, DEFAULT_DEPOSIT, "Unauthorized");
        vm.stopPrank();
    }

    function testRevert_BurnEscrowedNLP_ZeroAddress() public {
        vm.prank(OPERATOR);
        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.burnEscrowedNLP(address(0), 1e18, "Zero address");
    }

    function testRevert_BurnEscrowedNLP_NoBalance() public {
        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.NoEscrowBalance.selector, USER_A)
        );
        adapter.burnEscrowedNLP(USER_A, 1e18, "No balance");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TRANSFER TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_TransferEscrowedNLP() public {
        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        uint transferAmount = DEFAULT_DEPOSIT / 2;
        string memory reason = "Refund";

        uint initialBalanceUserB = nlpToken.balanceOf(USER_B);

        vm.startPrank(OPERATOR);
        vm.expectEmit(true, true, true, true);
        emit NLPToJPYCExchangeAdapter.EscrowedNLPTransferred(
            USER_A, USER_B, OPERATOR, transferAmount, reason
        );

        adapter.transferEscrowedNLP(USER_A, USER_B, transferAmount, reason);
        vm.stopPrank();

        // Check balances
        assertEq(
            nlpToken.balanceOf(USER_B),
            initialBalanceUserB + transferAmount,
            "USER_B should receive NLP"
        );

        // Check escrow data
        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, DEFAULT_DEPOSIT - transferAmount, "Current balance mismatch");

        // Check global stats
        (,,, uint globalTransferred,,) = adapter.exchangeStats();
        assertEq(globalTransferred, transferAmount, "Global transferred mismatch");
    }

    function test_TransferEscrowedNLP_ToSelf() public {
        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        uint initialBalance = nlpToken.balanceOf(USER_A);

        vm.prank(OPERATOR);
        adapter.transferEscrowedNLP(USER_A, USER_A, DEFAULT_DEPOSIT, "Return to user");

        // Check balance
        assertEq(
            nlpToken.balanceOf(USER_A),
            initialBalance + DEFAULT_DEPOSIT,
            "USER_A should receive NLP back"
        );

        // Check escrow data
        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, 0, "Current balance should be 0");
    }

    function testRevert_TransferEscrowedNLP_Unauthorized() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.transferEscrowedNLP(USER_A, USER_B, DEFAULT_DEPOSIT, "Unauthorized");
        vm.stopPrank();
    }

    function testRevert_TransferEscrowedNLP_ZeroAddress() public {
        vm.startPrank(OPERATOR);

        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.transferEscrowedNLP(address(0), USER_B, 1e18, "Zero from");

        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.transferEscrowedNLP(USER_A, address(0), 1e18, "Zero to");

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           BATCH OPERATIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_BatchBurnEscrowedNLP() public {
        // Setup deposits for multiple users
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(USER_B);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Prepare batch burn
        address[] memory users = new address[](2);
        users[0] = USER_A;
        users[1] = USER_B;

        uint[] memory amounts = new uint[](2);
        amounts[0] = DEFAULT_DEPOSIT / 2;
        amounts[1] = DEFAULT_DEPOSIT / 2;

        vm.prank(OPERATOR);
        adapter.batchBurnEscrowedNLP(users, amounts, "Batch exchange");

        // Check escrow data for both users
        (,, uint totalBurnedA, uint currentBalanceA,,) = adapter.userEscrows(USER_A);
        (,, uint totalBurnedB, uint currentBalanceB,,) = adapter.userEscrows(USER_B);

        assertEq(totalBurnedA, DEFAULT_DEPOSIT / 2, "USER_A total burned mismatch");
        assertEq(totalBurnedB, DEFAULT_DEPOSIT / 2, "USER_B total burned mismatch");
        assertEq(currentBalanceA, DEFAULT_DEPOSIT / 2, "USER_A current balance mismatch");
        assertEq(currentBalanceB, DEFAULT_DEPOSIT / 2, "USER_B current balance mismatch");

        // Check global stats
        (,, uint globalBurned,,,) = adapter.exchangeStats();
        assertEq(globalBurned, DEFAULT_DEPOSIT, "Global burned should be sum of burns");
    }

    function testRevert_BatchBurnEscrowedNLP_ArrayMismatch() public {
        address[] memory users = new address[](2);
        uint[] memory amounts = new uint[](1);

        vm.prank(OPERATOR);
        vm.expectRevert("Array length mismatch");
        adapter.batchBurnEscrowedNLP(users, amounts, "Mismatch");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           CONFIGURATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_UpdateNLPToJPYCRate() public {
        uint newRate = 90;

        vm.startPrank(ADMIN);
        vm.expectEmit(false, false, false, true);
        emit NLPToJPYCExchangeAdapter.RateUpdated(100, newRate, ADMIN);

        adapter.updateNLPToJPYCRate(newRate);
        vm.stopPrank();

        assertEq(adapter.nlpToJpycRate(), newRate, "Rate should be updated");
    }

    function testRevert_UpdateNLPToJPYCRate_ZeroRate() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(NLPToJPYCExchangeAdapter.InvalidRate.selector, 0));
        adapter.updateNLPToJPYCRate(0);
    }

    function testRevert_UpdateNLPToJPYCRate_Unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.updateNLPToJPYCRate(90);
    }

    function test_UpdateMinDepositAmount() public {
        uint newMinAmount = 5e18;

        vm.startPrank(ADMIN);
        vm.expectEmit(false, false, false, true);
        emit NLPToJPYCExchangeAdapter.MinDepositAmountUpdated(1e18, newMinAmount, ADMIN);

        adapter.updateMinDepositAmount(newMinAmount);
        vm.stopPrank();

        assertEq(adapter.minDepositAmount(), newMinAmount, "Min deposit should be updated");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           PERMIT DEPOSIT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testRevert_DepositNLPWithPermit_ZeroAddress() public {
        vm.prank(OPERATOR);
        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.depositNLPWithPermit(
            DEFAULT_DEPOSIT, block.timestamp + 1 hours, 0, bytes32(0), bytes32(0), address(0)
        );
    }

    function testRevert_DepositNLPWithPermit_ZeroAmount() public {
        vm.prank(OPERATOR);
        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAmount.selector);
        adapter.depositNLPWithPermit(
            0, block.timestamp + 1 hours, 0, bytes32(0), bytes32(0), USER_A
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SetExchangeMode() public {
        vm.startPrank(ADMIN);

        vm.expectEmit(false, false, false, true);
        emit NLPToJPYCExchangeAdapter.ExchangeModeUpdated(
            NLPToJPYCExchangeAdapter.ExchangeMode.PUBLIC,
            NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST,
            ADMIN
        );

        adapter.setExchangeMode(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST);
        vm.stopPrank();

        assertEq(
            uint(adapter.exchangeMode()), uint(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST)
        );
    }

    function test_UpdateWhitelist() public {
        address[] memory accounts = new address[](2);
        accounts[0] = USER_A;
        accounts[1] = USER_B;

        bool[] memory whitelisted = new bool[](2);
        whitelisted[0] = true;
        whitelisted[1] = true;

        vm.prank(ADMIN);
        adapter.updateWhitelist(accounts, whitelisted);

        assertTrue(adapter.whitelist(USER_A), "USER_A should be whitelisted");
        assertTrue(adapter.whitelist(USER_B), "USER_B should be whitelisted");
    }

    function test_WhitelistMode_AllowsWhitelistedUsers() public {
        // Set to whitelist mode
        vm.prank(ADMIN);
        adapter.setExchangeMode(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST);

        // Add USER_A to whitelist
        address[] memory accounts = new address[](1);
        accounts[0] = USER_A;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        vm.prank(ADMIN);
        adapter.updateWhitelist(accounts, whitelisted);

        // USER_A should be able to deposit
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, DEFAULT_DEPOSIT, "Whitelisted user should be able to deposit");
    }

    function testRevert_WhitelistMode_BlocksNonWhitelistedUsers() public {
        // Set to whitelist mode
        vm.prank(ADMIN);
        adapter.setExchangeMode(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST);

        // USER_A is not whitelisted
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);

        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.NotWhitelisted.selector, USER_A)
        );
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();
    }

    function test_PublicMode_AllowsAllUsers() public {
        // Default is PUBLIC mode
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(
            currentBalance, DEFAULT_DEPOSIT, "Any user should be able to deposit in PUBLIC mode"
        );
    }

    function testRevert_UpdateWhitelist_ArrayMismatch() public {
        address[] memory accounts = new address[](2);
        bool[] memory whitelisted = new bool[](1);

        vm.prank(ADMIN);
        vm.expectRevert("Array length mismatch");
        adapter.updateWhitelist(accounts, whitelisted);
    }

    function testRevert_SetExchangeMode_Unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.setExchangeMode(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST);
    }

    function testRevert_UpdateWhitelist_Unauthorized() public {
        address[] memory accounts = new address[](1);
        bool[] memory whitelisted = new bool[](1);

        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.updateWhitelist(accounts, whitelisted);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           VIEW FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GetExchangeQuote() public view {
        uint nlpAmount = 100e18;
        (uint jpycAmount, uint rate, uint denominator, uint exchangeFee, uint operationalFee) =
            adapter.getExchangeQuote(NLPToJPYCExchangeAdapter.TokenType.JPYC, nlpAmount);

        assertEq(jpycAmount, 100e18, "JPYC amount should be 100 at 1:1 rate");
        assertEq(rate, 100, "Rate should be 100");
        assertEq(denominator, 100, "Rate denominator should be 100");
        assertEq(exchangeFee, 0, "Exchange fee should be 0");
        assertEq(operationalFee, 0, "Operational fee should be 0");
    }

    function test_GetExchangeQuote_ZeroAmount() public view {
        (uint jpycAmount, uint rate, uint denominator, uint exchangeFee, uint operationalFee) =
            adapter.getExchangeQuote(NLPToJPYCExchangeAdapter.TokenType.JPYC, 0);

        assertEq(jpycAmount, 0, "JPYC amount should be 0");
        assertEq(rate, 100, "Rate should still be returned");
        assertEq(denominator, 100, "Rate denominator should still be returned");
        assertEq(exchangeFee, 0, "Exchange fee should be 0");
        assertEq(operationalFee, 0, "Operational fee should be 0");
    }

    function test_CalculateJPYCAmount() public view {
        uint nlpAmount = 100e18;
        uint jpycAmount = adapter.calculateJPYCAmount(nlpAmount);

        assertEq(jpycAmount, 100e18, "JPYC amount should equal NLP amount at 1:1 rate");
    }

    function test_CalculateNLPAmount() public view {
        uint jpycAmount = 100e18;
        uint nlpAmount = adapter.calculateNLPAmount(jpycAmount);

        assertEq(nlpAmount, 100e18, "NLP amount should equal JPYC amount at 1:1 rate");
    }

    function test_GetUserEscrow() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        NLPToJPYCExchangeAdapter.UserEscrow memory escrow = adapter.getUserEscrow(USER_A);

        assertEq(escrow.totalDeposited, DEFAULT_DEPOSIT, "Total deposited mismatch");
        assertEq(escrow.currentBalance, DEFAULT_DEPOSIT, "Current balance mismatch");
        assertEq(escrow.depositCount, 1, "Deposit count mismatch");
    }

    function test_GetExchangeStats() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        NLPToJPYCExchangeAdapter.ExchangeStats memory stats = adapter.getExchangeStats();

        assertEq(stats.totalDeposited, DEFAULT_DEPOSIT, "Total deposited mismatch");
        assertEq(stats.activeUsers, 1, "Active users mismatch");
        assertEq(stats.totalTransactions, 1, "Total transactions mismatch");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           PAUSE FUNCTIONALITY TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Pause() public {
        vm.prank(ADMIN);
        adapter.pause();

        assertTrue(adapter.paused(), "Contract should be paused");
    }

    function testRevert_DepositWhenPaused() public {
        vm.prank(ADMIN);
        adapter.pause();

        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        vm.expectRevert();
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(ADMIN);
        adapter.pause();
        adapter.unpause();
        vm.stopPrank();

        assertFalse(adapter.paused(), "Contract should be unpaused");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           EMERGENCY WITHDRAWAL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_EmergencyWithdrawNLP() public {
        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Pause and withdraw
        vm.startPrank(ADMIN);
        adapter.pause();

        uint treasuryBalanceBefore = nlpToken.balanceOf(TREASURY);

        vm.expectEmit(true, false, false, true);
        emit NLPToJPYCExchangeAdapter.EmergencyWithdraw(TREASURY, DEFAULT_DEPOSIT, ADMIN);

        adapter.emergencyWithdrawNLP(0); // 0 = withdraw all
        vm.stopPrank();

        assertEq(
            nlpToken.balanceOf(TREASURY),
            treasuryBalanceBefore + DEFAULT_DEPOSIT,
            "Treasury should receive NLP"
        );
        assertEq(nlpToken.balanceOf(address(adapter)), 0, "Adapter should have no NLP");
    }

    function testRevert_EmergencyWithdrawNLP_NotPaused() public {
        vm.prank(ADMIN);
        vm.expectRevert();
        adapter.emergencyWithdrawNLP(0);
    }

    function testRevert_EmergencyWithdrawNLP_TreasuryNotSet() public {
        // Deploy new adapter without treasury
        NLPToJPYCExchangeAdapter newAdapter = new NLPToJPYCExchangeAdapter(address(nlpToken), ADMIN);

        vm.startPrank(ADMIN);
        newAdapter.pause();
        vm.expectRevert(NLPToJPYCExchangeAdapter.TreasuryNotSet.selector);
        newAdapter.emergencyWithdrawNLP(0);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           INTEGRATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_FullWorkflow() public {
        // 1. User deposits NLP
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        (,,, uint balanceAfterDeposit,,) = adapter.userEscrows(USER_A);
        assertEq(balanceAfterDeposit, DEFAULT_DEPOSIT, "Balance after deposit");

        // 2. Operator burns half for JPYC exchange
        vm.prank(OPERATOR);
        adapter.burnEscrowedNLP(USER_A, DEFAULT_DEPOSIT / 2, "JPYC exchange completed");

        (,,, uint balanceAfterBurn,,) = adapter.userEscrows(USER_A);
        assertEq(balanceAfterBurn, DEFAULT_DEPOSIT / 2, "Balance after burn");

        // 3. User withdraws remaining
        vm.prank(USER_A);
        adapter.withdrawNLP(0);

        (,,, uint balanceAfterWithdraw,,) = adapter.userEscrows(USER_A);
        assertEq(balanceAfterWithdraw, 0, "Balance should be 0");

        // 4. Check final balances
        assertEq(nlpToken.balanceOf(address(adapter)), 0, "Adapter should have no NLP");
        assertEq(
            nlpToken.balanceOf(USER_A),
            INITIAL_NLP_BALANCE - DEFAULT_DEPOSIT / 2,
            "User final balance"
        );
    }

    function test_MultiUserWorkflow() public {
        // User A deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // User B deposits
        vm.startPrank(USER_B);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT * 2);
        adapter.depositNLP(DEFAULT_DEPOSIT * 2);
        vm.stopPrank();

        // Check stats
        (,,,, uint activeUsers,) = adapter.exchangeStats();
        assertEq(activeUsers, 2, "Should have 2 active users");

        // Operator burns for User A
        vm.prank(OPERATOR);
        adapter.burnEscrowedNLP(USER_A, DEFAULT_DEPOSIT, "User A exchange");

        // User B withdraws
        vm.prank(USER_B);
        adapter.withdrawNLP(0);

        // Check stats
        (,,,, activeUsers,) = adapter.exchangeStats();
        assertEq(activeUsers, 0, "Should have 0 active users");

        assertEq(nlpToken.balanceOf(address(adapter)), 0, "Adapter should be empty");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           PERMIT DEPOSIT FULL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DepositNLPWithPermit_ValidSignature() public {
        // Create a valid signer with known private key
        uint userPrivateKey = 0xA11CE;
        address user = vm.addr(userPrivateKey);

        // Mint tokens to the new user
        vm.prank(ADMIN);
        nlpToken.mint(user, INITIAL_NLP_BALANCE);

        uint depositAmount = DEFAULT_DEPOSIT;
        uint deadline = block.timestamp + 1 hours;

        // Get domain separator from NLP token
        bytes32 DOMAIN_SEPARATOR = nlpToken.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        // Build permit message hash
        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                user,
                address(adapter),
                depositAmount,
                nlpToken.nonces(user),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));

        // Sign the message
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        uint initialBalance = nlpToken.balanceOf(user);

        // Execute permit deposit via operator (relayer)
        vm.prank(OPERATOR);
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, user);

        // Verify deposit
        assertEq(nlpToken.balanceOf(address(adapter)), depositAmount, "Adapter should receive NLP");
        assertEq(
            nlpToken.balanceOf(user), initialBalance - depositAmount, "User balance should decrease"
        );

        (uint totalDeposited,,, uint currentBalance,,) = adapter.userEscrows(user);
        assertEq(totalDeposited, depositAmount, "Total deposited mismatch");
        assertEq(currentBalance, depositAmount, "Current balance mismatch");
    }

    function testRevert_DepositNLPWithPermit_ExpiredDeadline() public {
        uint userPrivateKey = 0xA11CE;
        address user = vm.addr(userPrivateKey);

        vm.prank(ADMIN);
        nlpToken.mint(user, INITIAL_NLP_BALANCE);

        uint depositAmount = DEFAULT_DEPOSIT;
        uint deadline = block.timestamp - 1; // Expired deadline

        bytes32 DOMAIN_SEPARATOR = nlpToken.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                user,
                address(adapter),
                depositAmount,
                nlpToken.nonces(user),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.PermitFailed.selector, user, depositAmount, deadline
            )
        );
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, user);
    }

    function test_DepositNLPWithPermit_WhitelistMode() public {
        // Set to whitelist mode
        vm.prank(ADMIN);
        adapter.setExchangeMode(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST);

        // Add OPERATOR to whitelist (they are the relayer)
        address[] memory accounts = new address[](1);
        accounts[0] = OPERATOR;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        vm.prank(ADMIN);
        adapter.updateWhitelist(accounts, whitelisted);

        uint userPrivateKey = 0xA11CE;
        address user = vm.addr(userPrivateKey);

        vm.prank(ADMIN);
        nlpToken.mint(user, INITIAL_NLP_BALANCE);

        uint depositAmount = DEFAULT_DEPOSIT;
        uint deadline = block.timestamp + 1 hours;

        bytes32 DOMAIN_SEPARATOR = nlpToken.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                user,
                address(adapter),
                depositAmount,
                nlpToken.nonces(user),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Operator (whitelisted) can execute permit deposit
        vm.prank(OPERATOR);
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, user);

        (,,, uint currentBalance,,) = adapter.userEscrows(user);
        assertEq(
            currentBalance,
            depositAmount,
            "Whitelisted operator should be able to execute permit deposit"
        );
    }

    function testRevert_DepositNLPWithPermit_WhitelistMode_NotWhitelisted() public {
        // Set to whitelist mode
        vm.prank(ADMIN);
        adapter.setExchangeMode(NLPToJPYCExchangeAdapter.ExchangeMode.WHITELIST);

        uint userPrivateKey = 0xA11CE;
        address user = vm.addr(userPrivateKey);

        vm.prank(ADMIN);
        nlpToken.mint(user, INITIAL_NLP_BALANCE);

        uint depositAmount = DEFAULT_DEPOSIT;
        uint deadline = block.timestamp + 1 hours;

        bytes32 DOMAIN_SEPARATOR = nlpToken.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                user,
                address(adapter),
                depositAmount,
                nlpToken.nonces(user),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, digest);

        // Unauthorized user trying to execute permit deposit in whitelist mode
        vm.prank(UNAUTHORIZED);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.NotWhitelisted.selector, UNAUTHORIZED)
        );
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, user);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           ADDITIONAL VIEW FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GetContractNLPBalance() public {
        assertEq(adapter.getContractNLPBalance(), 0, "Initial balance should be 0");

        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        assertEq(adapter.getContractNLPBalance(), DEFAULT_DEPOSIT, "Balance should equal deposit");

        vm.prank(USER_A);
        adapter.withdrawNLP(DEFAULT_DEPOSIT / 2);

        assertEq(adapter.getContractNLPBalance(), DEFAULT_DEPOSIT / 2, "Balance should be half");
    }

    function test_CalculateJPYCAmount_WithDifferentRate() public {
        // Change rate to 90 (0.9 JPYC per NLP)
        vm.prank(ADMIN);
        adapter.updateNLPToJPYCRate(90);

        uint nlpAmount = 100e18;
        uint jpycAmount = adapter.calculateJPYCAmount(nlpAmount);

        assertEq(jpycAmount, 90e18, "JPYC amount should be 90 at 0.9 rate");
    }

    function test_CalculateNLPAmount_WithDifferentRate() public {
        // Change rate to 90 (0.9 JPYC per NLP)
        vm.prank(ADMIN);
        adapter.updateNLPToJPYCRate(90);

        uint jpycAmount = 90e18;
        uint nlpAmount = adapter.calculateNLPAmount(jpycAmount);

        assertEq(nlpAmount, 100e18, "NLP amount should be 100 when JPYC is 90 at 0.9 rate");
    }

    function test_GetExchangeQuote_WithDifferentRate() public {
        // Change rate to 120 (1.2 JPYC per NLP)
        vm.prank(ADMIN);
        adapter.updateNLPToJPYCRate(120);

        uint nlpAmount = 100e18;
        (uint jpycAmount, uint rate, uint denominator, uint exchangeFee, uint operationalFee) =
            adapter.getExchangeQuote(NLPToJPYCExchangeAdapter.TokenType.JPYC, nlpAmount);

        assertEq(jpycAmount, 120e18, "JPYC amount should be 120 at 1.2 rate");
        assertEq(rate, 120, "Rate should be 120");
        assertEq(denominator, 100, "Rate denominator should be 100");
        assertEq(exchangeFee, 0, "Exchange fee should be 0");
        assertEq(operationalFee, 0, "Operational fee should be 0");
    }

    function test_GetExchangeQuote_WithJPYCTokenType() public view {
        // Verify that JPYC token type works correctly
        uint nlpAmount = 100e18;
        (uint jpycAmount,,,,) =
            adapter.getExchangeQuote(NLPToJPYCExchangeAdapter.TokenType.JPYC, nlpAmount);

        assertEq(jpycAmount, 100e18, "Should work with JPYC token type");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TREASURY MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SetTreasury() public {
        address newTreasury = address(0x99);

        vm.prank(ADMIN);
        vm.expectEmit(true, true, false, false);
        emit NLPToJPYCExchangeAdapter.TreasuryUpdated(TREASURY, newTreasury);

        adapter.setTreasury(newTreasury);

        assertEq(adapter.treasury(), newTreasury, "Treasury should be updated");
    }

    function testRevert_SetTreasury_ZeroAddress() public {
        vm.prank(ADMIN);
        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.setTreasury(address(0));
    }

    function testRevert_SetTreasury_Unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.setTreasury(address(0x99));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           DEPOSIT AMOUNT CONFIGURATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DepositAfterMinAmountUpdate() public {
        // Update minimum deposit to 5 NLP
        vm.prank(ADMIN);
        adapter.updateMinDepositAmount(5e18);

        // Should revert with old amount
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), 1e18);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.BelowMinimumDeposit.selector, 1e18, 5e18
            )
        );
        adapter.depositNLP(1e18);

        // Should succeed with new minimum
        nlpToken.approve(address(adapter), 5e18);
        adapter.depositNLP(5e18);
        vm.stopPrank();

        (,,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(currentBalance, 5e18, "Deposit should succeed with new minimum");
    }

    function testRevert_UpdateMinDepositAmount_ZeroAmount() public {
        vm.prank(ADMIN);
        vm.expectRevert(abi.encodeWithSelector(NLPToJPYCExchangeAdapter.InvalidAmount.selector, 0));
        adapter.updateMinDepositAmount(0);
    }

    function testRevert_UpdateMinDepositAmount_Unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.updateMinDepositAmount(5e18);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           ACTIVE USERS TRACKING TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_ActiveUsers_MultipleDepositsFromSameUser() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT * 3);

        adapter.depositNLP(DEFAULT_DEPOSIT);
        (,,,, uint activeUsers1,) = adapter.exchangeStats();
        assertEq(activeUsers1, 1, "Should have 1 active user after first deposit");

        adapter.depositNLP(DEFAULT_DEPOSIT);
        (,,,, uint activeUsers2,) = adapter.exchangeStats();
        assertEq(activeUsers2, 1, "Should still have 1 active user after second deposit");

        adapter.depositNLP(DEFAULT_DEPOSIT);
        (,,,, uint activeUsers3,) = adapter.exchangeStats();
        assertEq(activeUsers3, 1, "Should still have 1 active user after third deposit");

        vm.stopPrank();
    }

    function test_ActiveUsers_DepositWithdrawDeposit() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT * 2);

        adapter.depositNLP(DEFAULT_DEPOSIT);
        (,,,, uint activeUsers1,) = adapter.exchangeStats();
        assertEq(activeUsers1, 1, "Should have 1 active user");

        adapter.withdrawNLP(0); // Withdraw all
        (,,,, uint activeUsers2,) = adapter.exchangeStats();
        assertEq(activeUsers2, 0, "Should have 0 active users after full withdrawal");

        adapter.depositNLP(DEFAULT_DEPOSIT);
        (,,,, uint activeUsers3,) = adapter.exchangeStats();
        assertEq(activeUsers3, 1, "Should have 1 active user again after re-deposit");

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           BATCH OPERATIONS EDGE CASES
    ═══════════════════════════════════════════════════════════════════════ */

    function test_BatchBurnEscrowedNLP_EmptyArrays() public {
        address[] memory users = new address[](0);
        uint[] memory amounts = new uint[](0);

        vm.prank(OPERATOR);
        adapter.batchBurnEscrowedNLP(users, amounts, "Empty batch");
        // Should not revert, just do nothing
    }

    function test_BatchBurnEscrowedNLP_SkipsInvalidEntries() public {
        // Setup deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Batch with some invalid entries
        address[] memory users = new address[](5);
        users[0] = USER_A; // Valid
        users[1] = address(0); // Should skip (zero address)
        users[2] = USER_B; // Should skip (no balance)
        users[3] = USER_A; // Valid but amount is 0
        users[4] = USER_A; // Valid but insufficient balance

        uint[] memory amounts = new uint[](5);
        amounts[0] = DEFAULT_DEPOSIT / 4; // Valid
        amounts[1] = 1e18; // Skip (zero address)
        amounts[2] = 1e18; // Skip (no balance)
        amounts[3] = 0; // Skip (zero amount)
        amounts[4] = DEFAULT_DEPOSIT * 10; // Skip (insufficient balance)

        vm.prank(OPERATOR);
        adapter.batchBurnEscrowedNLP(users, amounts, "Partial batch");

        // Only first entry should be processed
        (,, uint totalBurnedA,,,) = adapter.userEscrows(USER_A);
        assertEq(totalBurnedA, DEFAULT_DEPOSIT / 4, "Should only burn first valid entry");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           GLOBAL STATISTICS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GlobalStats_ComplexScenario() public {
        // User A deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT * 2);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // User B deposits
        vm.startPrank(USER_B);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Burn half of User A's deposit
        vm.prank(OPERATOR);
        adapter.burnEscrowedNLP(USER_A, DEFAULT_DEPOSIT, "Partial burn");

        // Transfer some of User B's deposit
        vm.prank(OPERATOR);
        adapter.transferEscrowedNLP(USER_B, USER_A, DEFAULT_DEPOSIT / 2, "Partial transfer");

        // User A withdraws
        vm.prank(USER_A);
        adapter.withdrawNLP(DEFAULT_DEPOSIT / 2);

        // Check final stats
        (
            uint totalDeposited,
            uint totalWithdrawn,
            uint totalBurned,
            uint totalTransferred,
            uint activeUsers,
            uint totalTransactions
        ) = adapter.exchangeStats();

        assertEq(totalDeposited, DEFAULT_DEPOSIT * 3, "Total deposited: 3 deposits");
        assertEq(totalWithdrawn, DEFAULT_DEPOSIT / 2, "Total withdrawn: half of default");
        assertEq(totalBurned, DEFAULT_DEPOSIT, "Total burned: one default");
        assertEq(totalTransferred, DEFAULT_DEPOSIT / 2, "Total transferred: half of default");
        assertEq(activeUsers, 2, "Should have 2 active users");
        assertEq(
            totalTransactions,
            6,
            "Should have 6 total transactions (3 deposits + 1 burn + 1 transfer + 1 withdraw)"
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           FUZZ TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testFuzz_BurnEscrowedNLP(uint96 burnAmount) public {
        vm.assume(burnAmount > 0 && burnAmount <= DEFAULT_DEPOSIT);

        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Operator burns
        vm.prank(OPERATOR);
        adapter.burnEscrowedNLP(USER_A, burnAmount, "Fuzz burn");

        (,, uint totalBurned, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(totalBurned, burnAmount, "Total burned should match burn amount");
        assertEq(currentBalance, DEFAULT_DEPOSIT - burnAmount, "Current balance should be reduced");
    }

    function testFuzz_TransferEscrowedNLP(uint96 transferAmount) public {
        vm.assume(transferAmount > 0 && transferAmount <= DEFAULT_DEPOSIT);

        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        uint initialBalanceB = nlpToken.balanceOf(USER_B);

        // Operator transfers
        vm.prank(OPERATOR);
        adapter.transferEscrowedNLP(USER_A, USER_B, transferAmount, "Fuzz transfer");

        (,,, uint currentBalanceA,,) = adapter.userEscrows(USER_A);
        assertEq(
            currentBalanceA, DEFAULT_DEPOSIT - transferAmount, "Current balance should be reduced"
        );
        assertEq(
            nlpToken.balanceOf(USER_B),
            initialBalanceB + transferAmount,
            "USER_B should receive tokens"
        );
    }

    function testFuzz_WithdrawNLP(uint96 withdrawAmount) public {
        vm.assume(withdrawAmount > 0 && withdrawAmount <= DEFAULT_DEPOSIT);

        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);

        // User withdraws
        adapter.withdrawNLP(withdrawAmount);
        vm.stopPrank();

        (, uint totalWithdrawn,, uint currentBalance,,) = adapter.userEscrows(USER_A);
        assertEq(totalWithdrawn, withdrawAmount, "Total withdrawn should match");
        assertEq(
            currentBalance, DEFAULT_DEPOSIT - withdrawAmount, "Current balance should be reduced"
        );
    }

    function testFuzz_CalculateJPYCAmount(uint96 nlpAmount, uint96 rate) public {
        vm.assume(rate > 0 && rate <= 10000); // Reasonable rate range
        vm.assume(nlpAmount <= type(uint96).max / rate); // Avoid overflow

        vm.prank(ADMIN);
        adapter.updateNLPToJPYCRate(rate);

        uint jpycAmount = adapter.calculateJPYCAmount(nlpAmount);
        uint expectedJpyc = (uint(nlpAmount) * rate) / 100;

        assertEq(jpycAmount, expectedJpyc, "JPYC calculation should be correct");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           EMERGENCY WITHDRAWAL EDGE CASES
    ═══════════════════════════════════════════════════════════════════════ */

    function test_EmergencyWithdrawNLP_PartialAmount() public {
        // User deposits
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        // Pause and withdraw partial
        vm.startPrank(ADMIN);
        adapter.pause();

        uint withdrawAmount = DEFAULT_DEPOSIT / 2;
        uint treasuryBalanceBefore = nlpToken.balanceOf(TREASURY);

        adapter.emergencyWithdrawNLP(withdrawAmount);
        vm.stopPrank();

        assertEq(
            nlpToken.balanceOf(TREASURY),
            treasuryBalanceBefore + withdrawAmount,
            "Treasury should receive partial amount"
        );
        assertEq(
            nlpToken.balanceOf(address(adapter)),
            DEFAULT_DEPOSIT - withdrawAmount,
            "Adapter should have remaining balance"
        );
    }

    function testRevert_EmergencyWithdrawNLP_ExcessiveAmount() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(adapter), DEFAULT_DEPOSIT);
        adapter.depositNLP(DEFAULT_DEPOSIT);
        vm.stopPrank();

        vm.startPrank(ADMIN);
        adapter.pause();

        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.InsufficientBalance.selector,
                address(adapter),
                DEFAULT_DEPOSIT * 2,
                DEFAULT_DEPOSIT
            )
        );
        adapter.emergencyWithdrawNLP(DEFAULT_DEPOSIT * 2);
        vm.stopPrank();
    }

    function testRevert_EmergencyWithdrawNLP_Unauthorized() public {
        vm.prank(ADMIN);
        adapter.pause();

        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.emergencyWithdrawNLP(0);
    }
}
