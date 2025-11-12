// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { NLPBurnWithPermit } from "../src/NLPBurnWithPermit.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NLPBurnWithPermitTest
 * @author NewLo Team
 * @notice Comprehensive test suite for NLPBurnWithPermit contract
 * @dev This test suite covers:
 *      - Contract deployment and initialization
 *      - Direct burn functionality
 *      - Permit-based gasless burn
 *      - Access control and role management
 *      - Whitelist functionality
 *      - Pause/unpause functionality
 *      - Statistics tracking
 *      - Error conditions and edge cases
 */
contract NLPBurnWithPermitTest is Test {
    /* ═══════════════════════════════════════════════════════════════════════
                               TEST CONTRACTS
    ═══════════════════════════════════════════════════════════════════════ */

    NLPBurnWithPermit burnContract;
    NewLoPoint nlpToken;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST ACTORS
    ═══════════════════════════════════════════════════════════════════════ */

    address constant DEFAULT_ADMIN = address(0x1);
    address constant OPERATOR = address(0x2);
    address constant PAUSER = address(0x3);
    address constant USER_A = address(0x4);
    address constant USER_B = address(0x5);
    address constant MINTER = address(0x6);

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    uint constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint constant BURN_AMOUNT = 1000 * 1e18;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST SETUP
    ═══════════════════════════════════════════════════════════════════════ */

    function setUp() public {
        // Deploy NLP token with proxy
        NewLoPoint impl = new NewLoPoint();
        admin = new ProxyAdmin(DEFAULT_ADMIN);

        bytes memory data =
            abi.encodeWithSelector(impl.initialize.selector, DEFAULT_ADMIN, PAUSER, MINTER);

        proxy = new TransparentUpgradeableProxy(address(impl), address(admin), data);
        nlpToken = NewLoPoint(address(proxy));

        // Deploy burn contract
        burnContract = new NLPBurnWithPermit(address(nlpToken), DEFAULT_ADMIN);

        // Setup: Enable transfers and mint tokens
        vm.startPrank(DEFAULT_ADMIN);
        nlpToken.setTransfersEnabled(true);
        vm.stopPrank();

        // Mint tokens to users
        vm.startPrank(MINTER);
        nlpToken.mint(USER_A, INITIAL_SUPPLY);
        nlpToken.mint(USER_B, INITIAL_SUPPLY);
        vm.stopPrank();

        // Grant roles
        vm.startPrank(DEFAULT_ADMIN);
        burnContract.grantRole(burnContract.OPERATOR_ROLE(), OPERATOR);
        burnContract.grantRole(burnContract.PAUSER_ROLE(), PAUSER);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          DEPLOYMENT & INITIALIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Deployment() public view {
        assertEq(address(burnContract.nlpToken()), address(nlpToken));
        assertEq(burnContract.totalBurned(), 0);
        assertEq(burnContract.burnCount(), 0);
        assertTrue(
            burnContract.hasRole(burnContract.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN),
            "Admin role not granted"
        );
    }

    function test_InitialBurnMode() public view {
        assertEq(uint(burnContract.getBurnMode()), uint(NLPBurnWithPermit.BurnMode.PUBLIC));
    }

    function test_RolesAssigned() public view {
        assertTrue(burnContract.hasRole(burnContract.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN));
        assertTrue(burnContract.hasRole(burnContract.OPERATOR_ROLE(), OPERATOR));
        assertTrue(burnContract.hasRole(burnContract.OPERATOR_ROLE(), DEFAULT_ADMIN));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          DIRECT BURN TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DirectBurn() public {
        uint initialBalance = nlpToken.balanceOf(USER_A);

        // Approve burn contract
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);

        // Execute burn
        vm.expectEmit(true, false, false, true);
        emit NLPBurnWithPermit.TokensBurned(USER_A, BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();

        // Verify balances
        assertEq(nlpToken.balanceOf(USER_A), initialBalance - BURN_AMOUNT);
        assertEq(burnContract.totalBurned(), BURN_AMOUNT);
        assertEq(burnContract.burnCount(), 1);
        assertEq(burnContract.userBurnAmount(USER_A), BURN_AMOUNT);
        assertEq(burnContract.userBurnCount(USER_A), 1);
    }

    function test_DirectBurn_MultipleUsers() public {
        // USER_A burns
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();

        // USER_B burns
        vm.startPrank(USER_B);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();

        // Verify total stats
        assertEq(burnContract.totalBurned(), BURN_AMOUNT * 2);
        assertEq(burnContract.burnCount(), 2);

        // Verify individual stats
        assertEq(burnContract.userBurnAmount(USER_A), BURN_AMOUNT);
        assertEq(burnContract.userBurnAmount(USER_B), BURN_AMOUNT);
    }

    function test_DirectBurn_MultipleTimes() public {
        vm.startPrank(USER_A);

        // First burn
        nlpToken.approve(address(burnContract), BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);

        // Second burn
        nlpToken.approve(address(burnContract), BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);

        vm.stopPrank();

        assertEq(burnContract.userBurnAmount(USER_A), BURN_AMOUNT * 2);
        assertEq(burnContract.userBurnCount(USER_A), 2);
        assertEq(burnContract.totalBurned(), BURN_AMOUNT * 2);
    }

    function test_RevertWhen_BurnAmountZero() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(NLPBurnWithPermit.InvalidBurnAmount.selector, 0));
        burnContract.burn(0);
        vm.stopPrank();
    }

    function test_RevertWhen_InsufficientApproval() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT / 2);

        vm.expectRevert();
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          PERMIT BURN TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_BurnWithPermit() public {
        // Create permit signature
        uint privateKey = 0xA11CE;
        address user = vm.addr(privateKey);

        // Mint tokens to user
        vm.prank(MINTER);
        nlpToken.mint(user, BURN_AMOUNT);

        uint initialBalance = nlpToken.balanceOf(user);
        uint deadline = block.timestamp + 1 hours;

        // Create permit signature
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                nlpToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        user,
                        address(burnContract),
                        BURN_AMOUNT,
                        nlpToken.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, permitHash);

        // Execute burn with permit
        vm.startPrank(OPERATOR);
        vm.expectEmit(true, true, false, true);
        emit NLPBurnWithPermit.TokensBurnedWithPermit(user, OPERATOR, BURN_AMOUNT, deadline);
        burnContract.burnWithPermit(user, BURN_AMOUNT, deadline, v, r, s);
        vm.stopPrank();

        // Verify balances and stats
        assertEq(nlpToken.balanceOf(user), initialBalance - BURN_AMOUNT);
        assertEq(burnContract.totalBurned(), BURN_AMOUNT);
        assertEq(burnContract.userBurnAmount(user), BURN_AMOUNT);
    }

    function test_RevertWhen_BurnWithPermit_NotOperator() public {
        uint privateKey = 0xA11CE;
        address user = vm.addr(privateKey);

        vm.prank(MINTER);
        nlpToken.mint(user, BURN_AMOUNT);

        uint deadline = block.timestamp + 1 hours;

        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                nlpToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        user,
                        address(burnContract),
                        BURN_AMOUNT,
                        nlpToken.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, permitHash);

        // Try to call from non-operator
        vm.startPrank(USER_A);
        vm.expectRevert();
        burnContract.burnWithPermit(user, BURN_AMOUNT, deadline, v, r, s);
        vm.stopPrank();
    }

    function test_RevertWhen_BurnWithPermit_InvalidUser() public {
        uint deadline = block.timestamp + 1 hours;

        vm.startPrank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(NLPBurnWithPermit.InvalidUser.selector, address(0)));
        burnContract.burnWithPermit(address(0), BURN_AMOUNT, deadline, 0, bytes32(0), bytes32(0));
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          WHITELIST MODE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SetBurnMode() public {
        vm.startPrank(DEFAULT_ADMIN);

        vm.expectEmit(true, true, true, true);
        emit NLPBurnWithPermit.BurnModeUpdated(
            NLPBurnWithPermit.BurnMode.PUBLIC, NLPBurnWithPermit.BurnMode.WHITELIST, DEFAULT_ADMIN
        );
        burnContract.setBurnMode(NLPBurnWithPermit.BurnMode.WHITELIST);

        assertEq(uint(burnContract.getBurnMode()), uint(NLPBurnWithPermit.BurnMode.WHITELIST));
        vm.stopPrank();
    }

    function test_WhitelistMode_AllowsWhitelistedUser() public {
        // Set whitelist mode
        vm.startPrank(DEFAULT_ADMIN);
        burnContract.setBurnMode(NLPBurnWithPermit.BurnMode.WHITELIST);

        address[] memory accounts = new address[](1);
        accounts[0] = USER_A;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        burnContract.updateWhitelist(accounts, whitelisted);
        vm.stopPrank();

        // USER_A (whitelisted) should be able to burn
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();

        assertEq(burnContract.userBurnAmount(USER_A), BURN_AMOUNT);
    }

    function test_RevertWhen_WhitelistMode_NotWhitelisted() public {
        // Set whitelist mode
        vm.startPrank(DEFAULT_ADMIN);
        burnContract.setBurnMode(NLPBurnWithPermit.BurnMode.WHITELIST);
        vm.stopPrank();

        // USER_A (not whitelisted) should not be able to burn
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);

        vm.expectRevert(abi.encodeWithSelector(NLPBurnWithPermit.NotWhitelisted.selector, USER_A));
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();
    }

    function test_UpdateWhitelist_Batch() public {
        vm.startPrank(DEFAULT_ADMIN);

        address[] memory accounts = new address[](2);
        accounts[0] = USER_A;
        accounts[1] = USER_B;

        bool[] memory whitelisted = new bool[](2);
        whitelisted[0] = true;
        whitelisted[1] = true;

        burnContract.updateWhitelist(accounts, whitelisted);

        assertTrue(burnContract.isWhitelisted(USER_A));
        assertTrue(burnContract.isWhitelisted(USER_B));
        vm.stopPrank();
    }

    function test_WhitelistMode_PermitBurn_WhitelistedOperator() public {
        // Create permit signature
        uint privateKey = 0xA11CE;
        address user = vm.addr(privateKey);

        // Mint tokens to user
        vm.prank(MINTER);
        nlpToken.mint(user, BURN_AMOUNT);

        // Set whitelist mode and whitelist the OPERATOR (not the user)
        vm.startPrank(DEFAULT_ADMIN);
        burnContract.setBurnMode(NLPBurnWithPermit.BurnMode.WHITELIST);

        address[] memory accounts = new address[](1);
        accounts[0] = OPERATOR;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        burnContract.updateWhitelist(accounts, whitelisted);
        vm.stopPrank();

        uint deadline = block.timestamp + 1 hours;

        // Create permit signature
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                nlpToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        user,
                        address(burnContract),
                        BURN_AMOUNT,
                        nlpToken.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, permitHash);

        // Execute burn with permit - should succeed because OPERATOR is whitelisted
        vm.startPrank(OPERATOR);
        burnContract.burnWithPermit(user, BURN_AMOUNT, deadline, v, r, s);
        vm.stopPrank();

        // Verify burn was successful
        assertEq(nlpToken.balanceOf(user), 0);
        assertEq(burnContract.userBurnAmount(user), BURN_AMOUNT);
    }

    function test_RevertWhen_WhitelistMode_PermitBurn_OperatorNotWhitelisted() public {
        // Create permit signature
        uint privateKey = 0xA11CE;
        address user = vm.addr(privateKey);

        // Mint tokens to user
        vm.prank(MINTER);
        nlpToken.mint(user, BURN_AMOUNT);

        // Set whitelist mode but don't whitelist the OPERATOR
        vm.prank(DEFAULT_ADMIN);
        burnContract.setBurnMode(NLPBurnWithPermit.BurnMode.WHITELIST);

        uint deadline = block.timestamp + 1 hours;

        // Create permit signature
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                nlpToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        user,
                        address(burnContract),
                        BURN_AMOUNT,
                        nlpToken.nonces(user),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(privateKey, permitHash);

        // Execute burn with permit - should fail because OPERATOR is not whitelisted
        vm.startPrank(OPERATOR);
        vm.expectRevert(abi.encodeWithSelector(NLPBurnWithPermit.NotWhitelisted.selector, OPERATOR));
        burnContract.burnWithPermit(user, BURN_AMOUNT, deadline, v, r, s);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          PAUSE FUNCTIONALITY TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Pause() public {
        vm.startPrank(PAUSER);
        burnContract.pause();
        assertTrue(burnContract.paused());
        vm.stopPrank();
    }

    function test_Unpause() public {
        vm.startPrank(PAUSER);
        burnContract.pause();
        burnContract.unpause();
        assertFalse(burnContract.paused());
        vm.stopPrank();
    }

    function test_RevertWhen_BurnWhilePaused() public {
        vm.prank(PAUSER);
        burnContract.pause();

        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);

        vm.expectRevert();
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          VIEW FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GetTotalBurnStats() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();

        (uint totalBurned, uint burnCount) = burnContract.getTotalBurnStats();
        assertEq(totalBurned, BURN_AMOUNT);
        assertEq(burnCount, 1);
    }

    function test_GetUserBurnStats() public {
        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), BURN_AMOUNT * 2);
        burnContract.burn(BURN_AMOUNT);
        burnContract.burn(BURN_AMOUNT);
        vm.stopPrank();

        (uint amount, uint count) = burnContract.getUserBurnStats(USER_A);
        assertEq(amount, BURN_AMOUNT * 2);
        assertEq(count, 2);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_RevertWhen_SetBurnMode_NotAdmin() public {
        vm.startPrank(USER_A);
        vm.expectRevert();
        burnContract.setBurnMode(NLPBurnWithPermit.BurnMode.WHITELIST);
        vm.stopPrank();
    }

    function test_RevertWhen_UpdateWhitelist_NotManager() public {
        address[] memory accounts = new address[](1);
        accounts[0] = USER_A;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        vm.startPrank(USER_A);
        vm.expectRevert();
        burnContract.updateWhitelist(accounts, whitelisted);
        vm.stopPrank();
    }

    function test_RevertWhen_Pause_NotPauser() public {
        vm.startPrank(USER_A);
        vm.expectRevert();
        burnContract.pause();
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          FUZZ TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testFuzz_DirectBurn(uint amount) public {
        vm.assume(amount > 0 && amount <= INITIAL_SUPPLY);

        vm.startPrank(USER_A);
        nlpToken.approve(address(burnContract), amount);
        burnContract.burn(amount);
        vm.stopPrank();

        assertEq(burnContract.userBurnAmount(USER_A), amount);
    }

    function testFuzz_MultipleBurns(uint8 numBurns) public {
        vm.assume(numBurns > 0 && numBurns <= 10);

        uint burnAmount = BURN_AMOUNT / numBurns;

        vm.startPrank(USER_A);
        for (uint i = 0; i < numBurns; i++) {
            nlpToken.approve(address(burnContract), burnAmount);
            burnContract.burn(burnAmount);
        }
        vm.stopPrank();

        assertEq(burnContract.userBurnCount(USER_A), numBurns);
        assertEq(burnContract.userBurnAmount(USER_A), burnAmount * numBurns);
    }
}
