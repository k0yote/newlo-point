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
 *      - Escrow deposit (permit-based) functionality
 *      - Operator burn and transfer operations
 *      - Role-based access control
 *      - Fee configuration
 *      - Edge cases and security considerations
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
    address constant USER_A = address(0x4);
    address constant USER_B = address(0x5);
    address constant UNAUTHORIZED = address(0x6);

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    uint constant INITIAL_NLP_BALANCE = 10000e18;
    uint constant DEFAULT_DEPOSIT = 100e18;

    // Test user with known private key for permit signatures
    uint constant TEST_USER_PRIVATE_KEY = 0xA11CE;
    address testUser;

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

        // Deploy adapter with fee parameters
        // exchangeFeeRate: 0% (no exchange fee for testing)
        // operationalFeeRate: 0% (no operational fee for testing)
        adapter = new NLPToJPYCExchangeAdapter(address(nlpToken), ADMIN, 0, 0);

        // Setup roles
        vm.startPrank(ADMIN);
        adapter.grantRole(adapter.OPERATOR_ROLE(), OPERATOR);
        adapter.grantRole(adapter.CONFIG_ROLE(), ADMIN);

        // Enable global transfers for NLP
        nlpToken.setTransfersEnabled(true);

        // Mint NLP tokens to users
        nlpToken.mint(USER_A, INITIAL_NLP_BALANCE);
        nlpToken.mint(USER_B, INITIAL_NLP_BALANCE);

        // Setup test user with private key
        testUser = vm.addr(TEST_USER_PRIVATE_KEY);
        nlpToken.mint(testUser, INITIAL_NLP_BALANCE);

        vm.stopPrank();

        // Label addresses for better trace output
        vm.label(ADMIN, "ADMIN");
        vm.label(OPERATOR, "OPERATOR");
        vm.label(USER_A, "USER_A");
        vm.label(USER_B, "USER_B");
        vm.label(UNAUTHORIZED, "UNAUTHORIZED");
        vm.label(testUser, "TEST_USER");
        vm.label(address(adapter), "NLPToJPYCExchangeAdapter");
        vm.label(address(nlpToken), "NLPToken");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                 HELPER FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Helper function to create a permit deposit for testUser
     * @param depositAmount Amount of NLP to deposit
     * @return v Signature component v
     * @return r Signature component r
     * @return s Signature component s
     * @return deadline Permit deadline
     */
    function _createPermitSignature(uint depositAmount)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s, uint deadline)
    {
        deadline = block.timestamp + 1 hours;

        bytes32 DOMAIN_SEPARATOR = nlpToken.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                testUser,
                address(adapter),
                depositAmount,
                nlpToken.nonces(testUser),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (v, r, s) = vm.sign(TEST_USER_PRIVATE_KEY, digest);
    }

    /**
     * @notice Helper to deposit NLP using permit
     */
    function _depositNLP(uint amount) internal {
        (uint8 v, bytes32 r, bytes32 s, uint deadline) = _createPermitSignature(amount);
        vm.prank(OPERATOR);
        adapter.depositNLPWithPermit(amount, deadline, v, r, s, testUser);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           INITIALIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Initialization() public view {
        assertEq(address(adapter.nlpToken()), address(nlpToken), "NLP token address mismatch");
        assertEq(adapter.nlpToJpycRate(), 100, "Initial rate should be 100");
        assertEq(adapter.minDepositAmount(), 1e18, "Min deposit should be 1e18");
        assertEq(adapter.exchangeFeeRate(), 0, "Exchange fee rate should be 0");
        assertEq(adapter.operationalFeeRate(), 0, "Operational fee rate should be 0");
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
        new NLPToJPYCExchangeAdapter(address(0), ADMIN, 0, 0);

        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        new NLPToJPYCExchangeAdapter(address(nlpToken), address(0), 0, 0);
    }

    function testRevert_InitializationWithInvalidFeeRate() public {
        // Exchange fee rate > 10000 (100%)
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.InvalidFeeRate.selector, 10001)
        );
        new NLPToJPYCExchangeAdapter(address(nlpToken), ADMIN, 10001, 0);

        // Operational fee rate > 10000 (100%)
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.InvalidFeeRate.selector, 20000)
        );
        new NLPToJPYCExchangeAdapter(address(nlpToken), ADMIN, 0, 20000);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           PERMIT DEPOSIT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DepositNLPWithPermit_ValidSignature() public {
        uint depositAmount = DEFAULT_DEPOSIT;
        uint jpycEquivalent = adapter.calculateJPYCAmount(depositAmount);

        (uint8 v, bytes32 r, bytes32 s, uint deadline) = _createPermitSignature(depositAmount);

        uint initialBalance = nlpToken.balanceOf(testUser);

        vm.expectEmit(true, true, false, true);
        emit NLPToJPYCExchangeAdapter.GaslessDepositExecuted(
            testUser, OPERATOR, depositAmount, jpycEquivalent
        );

        vm.prank(OPERATOR);
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, testUser);

        // Verify deposit
        assertEq(nlpToken.balanceOf(address(adapter)), depositAmount, "Adapter should receive NLP");
        assertEq(
            nlpToken.balanceOf(testUser),
            initialBalance - depositAmount,
            "User balance should decrease"
        );

        (uint totalDeposited,, uint currentBalance, uint depositCount, uint lastDepositTime) =
            adapter.userEscrows(testUser);
        assertEq(totalDeposited, depositAmount, "Total deposited mismatch");
        assertEq(currentBalance, depositAmount, "Current balance mismatch");
        assertEq(depositCount, 1, "Deposit count should be 1");
        assertEq(lastDepositTime, block.timestamp, "Last deposit time mismatch");
    }

    function testRevert_DepositNLPWithPermit_NotOperator() public {
        (uint8 v, bytes32 r, bytes32 s, uint deadline) = _createPermitSignature(DEFAULT_DEPOSIT);

        // Unauthorized user trying to execute
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.depositNLPWithPermit(DEFAULT_DEPOSIT, deadline, v, r, s, testUser);
    }

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
            0, block.timestamp + 1 hours, 0, bytes32(0), bytes32(0), testUser
        );
    }

    function testRevert_DepositNLPWithPermit_ExpiredDeadline() public {
        uint depositAmount = DEFAULT_DEPOSIT;
        uint deadline = block.timestamp - 1; // Expired deadline

        bytes32 DOMAIN_SEPARATOR = nlpToken.DOMAIN_SEPARATOR();
        bytes32 PERMIT_TYPEHASH = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        bytes32 structHash = keccak256(
            abi.encode(
                PERMIT_TYPEHASH,
                testUser,
                address(adapter),
                depositAmount,
                nlpToken.nonces(testUser),
                deadline
            )
        );

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(TEST_USER_PRIVATE_KEY, digest);

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.PermitFailed.selector, testUser, depositAmount, deadline
            )
        );
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, testUser);
    }

    function testRevert_DepositNLPWithPermit_BelowMinimum() public {
        uint depositAmount = 0.5e18; // Below minimum
        (uint8 v, bytes32 r, bytes32 s, uint deadline) = _createPermitSignature(depositAmount);

        vm.prank(OPERATOR);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToJPYCExchangeAdapter.BelowMinimumDeposit.selector, depositAmount, 1e18
            )
        );
        adapter.depositNLPWithPermit(depositAmount, deadline, v, r, s, testUser);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           BURN TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_BurnEscrowedNLP() public {
        // User deposits using permit
        _depositNLP(DEFAULT_DEPOSIT);

        uint burnAmount = DEFAULT_DEPOSIT / 2;
        uint jpycEquivalent = adapter.calculateJPYCAmount(burnAmount);
        string memory reason = "Exchange completed";

        vm.startPrank(OPERATOR);
        vm.expectEmit(true, true, false, true);
        emit NLPToJPYCExchangeAdapter.EscrowedNLPBurned(
            testUser, OPERATOR, burnAmount, jpycEquivalent, reason
        );

        adapter.burnEscrowedNLP(testUser, burnAmount, reason);
        vm.stopPrank();

        // Check escrow data
        (, uint totalBurned, uint currentBalance,,) = adapter.userEscrows(testUser);

        assertEq(totalBurned, burnAmount, "Total burned mismatch");
        assertEq(currentBalance, DEFAULT_DEPOSIT - burnAmount, "Current balance mismatch");
    }

    function test_BurnEscrowedNLP_All() public {
        _depositNLP(DEFAULT_DEPOSIT);

        vm.prank(OPERATOR);
        adapter.burnEscrowedNLP(testUser, DEFAULT_DEPOSIT, "Full burn");

        // Check escrow data
        (,, uint currentBalance,,) = adapter.userEscrows(testUser);
        assertEq(currentBalance, 0, "Current balance should be 0");
    }

    function testRevert_BurnEscrowedNLP_Unauthorized() public {
        _depositNLP(DEFAULT_DEPOSIT);

        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.burnEscrowedNLP(testUser, DEFAULT_DEPOSIT, "Unauthorized");
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
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.NoEscrowBalance.selector, testUser)
        );
        adapter.burnEscrowedNLP(testUser, 1e18, "No balance");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TRANSFER TESTS (Refund functionality)
    ═══════════════════════════════════════════════════════════════════════ */

    function test_TransferEscrowedNLP() public {
        _depositNLP(DEFAULT_DEPOSIT);

        uint transferAmount = DEFAULT_DEPOSIT / 2;
        string memory reason = "Refund";

        uint initialBalanceUserA = nlpToken.balanceOf(USER_A);

        vm.startPrank(OPERATOR);
        vm.expectEmit(true, true, true, true);
        emit NLPToJPYCExchangeAdapter.EscrowedNLPTransferred(
            testUser, USER_A, OPERATOR, transferAmount, reason
        );

        adapter.transferEscrowedNLP(testUser, USER_A, transferAmount, reason);
        vm.stopPrank();

        // Check balances
        assertEq(
            nlpToken.balanceOf(USER_A),
            initialBalanceUserA + transferAmount,
            "USER_A should receive NLP"
        );

        // Check escrow data
        (,, uint currentBalance,,) = adapter.userEscrows(testUser);
        assertEq(currentBalance, DEFAULT_DEPOSIT - transferAmount, "Current balance mismatch");
    }

    function test_TransferEscrowedNLP_ToSelf() public {
        _depositNLP(DEFAULT_DEPOSIT);

        uint initialBalance = nlpToken.balanceOf(testUser);

        vm.prank(OPERATOR);
        adapter.transferEscrowedNLP(testUser, testUser, DEFAULT_DEPOSIT, "Return to user");

        // Check balance
        assertEq(
            nlpToken.balanceOf(testUser),
            initialBalance + DEFAULT_DEPOSIT,
            "User should receive NLP back"
        );

        // Check escrow data
        (,, uint currentBalance,,) = adapter.userEscrows(testUser);
        assertEq(currentBalance, 0, "Current balance should be 0");
    }

    function testRevert_TransferEscrowedNLP_Unauthorized() public {
        _depositNLP(DEFAULT_DEPOSIT);

        vm.startPrank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.transferEscrowedNLP(testUser, USER_A, DEFAULT_DEPOSIT, "Unauthorized");
        vm.stopPrank();
    }

    function testRevert_TransferEscrowedNLP_ZeroAddress() public {
        vm.startPrank(OPERATOR);

        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.transferEscrowedNLP(address(0), USER_A, 1e18, "Zero from");

        vm.expectRevert(NLPToJPYCExchangeAdapter.ZeroAddress.selector);
        adapter.transferEscrowedNLP(testUser, address(0), 1e18, "Zero to");

        vm.stopPrank();
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
                           FEE CONFIGURATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_UpdateExchangeFeeRate() public {
        uint newFeeRate = 100; // 1%

        vm.startPrank(ADMIN);
        vm.expectEmit(false, false, false, true);
        emit NLPToJPYCExchangeAdapter.ExchangeFeeRateUpdated(0, newFeeRate, ADMIN);

        adapter.updateExchangeFeeRate(newFeeRate);
        vm.stopPrank();

        assertEq(adapter.exchangeFeeRate(), newFeeRate, "Exchange fee rate should be updated");
    }

    function testRevert_UpdateExchangeFeeRate_ExceedsMax() public {
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.InvalidFeeRate.selector, 10001)
        );
        adapter.updateExchangeFeeRate(10001); // > 100%
    }

    function testRevert_UpdateExchangeFeeRate_Unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.updateExchangeFeeRate(100);
    }

    function test_UpdateOperationalFeeRate() public {
        uint newFeeRate = 50; // 0.5%

        vm.startPrank(ADMIN);
        vm.expectEmit(false, false, false, true);
        emit NLPToJPYCExchangeAdapter.OperationalFeeRateUpdated(0, newFeeRate, ADMIN);

        adapter.updateOperationalFeeRate(newFeeRate);
        vm.stopPrank();

        assertEq(adapter.operationalFeeRate(), newFeeRate, "Operational fee rate should be updated");
    }

    function testRevert_UpdateOperationalFeeRate_ExceedsMax() public {
        vm.prank(ADMIN);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToJPYCExchangeAdapter.InvalidFeeRate.selector, 20000)
        );
        adapter.updateOperationalFeeRate(20000); // > 100%
    }

    function testRevert_UpdateOperationalFeeRate_Unauthorized() public {
        vm.prank(UNAUTHORIZED);
        vm.expectRevert();
        adapter.updateOperationalFeeRate(50);
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

    function test_GetExchangeQuote_WithFees() public {
        // Set fee rates
        vm.startPrank(ADMIN);
        adapter.updateExchangeFeeRate(100); // 1%
        adapter.updateOperationalFeeRate(50); // 0.5%
        vm.stopPrank();

        uint nlpAmount = 100e18;
        (uint jpycAmount, uint rate, uint denominator, uint exchangeFee, uint operationalFee) =
            adapter.getExchangeQuote(NLPToJPYCExchangeAdapter.TokenType.JPYC, nlpAmount);

        uint grossAmount = 100e18; // 1:1 rate
        uint expectedExchangeFee = (grossAmount * 100) / 10000; // 1e18
        uint expectedOperationalFee = (grossAmount * 50) / 10000; // 0.5e18
        uint expectedNetAmount = grossAmount - expectedExchangeFee - expectedOperationalFee; // 98.5e18

        assertEq(jpycAmount, expectedNetAmount, "JPYC amount should be net after fees");
        assertEq(rate, 100, "Rate should be 100");
        assertEq(denominator, 100, "Rate denominator should be 100");
        assertEq(exchangeFee, expectedExchangeFee, "Exchange fee should be 1%");
        assertEq(operationalFee, expectedOperationalFee, "Operational fee should be 0.5%");
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
        _depositNLP(DEFAULT_DEPOSIT);

        NLPToJPYCExchangeAdapter.UserEscrow memory escrow = adapter.getUserEscrow(testUser);

        assertEq(escrow.totalDeposited, DEFAULT_DEPOSIT, "Total deposited mismatch");
        assertEq(escrow.currentBalance, DEFAULT_DEPOSIT, "Current balance mismatch");
        assertEq(escrow.depositCount, 1, "Deposit count mismatch");
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

        (uint8 v, bytes32 r, bytes32 s, uint deadline) = _createPermitSignature(DEFAULT_DEPOSIT);

        vm.prank(OPERATOR);
        vm.expectRevert();
        adapter.depositNLPWithPermit(DEFAULT_DEPOSIT, deadline, v, r, s, testUser);
    }

    function test_Unpause() public {
        vm.startPrank(ADMIN);
        adapter.pause();
        adapter.unpause();
        vm.stopPrank();

        assertFalse(adapter.paused(), "Contract should be unpaused");
    }
}
