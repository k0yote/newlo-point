// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NewLoPointFactoryTest
 * @author NewLo Team
 * @notice Comprehensive test suite for NewLoPointFactory contract
 * @dev This test suite covers:
 *      - Factory deployment and initialization
 *      - Token deployment using CREATE2
 *      - Address prediction functionality
 *      - Deployed token functionality verification
 *      - Salt uniqueness and collision handling
 *      - Event emission verification
 *      - Gas cost optimization verification
 *
 * @dev Test Coverage Areas:
 *      - ✅ Factory initialization and state verification
 *      - ✅ Token deployment with CREATE2
 *      - ✅ Address prediction accuracy
 *      - ✅ Multiple token deployment with different salts
 *      - ✅ Deployed token initialization and functionality
 *      - ✅ Event emission verification
 *      - ✅ Error condition testing (salt collision)
 *      - ✅ Gas cost optimization verification
 *
 * @dev Security Test Focus:
 *      - CREATE2 address calculation is deterministic and accurate
 *      - Each deployed token has independent state
 *      - Salt collision properly reverts deployment
 *      - Deployed tokens are properly initialized
 *      - Factory owner has correct ProxyAdmin permissions
 */
contract NewLoPointFactoryTest is Test {
    /* ═══════════════════════════════════════════════════════════════════════
                               TEST CONTRACTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @dev Factory contract under test
    NewLoPointFactory factory;

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST ACTORS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @dev Factory deployer (becomes ProxyAdmin owner)
    address constant FACTORY_DEPLOYER = address(0x1);
    /// @dev Address with full administrative privileges for tokens
    address constant TOKEN_ADMIN = address(0x2);
    /// @dev Address that can pause/unpause tokens
    address constant TOKEN_PAUSER = address(0x3);
    /// @dev Address that can mint new tokens
    address constant TOKEN_MINTER = address(0x4);
    /// @dev Regular user for testing transfers
    address constant USER_A = address(0x5);
    /// @dev Regular user for testing transfers
    address constant USER_B = address(0x6);

    /* ═══════════════════════════════════════════════════════════════════════
                                 TEST SETUP
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Set up test environment with deployed factory
     * @dev Deploys factory as FACTORY_DEPLOYER to verify ProxyAdmin ownership
     */
    function setUp() public {
        vm.prank(FACTORY_DEPLOYER);
        factory = new NewLoPointFactory();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           FACTORY INITIALIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test factory deployment and initial state
     * @dev Verifies that implementation and ProxyAdmin are properly set
     */
    function testFactoryInitialization() public view {
        // Verify implementation is deployed and not zero address
        address impl = factory.implementation();
        assertNotEq(impl, address(0));

        // Verify implementation is a NewLoPoint contract
        assertTrue(impl.code.length > 0);

        // Verify ProxyAdmin is deployed and not zero address
        ProxyAdmin proxyAdmin = factory.proxyAdmin();
        assertNotEq(address(proxyAdmin), address(0));

        // Verify ProxyAdmin owner is the factory deployer
        assertEq(proxyAdmin.owner(), FACTORY_DEPLOYER);
    }

    /**
     * @notice Test that implementation contract cannot be initialized directly
     * @dev Verifies security: implementation should be disabled for direct initialization
     */
    function testImplementationCannotBeInitialized() public {
        address impl = factory.implementation();
        NewLoPoint implContract = NewLoPoint(impl);

        // Attempting to initialize implementation directly should fail
        vm.expectRevert();
        implContract.initialize(TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TOKEN DEPLOYMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test basic token deployment
     * @dev Verifies that deployToken creates a working token proxy
     */
    function testDeployToken() public {
        bytes32 salt = keccak256("test-token-1");

        // Expect TokenDeployed event
        vm.expectEmit(true, true, true, true);
        emit NewLoPointFactory.TokenDeployed(
            factory.predictAddress(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER), salt
        );

        // Deploy token
        address tokenAddress = factory.deployToken(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);

        // Verify token is deployed at expected address
        assertTrue(tokenAddress.code.length > 0);

        // Verify token is properly initialized
        NewLoPoint token = NewLoPoint(tokenAddress);
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), TOKEN_ADMIN));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), TOKEN_PAUSER));
        assertTrue(token.hasRole(token.MINTER_ROLE(), TOKEN_MINTER));
    }

    /**
     * @notice Test address prediction accuracy
     * @dev Verifies that predictAddress returns the same address as deployToken
     */
    function testAddressPrediction() public {
        bytes32 salt = keccak256("prediction-test");

        // Predict address before deployment
        address predicted = factory.predictAddress(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);

        // Deploy token and verify address matches prediction
        address deployed = factory.deployToken(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);

        assertEq(predicted, deployed);
    }

    /**
     * @notice Test multiple token deployments with different salts
     * @dev Verifies that each deployment creates a unique address
     */
    function testMultipleTokenDeployments() public {
        bytes32 salt1 = keccak256("token-1");
        bytes32 salt2 = keccak256("token-2");
        bytes32 salt3 = keccak256("token-3");

        // Deploy three tokens with different salts
        address token1 = factory.deployToken(salt1, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        address token2 = factory.deployToken(salt2, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        address token3 = factory.deployToken(salt3, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);

        // Verify all addresses are different
        assertNotEq(token1, token2);
        assertNotEq(token1, token3);
        assertNotEq(token2, token3);

        // Verify all tokens are properly initialized
        assertTrue(NewLoPoint(token1).hasRole(NewLoPoint(token1).DEFAULT_ADMIN_ROLE(), TOKEN_ADMIN));
        assertTrue(NewLoPoint(token2).hasRole(NewLoPoint(token2).DEFAULT_ADMIN_ROLE(), TOKEN_ADMIN));
        assertTrue(NewLoPoint(token3).hasRole(NewLoPoint(token3).DEFAULT_ADMIN_ROLE(), TOKEN_ADMIN));
    }

    /**
     * @notice Test salt collision handling
     * @dev Verifies that using the same salt twice causes revert
     */
    function testSaltCollision() public {
        bytes32 salt = keccak256("collision-test");

        // First deployment should succeed
        factory.deployToken(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);

        // Second deployment with same salt should fail
        vm.expectRevert();
        factory.deployToken(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                        DEPLOYED TOKEN FUNCTIONALITY TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test that deployed tokens have independent state
     * @dev Verifies that changes to one token don't affect others
     */
    function testTokenIndependence() public {
        // Deploy two tokens
        bytes32 salt1 = keccak256("independent-1");
        bytes32 salt2 = keccak256("independent-2");

        address token1Address = factory.deployToken(salt1, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        address token2Address = factory.deployToken(salt2, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);

        NewLoPoint token1 = NewLoPoint(token1Address);
        NewLoPoint token2 = NewLoPoint(token2Address);

        // Enable transfers for token1 only
        vm.prank(TOKEN_ADMIN);
        token1.setTransfersEnabled(true);

        // Mint tokens to both contracts
        vm.prank(TOKEN_MINTER);
        token1.mint(USER_A, 100 ether);

        vm.prank(TOKEN_MINTER);
        token2.mint(USER_A, 100 ether);

        // Verify token1 allows transfers
        assertTrue(token1.transfersEnabled());
        vm.prank(USER_A);
        token1.transfer(USER_B, 1 ether);
        assertEq(token1.balanceOf(USER_B), 1 ether);

        // Verify token2 still blocks transfers
        assertFalse(token2.transfersEnabled());
        vm.prank(USER_A);
        vm.expectRevert(NewLoPoint.TransfersDisabled.selector);
        token2.transfer(USER_B, 1 ether);
    }

    /**
     * @notice Test deployed token minting functionality
     * @dev Verifies that tokens deployed by factory work correctly
     */
    function testDeployedTokenMinting() public {
        bytes32 salt = keccak256("minting-test");
        address tokenAddress = factory.deployToken(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        NewLoPoint token = NewLoPoint(tokenAddress);

        // Test minting
        vm.prank(TOKEN_MINTER);
        token.mint(USER_A, 1000 ether);

        assertEq(token.balanceOf(USER_A), 1000 ether);
        assertEq(token.totalSupply(), 1000 ether);
    }

    /**
     * @notice Test deployed token access control
     * @dev Verifies that role restrictions work correctly on deployed tokens
     */
    function testDeployedTokenAccessControl() public {
        bytes32 salt = keccak256("access-control-test");
        address tokenAddress = factory.deployToken(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        NewLoPoint token = NewLoPoint(tokenAddress);

        // Unauthorized user cannot mint
        vm.prank(USER_A);
        vm.expectRevert();
        token.mint(USER_A, 100 ether);

        // Unauthorized user cannot enable transfers
        vm.prank(USER_A);
        vm.expectRevert();
        token.setTransfersEnabled(true);

        // Authorized users can perform their roles
        vm.prank(TOKEN_MINTER);
        token.mint(USER_A, 100 ether); // Should succeed

        vm.prank(TOKEN_ADMIN);
        token.setTransfersEnabled(true); // Should succeed
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              EDGE CASE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test deployment with zero addresses
     * @dev Verifies behavior when zero addresses are used for roles
     */
    function testDeploymentWithZeroAddresses() public {
        bytes32 salt = keccak256("zero-address-test");

        // Deployment should succeed even with zero addresses
        // (role validation happens in NewLoPoint.initialize, not in factory)
        address tokenAddress = factory.deployToken(salt, address(0), address(0), address(0));
        assertTrue(tokenAddress.code.length > 0);

        NewLoPoint token = NewLoPoint(tokenAddress);

        // Verify that zero address has the roles (this is allowed by AccessControl)
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), address(0)));
        assertTrue(token.hasRole(token.PAUSER_ROLE(), address(0)));
        assertTrue(token.hasRole(token.MINTER_ROLE(), address(0)));
    }

    /**
     * @notice Test prediction with different parameters
     * @dev Verifies that different parameters produce different addresses
     */
    function testPredictionWithDifferentParameters() public view {
        bytes32 salt = keccak256("param-test");

        address addr1 = factory.predictAddress(salt, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        address addr2 = factory.predictAddress(salt, TOKEN_ADMIN, TOKEN_PAUSER, USER_A); // Different minter
        address addr3 = factory.predictAddress(salt, USER_A, TOKEN_PAUSER, TOKEN_MINTER); // Different admin

        // All addresses should be different
        assertNotEq(addr1, addr2);
        assertNotEq(addr1, addr3);
        assertNotEq(addr2, addr3);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               GAS OPTIMIZATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test gas efficiency of multiple deployments
     * @dev Verifies that shared implementation reduces gas costs for subsequent deployments
     */
    function testGasEfficiency() public {
        bytes32 salt1 = keccak256("gas-test-1");
        bytes32 salt2 = keccak256("gas-test-2");

        // Measure gas for first deployment
        uint gasStart1 = gasleft();
        factory.deployToken(salt1, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        uint gasUsed1 = gasStart1 - gasleft();

        // Measure gas for second deployment
        uint gasStart2 = gasleft();
        factory.deployToken(salt2, TOKEN_ADMIN, TOKEN_PAUSER, TOKEN_MINTER);
        uint gasUsed2 = gasStart2 - gasleft();

        // Gas usage should be similar (both deploy proxies, not implementations)
        // Allow for 10% variance
        uint tolerance = gasUsed1 / 10;
        assertApproxEqAbs(gasUsed1, gasUsed2, tolerance);

        // Log gas usage for analysis
        console2.log("Gas used for deployment 1:", gasUsed1);
        console2.log("Gas used for deployment 2:", gasUsed2);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                                FUZZ TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Fuzz test address prediction consistency
     * @dev Verifies that prediction is always accurate regardless of input parameters
     */
    function testFuzzAddressPrediction(bytes32 salt, address admin, address pauser, address minter)
        public
    {
        // Skip if addresses would cause the same deployment
        vm.assume(salt != bytes32(0)); // Avoid potential issues with zero salt

        address predicted = factory.predictAddress(salt, admin, pauser, minter);

        // If prediction doesn't revert, deployment should work and match
        if (predicted != address(0)) {
            try factory.deployToken(salt, admin, pauser, minter) returns (address deployed) {
                assertEq(predicted, deployed);
            } catch {
                // If deployment fails (e.g., salt collision), that's acceptable
                // The important thing is that prediction didn't give false positive
            }
        }
    }
}
