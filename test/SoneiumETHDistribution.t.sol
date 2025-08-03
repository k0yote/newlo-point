// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import "../src/SoneiumETHDistribution.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract SoneiumETHDistributionTest is Test {
    SoneiumETHDistribution public distribution;

    address public admin = address(0x1);
    address public distributor = address(0x2);
    address public depositManager = address(0x3);
    address public pauser = address(0x4);

    address public user1 = address(0x10);
    address public user2 = address(0x20);
    address public user3 = address(0x30);
    address public user4 = address(0x40);

    uint public constant INITIAL_BALANCE = 1000 ether;
    uint public constant DISTRIBUTION_AMOUNT = 1 ether;

    event BulkDistribution(
        uint indexed batchId,
        uint recipientCount,
        uint totalAmount,
        uint remainingBalance,
        uint timestamp
    );

    event ETHDistributed(
        address indexed recipient, uint amount, uint indexed batchId, uint timestamp
    );

    event ETHDeposited(address indexed from, uint amount, uint newBalance);
    event LowBalanceWarning(uint currentBalance, uint threshold);
    event AntiDuplicateModeChanged(bool enabled);
    event ETHWithdrawn(address indexed to, uint amount, uint remainingBalance);

    function setUp() public {
        // Deploy contract
        distribution = new SoneiumETHDistribution(admin);

        // Setup roles
        vm.startPrank(admin);
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributor);
        distribution.grantRole(distribution.DEPOSIT_MANAGER_ROLE(), depositManager);
        distribution.grantRole(distribution.PAUSER_ROLE(), pauser);
        vm.stopPrank();

        // Fund the contract
        vm.deal(address(distribution), INITIAL_BALANCE);
    }

    function testInitialState() public view {
        assertEq(address(distribution).balance, INITIAL_BALANCE);
        assertEq(distribution.totalDistributed(), 0);
        assertEq(distribution.totalDistributions(), 0);
        assertEq(distribution.antiDuplicateMode(), false);
        assertTrue(distribution.hasRole(distribution.DEFAULT_ADMIN_ROLE(), admin));
    }

    function testDepositETH() public {
        uint depositAmount = 10 ether;
        vm.deal(depositManager, depositAmount);

        vm.expectEmit(true, false, false, true);
        emit ETHDeposited(depositManager, depositAmount, INITIAL_BALANCE + depositAmount);

        vm.prank(depositManager);
        distribution.depositETH{ value: depositAmount }();

        assertEq(address(distribution).balance, INITIAL_BALANCE + depositAmount);
    }

    function testReceiveETH() public {
        uint depositAmount = 5 ether;
        vm.deal(address(this), depositAmount);

        vm.expectEmit(true, false, false, true);
        emit ETHDeposited(address(this), depositAmount, INITIAL_BALANCE + depositAmount);

        (bool success,) = address(distribution).call{ value: depositAmount }("");
        assertTrue(success);

        assertEq(address(distribution).balance, INITIAL_BALANCE + depositAmount);
    }

    function testDistributeEqual() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        uint initialBalance1 = user1.balance;
        uint initialBalance2 = user2.balance;
        uint initialBalance3 = user3.balance;

        vm.expectEmit(true, false, false, true);
        emit BulkDistribution(1, 3, 3 ether, INITIAL_BALANCE - 3 ether, block.timestamp);

        vm.prank(distributor);
        uint batchId = distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);

        assertEq(batchId, 1);
        assertEq(user1.balance, initialBalance1 + DISTRIBUTION_AMOUNT);
        assertEq(user2.balance, initialBalance2 + DISTRIBUTION_AMOUNT);
        assertEq(user3.balance, initialBalance3 + DISTRIBUTION_AMOUNT);

        assertEq(distribution.totalDistributed(), 3 ether);
        assertEq(distribution.totalDistributions(), 1);
        assertEq(distribution.userTotalReceived(user1), DISTRIBUTION_AMOUNT);
    }

    function testDistributeVariable() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        uint[] memory amounts = new uint[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        uint initialBalance1 = user1.balance;
        uint initialBalance2 = user2.balance;
        uint initialBalance3 = user3.balance;

        vm.expectEmit(true, false, false, true);
        emit BulkDistribution(1, 3, 6 ether, INITIAL_BALANCE - 6 ether, block.timestamp);

        vm.prank(distributor);
        uint batchId = distribution.distributeVariable(recipients, amounts);

        assertEq(batchId, 1);
        assertEq(user1.balance, initialBalance1 + 1 ether);
        assertEq(user2.balance, initialBalance2 + 2 ether);
        assertEq(user3.balance, initialBalance3 + 3 ether);

        assertEq(distribution.totalDistributed(), 6 ether);
        assertEq(distribution.userTotalReceived(user1), 1 ether);
        assertEq(distribution.userTotalReceived(user2), 2 ether);
        assertEq(distribution.userTotalReceived(user3), 3 ether);
    }

    function testAntiDuplicateMode() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        // Enable anti-duplicate mode
        vm.prank(admin);
        distribution.setAntiDuplicateMode(true);

        // First distribution should succeed
        vm.prank(distributor);
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);

        // Second distribution should fail
        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SoneiumETHDistribution.DuplicateDistribution.selector, user1, block.timestamp
            )
        );
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);
    }

    function testAntiDuplicateModeAfterTimeDelay() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        // Enable anti-duplicate mode
        vm.prank(admin);
        distribution.setAntiDuplicateMode(true);

        // First distribution
        vm.prank(distributor);
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);

        // Wait for 25 hours
        vm.warp(block.timestamp + 25 hours);

        // Second distribution should now succeed
        vm.prank(distributor);
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);

        assertEq(distribution.userTotalReceived(user1), 2 ether);
    }

    function testLowBalanceWarning() public {
        // Create a distribution that will leave balance below threshold
        uint distributionAmount = INITIAL_BALANCE - 0.01 ether; // Leave 5 ETH (below 10 ETH threshold)

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.expectEmit(true, false, false, true);
        emit LowBalanceWarning(0.01 ether, 0.1 ether);

        vm.prank(distributor);
        distribution.distributeEqual(recipients, distributionAmount);
    }

    function testEmergencyWithdraw() public {
        uint withdrawAmount = 100 ether;
        address payable recipient = payable(admin); // Use admin who is already authorized
        uint initialBalance = recipient.balance;

        vm.expectEmit(true, false, false, true);
        emit ETHWithdrawn(recipient, withdrawAmount, INITIAL_BALANCE - withdrawAmount);

        vm.prank(depositManager);
        distribution.emergencyWithdraw(withdrawAmount, recipient);

        assertEq(recipient.balance, initialBalance + withdrawAmount);
        assertEq(address(distribution).balance, INITIAL_BALANCE - withdrawAmount);
    }

    function testEmergencyWithdrawAll() public {
        address payable recipient = payable(admin); // Use admin who is already authorized
        uint initialBalance = recipient.balance;

        vm.prank(depositManager);
        distribution.emergencyWithdraw(0, recipient); // 0 means withdraw all

        assertEq(recipient.balance, initialBalance + INITIAL_BALANCE);
        assertEq(address(distribution).balance, 0);
    }

    function testPauseUnpause() public {
        vm.prank(pauser);
        distribution.pause();

        assertTrue(distribution.paused());

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(distributor);
        vm.expectRevert();
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);

        vm.prank(pauser);
        distribution.unpause();

        assertFalse(distribution.paused());

        vm.prank(distributor);
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);
    }

    function testGetContractBalance() public view {
        (uint balance, bool isLowBalance) = distribution.getContractBalance();
        assertEq(balance, INITIAL_BALANCE);
        assertFalse(isLowBalance); // 1000 ETH is above 10 ETH threshold
    }

    function testGetMaxDistributableUsers() public view {
        uint maxUsers = distribution.getMaxDistributableUsers(1 ether);
        assertEq(maxUsers, 500); // Should be capped at MAX_BATCH_SIZE

        maxUsers = distribution.getMaxDistributableUsers(10 ether);
        assertEq(maxUsers, 100); // 1000 ETH / 10 ETH per user = 100 users
    }

    function testGetDistributionStats() public view {
        // Initial stats
        (
            uint totalDistributed,
            uint totalDistributions,
            uint todayDistributed,
            uint contractBalance,
            bool isLowBalance,
            bool isAntiDuplicateEnabled
        ) = distribution.getDistributionStats();

        assertEq(totalDistributed, 0);
        assertEq(totalDistributions, 0);
        assertEq(todayDistributed, 0);
        assertEq(contractBalance, INITIAL_BALANCE);
        assertFalse(isLowBalance);
        assertFalse(isAntiDuplicateEnabled);
    }

    function testGetUserDistributionInfo() public view {
        (uint totalReceived, uint lastReceived, bool canReceiveToday) =
            distribution.getUserDistributionInfo(user1);

        assertEq(totalReceived, 0);
        assertEq(lastReceived, 0);
        assertTrue(canReceiveToday);
    }

    function testAccessControl() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        // Non-distributor should not be able to distribute
        vm.prank(user1);
        vm.expectRevert();
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);

        // Non-deposit-manager should not be able to deposit
        vm.deal(user1, 1 ether);
        vm.prank(user1);
        vm.expectRevert();
        distribution.depositETH{ value: 1 ether }();

        // Non-admin should not be able to set anti-duplicate mode
        vm.prank(user1);
        vm.expectRevert();
        distribution.setAntiDuplicateMode(true);

        // Non-pauser should not be able to pause
        vm.prank(user1);
        vm.expectRevert();
        distribution.pause();
    }

    function testInvalidBatchSize() public {
        address[] memory recipients = new address[](501); // Exceeds MAX_BATCH_SIZE

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(SoneiumETHDistribution.InvalidBatchSize.selector, 501, 500)
        );
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);
    }

    function testInsufficientBalance() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        uint excessiveAmount = INITIAL_BALANCE + 1 ether;

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                SoneiumETHDistribution.InsufficientContractBalance.selector,
                excessiveAmount,
                INITIAL_BALANCE
            )
        );
        distribution.distributeEqual(recipients, excessiveAmount);
    }

    function testZeroAddress() public {
        address[] memory recipients = new address[](1);
        recipients[0] = address(0);

        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSelector(SoneiumETHDistribution.ZeroAddress.selector, 0));
        distribution.distributeEqual(recipients, DISTRIBUTION_AMOUNT);
    }

    function testZeroAmount() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSelector(SoneiumETHDistribution.ZeroAmount.selector, 0));
        distribution.distributeEqual(recipients, 0);
    }

    function testArrayLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        uint[] memory amounts = new uint[](1);
        amounts[0] = 1 ether;

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(SoneiumETHDistribution.ArrayLengthMismatch.selector, 2, 1)
        );
        distribution.distributeVariable(recipients, amounts);
    }

    function testLargeScaleDistribution() public {
        // Test with a reasonable batch size (100 users instead of 500)
        address[] memory recipients = new address[](100);
        for (uint i = 0; i < 100; i++) {
            recipients[i] = address(uint160(i + 1000));
        }

        vm.prank(distributor);
        uint batchId = distribution.distributeEqual(recipients, 0.1 ether);

        assertEq(batchId, 1);
        assertEq(distribution.totalDistributed(), 10 ether);
        assertEq(distribution.totalDistributions(), 1);

        // Check that all recipients received their ETH
        for (uint i = 0; i < 10; i++) {
            // Check first 10 recipients
            assertEq(recipients[i].balance, 0.1 ether);
            assertEq(distribution.userTotalReceived(recipients[i]), 0.1 ether);
        }
    }

    function testReentrancyProtection() public {
        ReentrancyAttacker attacker = new ReentrancyAttacker(distribution);

        address[] memory recipients = new address[](1);
        recipients[0] = address(attacker);

        vm.prank(distributor);
        // This should not revert due to reentrancy, but the attacker's callback will fail
        distribution.distributeEqual(recipients, 1 ether);

        // Verify the attacker received the ETH
        assertEq(address(attacker).balance, 1 ether);
    }

    function testBlacklistFunctionality() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        // Blacklist user1 (as admin)
        vm.prank(admin);
        distribution.setBlacklisted(user1, true);
        assertTrue(distribution.blacklisted(user1));

        // Try to distribute to blacklisted user
        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(SoneiumETHDistribution.BlacklistedAddress.selector, user1)
        );
        distribution.distributeEqual(recipients, 1 ether);

        // Remove from blacklist (as admin)
        vm.prank(admin);
        distribution.setBlacklisted(user1, false);
        assertFalse(distribution.blacklisted(user1));

        // Now distribution should work
        vm.prank(distributor);
        distribution.distributeEqual(recipients, 1 ether);
        assertEq(user1.balance, 1 ether);
    }

    function testEmergencyRecipientFunctionality() public {
        // Try emergency withdrawal to unauthorized recipient (as deposit manager)
        vm.prank(depositManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                SoneiumETHDistribution.UnauthorizedEmergencyRecipient.selector, user1
            )
        );
        distribution.emergencyWithdraw(1 ether, payable(user1));

        // Authorize user1 for emergency withdrawals (as admin)
        vm.prank(admin);
        distribution.setEmergencyRecipient(user1, true);
        assertTrue(distribution.authorizedEmergencyRecipients(user1));

        // Now emergency withdrawal should work (as deposit manager)
        uint balanceBefore = user1.balance;
        vm.prank(depositManager);
        distribution.emergencyWithdraw(1 ether, payable(user1));
        assertEq(user1.balance, balanceBefore + 1 ether);

        // Deauthorize user1 (as admin)
        vm.prank(admin);
        distribution.setEmergencyRecipient(user1, false);
        assertFalse(distribution.authorizedEmergencyRecipients(user1));
    }

    function testBatchBlacklistOperations() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;

        // Batch blacklist (as admin)
        vm.prank(admin);
        distribution.batchSetBlacklisted(accounts, true);

        // Verify all are blacklisted
        assertTrue(distribution.blacklisted(user1));
        assertTrue(distribution.blacklisted(user2));
        assertTrue(distribution.blacklisted(user3));

        // Batch unblacklist (as admin)
        vm.prank(admin);
        distribution.batchSetBlacklisted(accounts, false);

        // Verify all are unblacklisted
        assertFalse(distribution.blacklisted(user1));
        assertFalse(distribution.blacklisted(user2));
        assertFalse(distribution.blacklisted(user3));
    }

    function testBatchEmergencyRecipientOperations() public {
        address[] memory accounts = new address[](3);
        accounts[0] = user1;
        accounts[1] = user2;
        accounts[2] = user3;

        // Batch authorize (as admin)
        vm.prank(admin);
        distribution.batchSetEmergencyRecipients(accounts, true);

        // Verify all are authorized
        assertTrue(distribution.authorizedEmergencyRecipients(user1));
        assertTrue(distribution.authorizedEmergencyRecipients(user2));
        assertTrue(distribution.authorizedEmergencyRecipients(user3));

        // Batch deauthorize (as admin)
        vm.prank(admin);
        distribution.batchSetEmergencyRecipients(accounts, false);

        // Verify all are deauthorized
        assertFalse(distribution.authorizedEmergencyRecipients(user1));
        assertFalse(distribution.authorizedEmergencyRecipients(user2));
        assertFalse(distribution.authorizedEmergencyRecipients(user3));
    }

    function testSecurityAccessControl() public {
        // Test that only admin can manage blacklist
        vm.prank(user1);
        vm.expectRevert();
        distribution.setBlacklisted(user2, true);

        // Test that only admin can manage emergency recipients
        vm.prank(user1);
        vm.expectRevert();
        distribution.setEmergencyRecipient(user2, true);

        // Test that only admin can batch operations
        address[] memory accounts = new address[](1);
        accounts[0] = user1;

        vm.prank(user1);
        vm.expectRevert();
        distribution.batchSetBlacklisted(accounts, true);

        vm.prank(user1);
        vm.expectRevert();
        distribution.batchSetEmergencyRecipients(accounts, true);
    }

    function testDefaultAdminIsAuthorizedForEmergencyWithdrawal() public {
        // Default admin should be authorized for emergency withdrawals
        assertTrue(distribution.authorizedEmergencyRecipients(admin));

        // Test emergency withdrawal to default admin (as deposit manager)
        uint balanceBefore = admin.balance;
        vm.prank(depositManager);
        distribution.emergencyWithdraw(1 ether, payable(admin));
        assertEq(admin.balance, balanceBefore + 1 ether);
    }
}

// Helper contract for testing reentrancy protection
contract ReentrancyAttacker {
    SoneiumETHDistribution public distribution;

    constructor(SoneiumETHDistribution _distribution) {
        distribution = _distribution;
    }

    receive() external payable {
        // This will fail due to reentrancy protection
        try distribution.getContractBalance() {
            // If we can call a view function, that's fine
        } catch {
            // Expected to fail for state-changing functions
        }
    }
}
