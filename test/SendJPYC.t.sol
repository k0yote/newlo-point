// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { SendJPYC } from "../src/SendJPYC.sol";
import { MockJPYC } from "./mocks/MockJPYC.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title SendJPYCTest
 * @author NewLo Team
 * @notice Comprehensive test suite for SendJPYC contract
 * @dev This test suite covers:
 *      - Contract deployment and initialization
 *      - EIP-2612 permit-based transfers
 *      - EIP-3009 authorization-based transfers
 *      - Access control and role management
 *      - Pause/unpause functionality
 *      - Statistics tracking
 *      - Error conditions and edge cases
 *      - UUPS upgrade functionality
 */
contract SendJPYCTest is Test {
    /* ═══════════════════════════════════════════════════════════════════════
                               TEST CONTRACTS
    ═══════════════════════════════════════════════════════════════════════ */

    SendJPYC sendJpyc;
    SendJPYC sendJpycImpl;
    MockJPYC jpycToken;
    ERC1967Proxy proxy;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST ACTORS
    ═══════════════════════════════════════════════════════════════════════ */

    address constant DEFAULT_ADMIN = address(0x1);
    address constant OPERATOR = address(0x2);
    address constant PAUSER = address(0x3);
    address constant MINTER_ADMIN = address(0x4);
    address constant MINTER = address(0x5);
    address constant BLOCKLISTER = address(0x6);
    address constant RESCUER = address(0x7);
    address constant OWNER = address(0x8);

    uint constant USER_A_PRIVATE_KEY = 0xA11CE;
    uint constant USER_B_PRIVATE_KEY = 0xB0B;
    address USER_A;
    address USER_B;
    address constant RECIPIENT = address(0x100);

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST CONSTANTS
    ═══════════════════════════════════════════════════════════════════════ */

    uint constant INITIAL_SUPPLY = 1_000_000 * 1e18;
    uint constant TRANSFER_AMOUNT = 1000 * 1e18;

    // EIP-712 Type Hashes
    bytes32 constant PERMIT_TYPEHASH = keccak256(
        "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
    );

    bytes32 constant TRANSFER_WITH_AUTHORIZATION_TYPEHASH = keccak256(
        "TransferWithAuthorization(address from,address to,uint256 value,uint256 validAfter,uint256 validBefore,bytes32 nonce)"
    );

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST SETUP
    ═══════════════════════════════════════════════════════════════════════ */

    function setUp() public {
        // Derive user addresses from private keys
        USER_A = vm.addr(USER_A_PRIVATE_KEY);
        USER_B = vm.addr(USER_B_PRIVATE_KEY);

        // Deploy JPYC token (MockJPYC)
        jpycToken = new MockJPYC();

        // Mint tokens to users
        jpycToken.mint(USER_A, INITIAL_SUPPLY);
        jpycToken.mint(USER_B, INITIAL_SUPPLY);

        // Deploy SendJPYC with UUPS proxy
        sendJpycImpl = new SendJPYC();
        bytes memory initData = abi.encodeWithSelector(
            SendJPYC.initialize.selector, address(jpycToken), DEFAULT_ADMIN
        );
        proxy = new ERC1967Proxy(address(sendJpycImpl), initData);
        sendJpyc = SendJPYC(address(proxy));

        // Grant roles
        vm.startPrank(DEFAULT_ADMIN);
        sendJpyc.grantRole(sendJpyc.OPERATOR_ROLE(), OPERATOR);
        sendJpyc.grantRole(sendJpyc.PAUSER_ROLE(), PAUSER);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          DEPLOYMENT & INITIALIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Deployment() public view {
        assertEq(address(sendJpyc.jpycToken()), address(jpycToken));
        assertEq(sendJpyc.totalPermitTransfers(), 0);
        assertEq(sendJpyc.totalAuthTransfers(), 0);
        assertEq(sendJpyc.totalPermitAmount(), 0);
        assertEq(sendJpyc.totalAuthAmount(), 0);
        assertTrue(
            sendJpyc.hasRole(sendJpyc.DEFAULT_ADMIN_ROLE(), DEFAULT_ADMIN), "Admin role not granted"
        );
        assertTrue(
            sendJpyc.hasRole(sendJpyc.OPERATOR_ROLE(), DEFAULT_ADMIN),
            "Operator role not granted to admin"
        );
        assertTrue(
            sendJpyc.hasRole(sendJpyc.PAUSER_ROLE(), DEFAULT_ADMIN),
            "Pauser role not granted to admin"
        );
    }

    function test_InitializeRevertsOnZeroJPYC() public {
        SendJPYC impl = new SendJPYC();
        bytes memory initData =
            abi.encodeWithSelector(SendJPYC.initialize.selector, address(0), DEFAULT_ADMIN);
        vm.expectRevert(SendJPYC.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    function test_InitializeRevertsOnZeroAdmin() public {
        SendJPYC impl = new SendJPYC();
        bytes memory initData =
            abi.encodeWithSelector(SendJPYC.initialize.selector, address(jpycToken), address(0));
        vm.expectRevert(SendJPYC.ZeroAddress.selector);
        new ERC1967Proxy(address(impl), initData);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          EIP-2612 PERMIT TRANSFER TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SendWithPermit() public {
        uint deadline = block.timestamp + 1 hours;
        uint nonce = jpycToken.nonces(USER_A);

        // Create permit signature
        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, USER_A, address(sendJpyc), TRANSFER_AMOUNT, nonce, deadline)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        uint recipientBalanceBefore = jpycToken.balanceOf(RECIPIENT);

        // Execute transfer
        vm.prank(OPERATOR);
        sendJpyc.sendWithPermit(USER_A, RECIPIENT, TRANSFER_AMOUNT, deadline, v, r, s);

        // Verify transfer
        assertEq(jpycToken.balanceOf(RECIPIENT), recipientBalanceBefore + TRANSFER_AMOUNT);
        assertEq(sendJpyc.totalPermitTransfers(), 1);
        assertEq(sendJpyc.totalPermitAmount(), TRANSFER_AMOUNT);
    }

    function test_SendWithPermit_RevertsOnExpiredDeadline() public {
        uint deadline = block.timestamp - 1; // Expired
        uint nonce = jpycToken.nonces(USER_A);

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, USER_A, address(sendJpyc), TRANSFER_AMOUNT, nonce, deadline)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.PermitExpired.selector);
        sendJpyc.sendWithPermit(USER_A, RECIPIENT, TRANSFER_AMOUNT, deadline, v, r, s);
    }

    function test_SendWithPermit_RevertsOnZeroAmount() public {
        uint deadline = block.timestamp + 1 hours;
        uint nonce = jpycToken.nonces(USER_A);

        bytes32 structHash =
            keccak256(abi.encode(PERMIT_TYPEHASH, USER_A, address(sendJpyc), 0, nonce, deadline));
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.ZeroAmount.selector);
        sendJpyc.sendWithPermit(USER_A, RECIPIENT, 0, deadline, v, r, s);
    }

    function test_SendWithPermit_RevertsOnInvalidFrom() public {
        uint deadline = block.timestamp + 1 hours;

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.InvalidFromAddress.selector);
        sendJpyc.sendWithPermit(
            address(0), RECIPIENT, TRANSFER_AMOUNT, deadline, 0, bytes32(0), bytes32(0)
        );
    }

    function test_SendWithPermit_RevertsOnInvalidTo() public {
        uint deadline = block.timestamp + 1 hours;

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.InvalidToAddress.selector);
        sendJpyc.sendWithPermit(
            USER_A, address(0), TRANSFER_AMOUNT, deadline, 0, bytes32(0), bytes32(0)
        );
    }

    function test_SendWithPermit_RevertsWithoutOperatorRole() public {
        uint deadline = block.timestamp + 1 hours;

        vm.prank(USER_A);
        vm.expectRevert();
        sendJpyc.sendWithPermit(
            USER_A, RECIPIENT, TRANSFER_AMOUNT, deadline, 0, bytes32(0), bytes32(0)
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                      EIP-3009 AUTHORIZATION TRANSFER TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SendWithAuthorization() public {
        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        // Create authorization signature
        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                USER_A,
                RECIPIENT,
                TRANSFER_AMOUNT,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        uint recipientBalanceBefore = jpycToken.balanceOf(RECIPIENT);

        // Execute transfer
        vm.prank(OPERATOR);
        sendJpyc.sendWithAuthorization(
            USER_A, RECIPIENT, TRANSFER_AMOUNT, validAfter, validBefore, nonce, v, r, s
        );

        // Verify transfer
        assertEq(jpycToken.balanceOf(RECIPIENT), recipientBalanceBefore + TRANSFER_AMOUNT);
        assertEq(sendJpyc.totalAuthTransfers(), 1);
        assertEq(sendJpyc.totalAuthAmount(), TRANSFER_AMOUNT);
    }

    function test_SendWithAuthorization_RevertsOnInvalidTimeWindow() public {
        uint validAfter = block.timestamp + 1 hours;
        uint validBefore = block.timestamp; // validBefore <= validAfter
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.InvalidTimeWindow.selector);
        sendJpyc.sendWithAuthorization(
            USER_A,
            RECIPIENT,
            TRANSFER_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_SendWithAuthorization_RevertsOnZeroAmount() public {
        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.ZeroAmount.selector);
        sendJpyc.sendWithAuthorization(
            USER_A, RECIPIENT, 0, validAfter, validBefore, nonce, 0, bytes32(0), bytes32(0)
        );
    }

    function test_SendWithAuthorization_RevertsOnInvalidFrom() public {
        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.InvalidFromAddress.selector);
        sendJpyc.sendWithAuthorization(
            address(0),
            RECIPIENT,
            TRANSFER_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_SendWithAuthorization_RevertsOnInvalidTo() public {
        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        vm.prank(OPERATOR);
        vm.expectRevert(SendJPYC.InvalidToAddress.selector);
        sendJpyc.sendWithAuthorization(
            USER_A,
            address(0),
            TRANSFER_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_SendWithAuthorization_RevertsWithoutOperatorRole() public {
        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        vm.prank(USER_A);
        vm.expectRevert();
        sendJpyc.sendWithAuthorization(
            USER_A,
            RECIPIENT,
            TRANSFER_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            PAUSE FUNCTIONALITY TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Pause() public {
        vm.prank(PAUSER);
        sendJpyc.pause();
        assertTrue(sendJpyc.paused());
    }

    function test_Unpause() public {
        vm.prank(PAUSER);
        sendJpyc.pause();

        vm.prank(PAUSER);
        sendJpyc.unpause();
        assertFalse(sendJpyc.paused());
    }

    function test_SendWithPermit_RevertsWhenPaused() public {
        vm.prank(PAUSER);
        sendJpyc.pause();

        uint deadline = block.timestamp + 1 hours;

        vm.prank(OPERATOR);
        vm.expectRevert();
        sendJpyc.sendWithPermit(
            USER_A, RECIPIENT, TRANSFER_AMOUNT, deadline, 0, bytes32(0), bytes32(0)
        );
    }

    function test_SendWithAuthorization_RevertsWhenPaused() public {
        vm.prank(PAUSER);
        sendJpyc.pause();

        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));

        vm.prank(OPERATOR);
        vm.expectRevert();
        sendJpyc.sendWithAuthorization(
            USER_A,
            RECIPIENT,
            TRANSFER_AMOUNT,
            validAfter,
            validBefore,
            nonce,
            0,
            bytes32(0),
            bytes32(0)
        );
    }

    function test_PauseRevertsWithoutPauserRole() public {
        vm.prank(USER_A);
        vm.expectRevert();
        sendJpyc.pause();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ADMIN FUNCTIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SetJPYCToken() public {
        MockJPYC newJpyc = new MockJPYC();

        vm.prank(DEFAULT_ADMIN);
        sendJpyc.setJPYCToken(address(newJpyc));

        assertEq(address(sendJpyc.jpycToken()), address(newJpyc));
    }

    function test_SetJPYCToken_RevertsOnZeroAddress() public {
        vm.prank(DEFAULT_ADMIN);
        vm.expectRevert(SendJPYC.ZeroAddress.selector);
        sendJpyc.setJPYCToken(address(0));
    }

    function test_SetJPYCToken_RevertsWithoutAdminRole() public {
        vm.prank(USER_A);
        vm.expectRevert();
        sendJpyc.setJPYCToken(address(1));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            VIEW FUNCTIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GetPermitNonce() public view {
        uint nonce = sendJpyc.getPermitNonce(USER_A);
        assertEq(nonce, jpycToken.nonces(USER_A));
    }

    function test_IsAuthorizationUsed() public view {
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp));
        assertFalse(sendJpyc.isAuthorizationUsed(USER_A, nonce));
    }

    function test_GetDomainSeparator() public view {
        bytes32 domainSeparator = sendJpyc.getDomainSeparator();
        assertEq(domainSeparator, jpycToken.DOMAIN_SEPARATOR());
    }

    function test_GetStatistics() public {
        // Execute a permit transfer
        uint deadline = block.timestamp + 1 hours;
        uint nonce = jpycToken.nonces(USER_A);

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, USER_A, address(sendJpyc), TRANSFER_AMOUNT, nonce, deadline)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        vm.prank(OPERATOR);
        sendJpyc.sendWithPermit(USER_A, RECIPIENT, TRANSFER_AMOUNT, deadline, v, r, s);

        // Execute an auth transfer
        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 authNonce = keccak256(abi.encodePacked(USER_B, block.timestamp));

        bytes32 authStructHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                USER_B,
                RECIPIENT,
                TRANSFER_AMOUNT,
                validAfter,
                validBefore,
                authNonce
            )
        );
        bytes32 authDigest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), authStructHash));
        (uint8 v2, bytes32 r2, bytes32 s2) = vm.sign(USER_B_PRIVATE_KEY, authDigest);

        vm.prank(OPERATOR);
        sendJpyc.sendWithAuthorization(
            USER_B, RECIPIENT, TRANSFER_AMOUNT, validAfter, validBefore, authNonce, v2, r2, s2
        );

        // Check statistics
        (uint permitTransfers, uint authTransfers, uint permitAmount, uint authAmount) =
            sendJpyc.getStatistics();

        assertEq(permitTransfers, 1);
        assertEq(authTransfers, 1);
        assertEq(permitAmount, TRANSFER_AMOUNT);
        assertEq(authAmount, TRANSFER_AMOUNT);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ROLE MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GrantOperatorRole() public {
        address newOperator = address(0x999);
        bytes32 operatorRole = sendJpyc.OPERATOR_ROLE();

        vm.prank(DEFAULT_ADMIN);
        sendJpyc.grantRole(operatorRole, newOperator);

        assertTrue(sendJpyc.hasRole(operatorRole, newOperator));
    }

    function test_RevokeOperatorRole() public {
        bytes32 operatorRole = sendJpyc.OPERATOR_ROLE();

        vm.prank(DEFAULT_ADMIN);
        sendJpyc.revokeRole(operatorRole, OPERATOR);

        assertFalse(sendJpyc.hasRole(operatorRole, OPERATOR));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            UUPS UPGRADE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_UpgradeToNewImplementation() public {
        SendJPYC newImpl = new SendJPYC();

        vm.prank(DEFAULT_ADMIN);
        sendJpyc.upgradeToAndCall(address(newImpl), "");
    }

    function test_UpgradeRevertsWithoutAdminRole() public {
        SendJPYC newImpl = new SendJPYC();

        vm.prank(USER_A);
        vm.expectRevert();
        sendJpyc.upgradeToAndCall(address(newImpl), "");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            FUZZ TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testFuzz_SendWithPermit(uint amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);

        uint deadline = block.timestamp + 1 hours;
        uint nonce = jpycToken.nonces(USER_A);

        bytes32 structHash = keccak256(
            abi.encode(PERMIT_TYPEHASH, USER_A, address(sendJpyc), amount, nonce, deadline)
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        uint recipientBalanceBefore = jpycToken.balanceOf(RECIPIENT);

        vm.prank(OPERATOR);
        sendJpyc.sendWithPermit(USER_A, RECIPIENT, amount, deadline, v, r, s);

        assertEq(jpycToken.balanceOf(RECIPIENT), recipientBalanceBefore + amount);
    }

    function testFuzz_SendWithAuthorization(uint amount) public {
        amount = bound(amount, 1, INITIAL_SUPPLY);

        uint validAfter = block.timestamp - 1;
        uint validBefore = block.timestamp + 1 hours;
        bytes32 nonce = keccak256(abi.encodePacked(USER_A, block.timestamp, amount));

        bytes32 structHash = keccak256(
            abi.encode(
                TRANSFER_WITH_AUTHORIZATION_TYPEHASH,
                USER_A,
                RECIPIENT,
                amount,
                validAfter,
                validBefore,
                nonce
            )
        );
        bytes32 digest =
            keccak256(abi.encodePacked("\x19\x01", jpycToken.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(USER_A_PRIVATE_KEY, digest);

        uint recipientBalanceBefore = jpycToken.balanceOf(RECIPIENT);

        vm.prank(OPERATOR);
        sendJpyc.sendWithAuthorization(
            USER_A, RECIPIENT, amount, validAfter, validBefore, nonce, v, r, s
        );

        assertEq(jpycToken.balanceOf(RECIPIENT), recipientBalanceBefore + amount);
    }
}
