// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, console } from "forge-std/Test.sol";
import { TokenDistributionV2 } from "../src/TokenDistributionV2.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

contract TokenDistributionV2Test is Test {
    TokenDistributionV2 public distribution;
    NewLoPoint public nlpToken;
    NewLoPointFactory public factory;

    // Role-based addresses
    address public defaultAdmin = makeAddr("defaultAdmin");
    address public distributor = makeAddr("distributor");
    address public depositManager = makeAddr("depositManager");
    address public pauser = makeAddr("pauser");

    // User addresses
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");
    address public unauthorized = makeAddr("unauthorized");

    uint constant BATCH_AMOUNT = 500 * 10 ** 18;
    uint constant DEPOSIT_AMOUNT = 1000000 * 10 ** 18; // 1M tokens

    function setUp() public {
        vm.startPrank(defaultAdmin);

        // Deploy factory and token
        factory = new NewLoPointFactory();
        bytes32 salt = keccak256("TEST_DISTRIBUTION_V2_TOKEN");
        nlpToken = NewLoPoint(factory.deployToken(salt, defaultAdmin, defaultAdmin, defaultAdmin));

        // Deploy TokenDistributionV2
        distribution = new TokenDistributionV2(address(nlpToken), defaultAdmin);

        // Grant roles
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        distribution.grantRole(distribution.DEPOSIT_MANAGER_ROLE(), depositManager);
        distribution.grantRole(distribution.PAUSER_ROLE(), pauser);

        // Setup token for efficient distribution
        nlpToken.setWhitelistModeEnabled(true);
        nlpToken.setWhitelistedAddress(address(distribution), true);
        nlpToken.setWhitelistedAddress(depositManager, true); // Add depositManager to whitelist

        // Mint tokens to default admin for deposits
        nlpToken.mint(defaultAdmin, DEPOSIT_AMOUNT);

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ROLE MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_InitialRoles() public view {
        assertTrue(distribution.hasRole(distribution.DEFAULT_ADMIN_ROLE(), defaultAdmin));
        assertTrue(distribution.hasRole(distribution.DISTRIBUTOR_ROLE(), distributor));
        assertTrue(distribution.hasRole(distribution.DEPOSIT_MANAGER_ROLE(), depositManager));
        assertTrue(distribution.hasRole(distribution.PAUSER_ROLE(), pauser));
    }

    function test_RoleConstants() public view {
        bytes32 distributorRole = keccak256("DISTRIBUTOR_ROLE");
        bytes32 depositManagerRole = keccak256("DEPOSIT_MANAGER_ROLE");
        bytes32 pauserRole = keccak256("PAUSER_ROLE");

        assertEq(distribution.DISTRIBUTOR_ROLE(), distributorRole);
        assertEq(distribution.DEPOSIT_MANAGER_ROLE(), depositManagerRole);
        assertEq(distribution.PAUSER_ROLE(), pauserRole);
    }

    function test_GrantRole_OnlyAdmin() public {
        address newDistributor = makeAddr("newDistributor");

        // Verify newDistributor doesn't have the role initially
        assertFalse(distribution.hasRole(distribution.DISTRIBUTOR_ROLE(), newDistributor));

        // Verify defaultAdmin has DEFAULT_ADMIN_ROLE
        assertTrue(distribution.hasRole(distribution.DEFAULT_ADMIN_ROLE(), defaultAdmin));

        // Should succeed when called by admin
        vm.startPrank(defaultAdmin);
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), newDistributor);
        vm.stopPrank();

        // Verify the role was granted
        assertTrue(distribution.hasRole(distribution.DISTRIBUTOR_ROLE(), newDistributor));
    }

    function test_RevertWhen_UnauthorizedGrantRole() public {
        address newDistributor = makeAddr("newDistributor");

        // Verify unauthorized user doesn't have admin role
        assertFalse(distribution.hasRole(distribution.DEFAULT_ADMIN_ROLE(), unauthorized));

        // Try to grant role as unauthorized user - should revert
        vm.prank(unauthorized);
        try distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), newDistributor) {
            // If we reach here, the call succeeded when it should have failed
            assertTrue(false, "Expected revert but call succeeded");
        } catch {
            // This is expected - the call should revert
        }

        // Verify the role was not granted
        assertFalse(distribution.hasRole(distribution.DISTRIBUTOR_ROLE(), newDistributor));
    }

    function test_RevokeRole_OnlyAdmin() public {
        // Verify distributor has the role initially
        assertTrue(distribution.hasRole(distribution.DISTRIBUTOR_ROLE(), distributor));

        // Verify defaultAdmin has DEFAULT_ADMIN_ROLE
        assertTrue(distribution.hasRole(distribution.DEFAULT_ADMIN_ROLE(), defaultAdmin));

        // Should succeed when called by admin
        vm.startPrank(defaultAdmin);
        distribution.revokeRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        vm.stopPrank();

        // Verify the role was revoked
        assertFalse(distribution.hasRole(distribution.DISTRIBUTOR_ROLE(), distributor));
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            DEPOSIT MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DepositTokens_Success() public {
        uint depositAmount = 100000 * 10 ** 18;

        // Transfer tokens from defaultAdmin to depositManager first
        vm.prank(defaultAdmin);
        nlpToken.transfer(depositManager, depositAmount);

        vm.startPrank(depositManager);
        nlpToken.approve(address(distribution), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit TokenDistributionV2.TokensDeposited(depositManager, depositAmount, depositAmount);

        distribution.depositTokens(depositAmount);
        vm.stopPrank();

        assertEq(nlpToken.balanceOf(address(distribution)), depositAmount);
    }

    function test_RevertWhen_UnauthorizedDeposit() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.depositTokens(BATCH_AMOUNT);
    }

    function test_RevertWhen_ZeroDeposit() public {
        vm.prank(depositManager);
        vm.expectRevert("Amount must be greater than 0");
        distribution.depositTokens(0);
    }

    function test_EmergencyWithdraw_Success() public {
        // First deposit tokens
        _depositTokens(DEPOSIT_AMOUNT);

        uint withdrawAmount = 50000 * 10 ** 18;
        address recipient = makeAddr("recipient");

        vm.prank(depositManager);
        distribution.emergencyWithdraw(withdrawAmount, recipient);

        assertEq(nlpToken.balanceOf(recipient), withdrawAmount);
        assertEq(nlpToken.balanceOf(address(distribution)), DEPOSIT_AMOUNT - withdrawAmount);
    }

    function test_EmergencyWithdraw_FullBalance() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address recipient = makeAddr("recipient");

        vm.prank(depositManager);
        distribution.emergencyWithdraw(0, recipient); // 0 means full balance

        assertEq(nlpToken.balanceOf(recipient), DEPOSIT_AMOUNT);
        assertEq(nlpToken.balanceOf(address(distribution)), 0);
    }

    function test_RevertWhen_UnauthorizedWithdraw() public {
        _depositTokens(DEPOSIT_AMOUNT);

        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.emergencyWithdraw(BATCH_AMOUNT, user1);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            DISTRIBUTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_DistributeEqual_Success() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        vm.prank(distributor);
        uint batchId = distribution.distributeEqual(recipients, BATCH_AMOUNT);

        assertEq(batchId, 1);
        assertEq(nlpToken.balanceOf(user1), BATCH_AMOUNT);
        assertEq(nlpToken.balanceOf(user2), BATCH_AMOUNT);
        assertEq(nlpToken.balanceOf(user3), BATCH_AMOUNT);
        assertEq(distribution.totalDistributed(), BATCH_AMOUNT * 3);
        assertEq(distribution.totalDistributions(), 1);
        assertEq(distribution.userTotalReceived(user1), BATCH_AMOUNT);
    }

    function test_DistributeVariable_Success() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        uint[] memory amounts = new uint[](3);
        amounts[0] = 100 * 10 ** 18;
        amounts[1] = 200 * 10 ** 18;
        amounts[2] = 300 * 10 ** 18;

        vm.prank(distributor);
        uint batchId = distribution.distributeVariable(recipients, amounts);

        assertEq(batchId, 1);
        assertEq(nlpToken.balanceOf(user1), amounts[0]);
        assertEq(nlpToken.balanceOf(user2), amounts[1]);
        assertEq(nlpToken.balanceOf(user3), amounts[2]);

        uint totalExpected = amounts[0] + amounts[1] + amounts[2];
        assertEq(distribution.totalDistributed(), totalExpected);
    }

    function test_RevertWhen_UnauthorizedDistribution() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_RevertWhen_InsufficientBalance() public {
        // Don't deposit enough tokens
        _depositTokens(BATCH_AMOUNT); // Only deposit 500 tokens

        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributionV2.InsufficientContractBalance.selector,
                BATCH_AMOUNT * 3,
                BATCH_AMOUNT
            )
        );
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_LowBalanceWarning() public {
        uint lowAmount = 5000 * 10 ** 18; // Below LOW_BALANCE_THRESHOLD (10,000)
        _depositTokens(lowAmount);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        uint remainingAfterDistribution = lowAmount - BATCH_AMOUNT;

        // Expect the LowBalanceWarning event to be emitted
        vm.expectEmit(true, true, true, true);
        emit TokenDistributionV2.LowBalanceWarning(
            remainingAfterDistribution, distribution.LOW_BALANCE_THRESHOLD()
        );

        vm.prank(distributor);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          ANTI-DUPLICATE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SetAntiDuplicateMode_Success() public {
        vm.prank(defaultAdmin);
        distribution.setAntiDuplicateMode(true);

        assertTrue(distribution.antiDuplicateMode());
    }

    function test_RevertWhen_UnauthorizedSetAntiDuplicate() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.setAntiDuplicateMode(true);
    }

    function test_AntiDuplicateMode_PreventsDuplicate() public {
        _depositTokens(DEPOSIT_AMOUNT);

        vm.prank(defaultAdmin);
        distribution.setAntiDuplicateMode(true);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        // First distribution
        vm.prank(distributor);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        // Second distribution should fail
        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                TokenDistributionV2.DuplicateDistribution.selector, user1, block.timestamp
            )
        );
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_AntiDuplicateMode_AllowsAfterPeriod() public {
        _depositTokens(DEPOSIT_AMOUNT);

        vm.prank(defaultAdmin);
        distribution.setAntiDuplicateMode(true);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(distributor);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        // Simulate 24 hours + 1 second
        vm.warp(block.timestamp + 86401);

        vm.prank(distributor);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        assertEq(nlpToken.balanceOf(user1), BATCH_AMOUNT * 2);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              PAUSE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_Pause_Success() public {
        vm.prank(pauser);
        distribution.pause();

        assertTrue(distribution.paused());
    }

    function test_Unpause_Success() public {
        vm.prank(pauser);
        distribution.pause();

        vm.prank(pauser);
        distribution.unpause();

        assertFalse(distribution.paused());
    }

    function test_RevertWhen_UnauthorizedPause() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.pause();
    }

    function test_RevertWhen_UnauthorizedUnpause() public {
        vm.prank(pauser);
        distribution.pause();

        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.unpause();
    }

    function test_Pause_PreventsDistribution() public {
        _depositTokens(DEPOSIT_AMOUNT);

        vm.prank(pauser);
        distribution.pause();

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(distributor);
        vm.expectRevert();
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              SETUP TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_SetupForEfficientDistribution_Success() public {
        // Deploy new token for clean test since existing token already has whitelist enabled
        vm.startPrank(defaultAdmin);

        NewLoPointFactory newFactory = new NewLoPointFactory();
        bytes32 salt = keccak256("CLEAN_TEST_TOKEN");
        NewLoPoint newToken =
            NewLoPoint(newFactory.deployToken(salt, defaultAdmin, defaultAdmin, defaultAdmin));

        // Verify defaultAdmin has WHITELIST_MANAGER_ROLE on the new token
        assertTrue(
            newToken.hasRole(newToken.WHITELIST_MANAGER_ROLE(), defaultAdmin),
            "defaultAdmin should have WHITELIST_MANAGER_ROLE"
        );

        // Deploy new distribution contract
        TokenDistributionV2 newDistribution =
            new TokenDistributionV2(address(newToken), defaultAdmin);

        // Grant DEPOSIT_MANAGER_ROLE to defaultAdmin for testing
        newDistribution.grantRole(newDistribution.DEPOSIT_MANAGER_ROLE(), defaultAdmin);

        // Manual setup (what setupForEfficientDistribution would do)
        // 1. Enable whitelist mode
        newToken.setWhitelistModeEnabled(true);

        // 2. Add distribution contract to whitelist
        newToken.setWhitelistedAddress(address(newDistribution), true);

        // 3. Mint tokens and deposit
        newToken.mint(defaultAdmin, DEPOSIT_AMOUNT);
        newToken.approve(address(newDistribution), DEPOSIT_AMOUNT);
        newDistribution.depositTokens(DEPOSIT_AMOUNT);

        vm.stopPrank();

        // Verify setup
        assertTrue(newToken.whitelistModeEnabled());
        assertTrue(newToken.whitelistedAddresses(address(newDistribution)));
        assertEq(newToken.balanceOf(address(newDistribution)), DEPOSIT_AMOUNT);
    }

    function test_RevertWhen_UnauthorizedSetup() public {
        vm.prank(unauthorized);
        vm.expectRevert();
        distribution.setupForEfficientDistribution(0);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GetContractBalance() public {
        _depositTokens(DEPOSIT_AMOUNT);

        (uint balance, bool isLowBalance) = distribution.getContractBalance();

        assertEq(balance, DEPOSIT_AMOUNT);
        assertFalse(isLowBalance); // DEPOSIT_AMOUNT > LOW_BALANCE_THRESHOLD
    }

    function test_GetContractBalance_LowBalance() public {
        uint lowAmount = 5000 * 10 ** 18; // Below threshold
        _depositTokens(lowAmount);

        (uint balance, bool isLowBalance) = distribution.getContractBalance();

        assertEq(balance, lowAmount);
        assertTrue(isLowBalance);
    }

    function test_GetMaxDistributableUsers() public {
        _depositTokens(DEPOSIT_AMOUNT);

        uint maxUsers = distribution.getMaxDistributableUsers(BATCH_AMOUNT);
        uint expectedMax = DEPOSIT_AMOUNT / BATCH_AMOUNT;
        if (expectedMax > 500) {
            expectedMax = 500; // Capped at MAX_BATCH_SIZE
        }

        assertEq(maxUsers, expectedMax);
    }

    function test_GetMaxDistributableUsers_ExceedsMaxBatch() public {
        uint largeDeposit = 1000000 * 10 ** 18; // Very large amount
        _depositTokens(largeDeposit);

        uint maxUsers = distribution.getMaxDistributableUsers(1 * 10 ** 18); // 1 token per user

        assertEq(maxUsers, 500); // Should be capped at MAX_BATCH_SIZE
    }

    function test_GetDistributionStats() public {
        _depositTokens(DEPOSIT_AMOUNT);

        // Perform a distribution
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        vm.prank(distributor);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        (
            uint totalDistributed,
            uint totalDistributions,
            uint todayDistributed,
            uint contractBalance,
            bool isLowBalance,
            bool isAntiDuplicateEnabled
        ) = distribution.getDistributionStats();

        assertEq(totalDistributed, BATCH_AMOUNT * 2);
        assertEq(totalDistributions, 1);
        assertEq(todayDistributed, BATCH_AMOUNT * 2);
        assertEq(contractBalance, DEPOSIT_AMOUNT - (BATCH_AMOUNT * 2));
        assertFalse(isLowBalance);
        assertFalse(isAntiDuplicateEnabled);
    }

    function test_GetUserDistributionInfo() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(distributor);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        (uint totalReceived, uint lastReceived, bool canReceiveToday) =
            distribution.getUserDistributionInfo(user1);

        assertEq(totalReceived, BATCH_AMOUNT);
        assertEq(lastReceived, block.timestamp);
        assertTrue(canReceiveToday); // Anti-duplicate mode is disabled
    }

    function test_CheckSetupStatus() public view {
        (
            bool isWhitelistModeEnabled,
            bool isContractWhitelisted,
            uint contractBalance,
            bool canDistribute
        ) = distribution.checkSetupStatus();

        assertTrue(isWhitelistModeEnabled);
        assertTrue(isContractWhitelisted);
        assertEq(contractBalance, 0); // No tokens deposited yet
        assertTrue(canDistribute); // Contract is whitelisted
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VALIDATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_RevertWhen_ZeroAmount() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSelector(TokenDistributionV2.ZeroAmount.selector, 0));
        distribution.distributeEqual(recipients, 0);
    }

    function test_RevertWhen_ZeroAddress() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = address(0);

        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSelector(TokenDistributionV2.ZeroAddress.selector, 1));
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_RevertWhen_ArrayLengthMismatch() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        uint[] memory amounts = new uint[](1);
        amounts[0] = BATCH_AMOUNT;

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributionV2.ArrayLengthMismatch.selector, 2, 1)
        );
        distribution.distributeVariable(recipients, amounts);
    }

    function test_RevertWhen_BatchSizeTooLarge() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](501);
        for (uint i = 0; i < 501; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributionV2.InvalidBatchSize.selector, 501, 500)
        );
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_RevertWhen_EmptyArray() public {
        _depositTokens(DEPOSIT_AMOUNT);

        address[] memory recipients = new address[](0);

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistributionV2.InvalidBatchSize.selector, 0, 500)
        );
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              HELPER FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    function _depositTokens(uint amount) internal {
        // Transfer tokens from defaultAdmin to depositManager first
        vm.prank(defaultAdmin);
        nlpToken.transfer(depositManager, amount);

        // Approve and deposit
        vm.startPrank(depositManager);
        nlpToken.approve(address(distribution), amount);
        distribution.depositTokens(amount);
        vm.stopPrank();
    }
}
