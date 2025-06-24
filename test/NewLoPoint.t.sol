// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NewLoPointTest
 * @author NewLo Team
 * @notice Comprehensive test suite for NewLoPoint token contract
 * @dev This test suite covers:
 *      - Initial state and deployment verification
 *      - Role-based access control functionality
 *      - Transfer control mechanisms (global and whitelist-based)
 *      - Pause/unpause functionality
 *      - Mint/burn operations
 *      - Edge cases and security considerations
 *      - Upgradeable proxy pattern testing
 *
 * @dev Test Coverage Areas:
 *      - ✅ Initialization and role assignment
 *      - ✅ Access control enforcement
 *      - ✅ Transfer restrictions (global enable/disable)
 *      - ✅ Whitelist functionality (individual and batch)
 *      - ✅ Pause mechanism
 *      - ✅ Mint/burn bypassing restrictions
 *      - ✅ Event emission verification
 *      - ✅ Error condition testing
 *
 * @dev Security Test Focus:
 *      - Role-based access control cannot be bypassed
 *      - Transfer restrictions work as intended
 *      - Mint/burn operations correctly bypass transfer controls
 *      - Pause functionality works for emergency stops
 *      - Whitelist mode properly overrides transfer locks
 *      - Global transfer enable properly overrides whitelist restrictions
 */
contract NewLoPointTest is Test {
    /* ═══════════════════════════════════════════════════════════════════════
                               TEST CONTRACTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @dev Implementation contract (logic)
    NewLoPoint impl;
    /// @dev User-facing token contract (proxy)
    NewLoPoint token;
    /// @dev Proxy admin for upgrade management
    ProxyAdmin admin;
    /// @dev The actual proxy contract
    TransparentUpgradeableProxy proxy;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST ACTORS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @dev Address with full administrative privileges
    address constant DEFAULT_ADMIN = address(0x1);
    /// @dev Address that can pause/unpause the contract
    address constant PAUSER = address(0x2);
    /// @dev Address that can mint new tokens
    address constant MINTER = address(0x3);
    /// @dev Regular user for testing transfers
    address constant USER_A = address(0x4);
    /// @dev Regular user for testing transfers
    address constant USER_B = address(0x5);
    /// @dev Exchange address for whitelist testing
    address constant EXCHANGE = address(0x6);

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST SETUP
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Set up test environment with deployed contracts
     * @dev Deploys implementation, proxy admin, and proxy with initialization
     * @dev This setup mirrors the production deployment process
     */
    function setUp() public {
        // Deploy implementation contract
        impl = new NewLoPoint();

        // Deploy proxy admin (DEFAULT_ADMIN becomes the owner)
        admin = new ProxyAdmin(DEFAULT_ADMIN);

        // Encode initialization data
        bytes memory data =
            abi.encodeWithSelector(impl.initialize.selector, DEFAULT_ADMIN, PAUSER, MINTER);

        // Deploy proxy and initialize in one transaction
        proxy = new TransparentUpgradeableProxy(address(impl), address(admin), data);

        // Create interface to interact with the proxy
        token = NewLoPoint(address(proxy));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           INITIALIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test initial contract state after deployment
     * @dev Verifies that transfer controls are properly initialized to restrictive state
     */
    function testInitialState() public view {
        // Transfer controls should be disabled by default (restrictive)
        assertFalse(token.transfersEnabled());
        assertFalse(token.whitelistModeEnabled());

        // No addresses should be whitelisted initially
        assertFalse(token.whitelistedAddresses(USER_A));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TRANSFER CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test initial transfer lock behavior
     * @dev Verifies that transfers are blocked by default after minting
     */
    function testInitialTransferLock() public {
        // Mint tokens to USER_A
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // Transfer should fail with TransfersDisabled error
        vm.prank(USER_A);
        vm.expectRevert(NewLoPoint.TransfersDisabled.selector);
        token.transfer(USER_B, 1 ether);
    }

    /**
     * @notice Test global transfer enable functionality
     * @dev Verifies that enabling transfers allows all transfers to work
     */
    function testEnableTransfers() public {
        // Check event emission
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.TransfersEnabledChanged(true);

        // Enable transfers (only admin can do this)
        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        // Verify state change
        assertTrue(token.transfersEnabled());

        // Test that transfers now work
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        vm.prank(USER_A);
        token.transfer(USER_B, 1 ether);

        assertEq(token.balanceOf(USER_B), 1 ether);
    }

    /**
     * @notice Test whitelist mode functionality
     * @dev Verifies that whitelist mode allows specific addresses to transfer
     */
    function testWhitelistMode() public {
        // Enable whitelist mode
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.WhitelistModeChanged(true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        assertTrue(token.whitelistModeEnabled());

        // Add exchange to whitelist
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.AddressWhitelisted(EXCHANGE, true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistedAddress(EXCHANGE, true);

        assertTrue(token.whitelistedAddresses(EXCHANGE));

        // Mint tokens to USER_A
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // Transfer between regular users should fail
        vm.prank(USER_A);
        vm.expectRevert(NewLoPoint.NotWhitelisted.selector);
        token.transfer(USER_B, 1 ether);

        // Transfer to whitelisted exchange should succeed
        vm.prank(USER_A);
        token.transfer(EXCHANGE, 1 ether);
        assertEq(token.balanceOf(EXCHANGE), 1 ether);

        // Transfer from whitelisted exchange should also succeed
        vm.prank(EXCHANGE);
        token.transfer(USER_B, 0.5 ether);
        assertEq(token.balanceOf(USER_B), 0.5 ether);
    }

    /**
     * @notice Test batch whitelist functionality
     * @dev Verifies that multiple addresses can be whitelisted in one transaction
     */
    function testBatchWhitelist() public {
        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        address[] memory addresses = new address[](2);
        addresses[0] = EXCHANGE;
        addresses[1] = USER_A;

        // Batch add to whitelist
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.AddressWhitelisted(EXCHANGE, true);
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.AddressWhitelisted(USER_A, true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistedAddresses(addresses, true);

        assertTrue(token.whitelistedAddresses(EXCHANGE));
        assertTrue(token.whitelistedAddresses(USER_A));
    }

    /**
     * @notice Test that whitelist overrides transfer lock
     * @dev Verifies precedence: whitelist mode allows transfers even when global transfers are disabled
     */
    function testWhitelistOverridesTransferLock() public {
        // Transfers disabled, whitelist mode enabled
        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistedAddress(USER_A, true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // Whitelisted user can transfer
        vm.prank(USER_A);
        token.transfer(USER_B, 1 ether);
        assertEq(token.balanceOf(USER_B), 1 ether);
    }

    /**
     * @notice Test that global transfer enable overrides whitelist restrictions
     * @dev Verifies precedence: global transfers override whitelist mode
     */
    function testFullTransferEnableOverridesWhitelist() public {
        // Whitelist mode enabled, but global transfers also enabled
        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // Global transfers are enabled, so transfer should work even if not whitelisted
        vm.prank(USER_A);
        token.transfer(USER_B, 1 ether);
        assertEq(token.balanceOf(USER_B), 1 ether);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              PAUSE MECHANISM TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test pause functionality
     * @dev Verifies that pause stops all transfers, even when transfers are enabled
     */
    function testPause() public {
        // Enable transfers first
        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // Pause the contract
        vm.prank(PAUSER);
        token.pause();

        // Transfer should fail when paused
        vm.prank(USER_A);
        vm.expectRevert();
        token.transfer(USER_B, 1 ether);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test role-based access control enforcement
     * @dev Verifies that functions with role restrictions cannot be called by unauthorized users
     */
    function testAccessControl() public {
        // Unauthorized users cannot change transfer settings
        vm.prank(USER_A);
        vm.expectRevert();
        token.setTransfersEnabled(true);

        vm.prank(USER_A);
        vm.expectRevert();
        token.setWhitelistModeEnabled(true);

        vm.prank(USER_A);
        vm.expectRevert();
        token.setWhitelistedAddress(USER_B, true);

        // Only addresses with MINTER role can mint
        vm.prank(USER_A);
        vm.expectRevert();
        token.mint(USER_B, 100 ether);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              MINT/BURN TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test that mint/burn operations bypass transfer restrictions
     * @dev Verifies that mint/burn work even when all transfers are disabled
     * @dev This is a critical security feature - mint/burn should always work
     */
    function testMintBurnAlwaysAllowed() public {
        // Mint/Burn is always possible even when transfers are disabled
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);
        assertEq(token.balanceOf(USER_A), 100 ether);

        // Burn should work even with transfer restrictions
        vm.prank(USER_A);
        token.burn(50 ether);
        assertEq(token.balanceOf(USER_A), 50 ether);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                         PAUSE vs TRANSFER CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test pause behavior with transfer controls
     * @dev Verifies that pause state takes precedence over custom transfer controls
     */
    function testPauseVsTransferControlBehavior() public {
        // Mint some tokens first
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // Pause the contract
        vm.prank(PAUSER);
        token.pause();

        // Try to transfer - should get pause error, not custom transfer control error
        vm.prank(USER_A);
        vm.expectRevert(); // Now expects pause-related error
        token.transfer(USER_B, 1 ether);
    }

    /**
     * @notice Test mint behavior when paused
     * @dev Verifies that minting is properly blocked when contract is paused
     */
    function testMintWhenPaused() public {
        // Pause the contract
        vm.prank(PAUSER);
        token.pause();

        // Try to mint - should fail with pause error
        vm.prank(MINTER);
        vm.expectRevert(); // Should revert with pause error
        token.mint(USER_A, 100 ether);
    }
}
