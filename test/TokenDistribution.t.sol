// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, console } from "forge-std/Test.sol";
import { TokenDistribution } from "../src/TokenDistribution.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";

contract TokenDistributionTest is Test {
    TokenDistribution public distribution;
    NewLoPoint public nlpToken;
    NewLoPointFactory public factory;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");
    address public user3 = makeAddr("user3");

    uint constant BATCH_AMOUNT = 500 * 10 ** 18;

    function setUp() public {
        vm.startPrank(admin);

        factory = new NewLoPointFactory();
        bytes32 salt = keccak256("TEST_DISTRIBUTION_TOKEN");

        nlpToken = NewLoPoint(factory.deployToken(salt, admin, admin, admin));

        distribution = new TokenDistribution(address(nlpToken), admin);
        nlpToken.grantRole(nlpToken.MINTER_ROLE(), address(distribution));

        vm.stopPrank();
    }

    function test_InitialState() public view {
        assertEq(distribution.totalDistributed(), 0);
        assertEq(distribution.totalDistributions(), 0);
        assertFalse(distribution.antiDuplicateMode());
        assertEq(address(distribution.nlpToken()), address(nlpToken));
    }

    function test_DistributeEqual_Success() public {
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        vm.prank(admin);
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
        address[] memory recipients = new address[](3);
        recipients[0] = user1;
        recipients[1] = user2;
        recipients[2] = user3;

        uint[] memory amounts = new uint[](3);
        amounts[0] = 100 * 10 ** 18;
        amounts[1] = 200 * 10 ** 18;
        amounts[2] = 300 * 10 ** 18;

        vm.prank(admin);
        uint batchId = distribution.distributeVariable(recipients, amounts);

        assertEq(batchId, 1);
        assertEq(nlpToken.balanceOf(user1), amounts[0]);
        assertEq(nlpToken.balanceOf(user2), amounts[1]);
        assertEq(nlpToken.balanceOf(user3), amounts[2]);

        uint totalExpected = amounts[0] + amounts[1] + amounts[2];
        assertEq(distribution.totalDistributed(), totalExpected);
    }

    function test_AntiDuplicateMode_Enable() public {
        vm.prank(admin);
        distribution.setAntiDuplicateMode(true);
        assertTrue(distribution.antiDuplicateMode());
    }

    function test_AntiDuplicateMode_PreventsDuplicate() public {
        vm.prank(admin);
        distribution.setAntiDuplicateMode(true);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        // 最初の配布
        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        // 2回目の配布は失敗すべき
        vm.prank(admin);
        vm.expectRevert();
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_AntiDuplicateMode_AllowsAfterPeriod() public {
        vm.prank(admin);
        distribution.setAntiDuplicateMode(true);

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        // 24時間経過をシミュレート
        vm.warp(block.timestamp + 86401);

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        assertEq(nlpToken.balanceOf(user1), BATCH_AMOUNT * 2);
    }

    function test_RevertWhen_ZeroAmount() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TokenDistribution.ZeroAmount.selector, 0));
        distribution.distributeEqual(recipients, 0);
    }

    function test_RevertWhen_ZeroAddress() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = address(0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TokenDistribution.ZeroAddress.selector, 1));
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_RevertWhen_ArrayLengthMismatch() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        uint[] memory amounts = new uint[](1);
        amounts[0] = BATCH_AMOUNT;

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistribution.ArrayLengthMismatch.selector, 2, 1)
        );
        distribution.distributeVariable(recipients, amounts);
    }

    function test_RevertWhen_BatchSizeTooLarge() public {
        address[] memory recipients = new address[](501);
        for (uint i = 0; i < 501; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        vm.prank(admin);
        vm.expectRevert(
            abi.encodeWithSelector(TokenDistribution.InvalidBatchSize.selector, 501, 500)
        );
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_RevertWhen_EmptyArray() public {
        address[] memory recipients = new address[](0);

        vm.prank(admin);
        vm.expectRevert(abi.encodeWithSelector(TokenDistribution.InvalidBatchSize.selector, 0, 500));
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_RevertWhen_NotOwner() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(user1);
        vm.expectRevert();
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_Pause_PreventsDistribution() public {
        vm.prank(admin);
        distribution.pause();

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(admin);
        vm.expectRevert();
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_Unpause_AllowsDistribution() public {
        vm.prank(admin);
        distribution.pause();

        vm.prank(admin);
        distribution.unpause();

        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        assertEq(nlpToken.balanceOf(user1), BATCH_AMOUNT);
    }

    function test_GetDistributionStats() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        (
            uint totalDistributed,
            uint totalDistributions,
            uint todayDistributed,
            bool antiDuplicateEnabled
        ) = distribution.getDistributionStats();

        assertEq(totalDistributed, BATCH_AMOUNT * 2);
        assertEq(totalDistributions, 1);
        assertEq(todayDistributed, BATCH_AMOUNT * 2);
        assertFalse(antiDuplicateEnabled);
    }

    function test_GetUserDistributionInfo() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        (uint totalReceived, uint lastReceived, bool canReceiveToday) =
            distribution.getUserDistributionInfo(user1);

        assertEq(totalReceived, BATCH_AMOUNT);
        assertGt(lastReceived, 0);
        assertTrue(canReceiveToday);
    }

    function test_GetDailyDistribution() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        uint today = block.timestamp;
        uint dailyAmount = distribution.getDailyDistribution(today);
        assertEq(dailyAmount, BATCH_AMOUNT * 2);
    }

    function test_ResetStats() public {
        address[] memory recipients = new address[](1);
        recipients[0] = user1;

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);

        assertGt(distribution.totalDistributed(), 0);
        assertGt(distribution.totalDistributions(), 0);

        vm.prank(admin);
        distribution.resetStats();

        assertEq(distribution.totalDistributed(), 0);
        assertEq(distribution.totalDistributions(), 0);
    }

    function test_BulkDistributionEvent() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        vm.expectEmit(true, true, true, true);
        emit TokenDistribution.BulkDistribution(1, 2, BATCH_AMOUNT * 2, block.timestamp);

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_TokenDistributedEvents() public {
        address[] memory recipients = new address[](2);
        recipients[0] = user1;
        recipients[1] = user2;

        vm.expectEmit(true, true, true, true);
        emit TokenDistribution.TokenDistributed(user1, BATCH_AMOUNT, 1, block.timestamp);

        vm.expectEmit(true, true, true, true);
        emit TokenDistribution.TokenDistributed(user2, BATCH_AMOUNT, 1, block.timestamp);

        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
    }

    function test_AntiDuplicateModeChangedEvent() public {
        vm.expectEmit(true, true, true, true);
        emit TokenDistribution.AntiDuplicateModeChanged(true);

        vm.prank(admin);
        distribution.setAntiDuplicateMode(true);
    }

    function test_GasUsage_LargeBatch() public {
        address[] memory recipients = new address[](100);
        for (uint i = 0; i < 100; i++) {
            recipients[i] = makeAddr(string(abi.encodePacked("user", i)));
        }

        uint gasBefore = gasleft();
        vm.prank(admin);
        distribution.distributeEqual(recipients, BATCH_AMOUNT);
        uint gasUsed = gasBefore - gasleft();

        console.log("Gas used for 100 recipients:", gasUsed);
        assertLt(gasUsed, 30_000_000);
    }
}
