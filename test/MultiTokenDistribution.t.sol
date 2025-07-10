// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { MultiTokenDistribution } from "../src/MultiTokenDistribution.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(
        string memory name,
        string memory symbol,
        uint8 decimals_,
        uint256 initialSupply
    ) ERC20(name, symbol) {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint256 amount) external {
        _mint(to, amount);
    }
}

contract MultiTokenDistributionTest is Test {
    MultiTokenDistribution public distribution;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public usdt;

    address public owner = address(0x1);
    address public user1 = address(0x2);
    address public user2 = address(0x3);
    address public user3 = address(0x4);

    event TokenAdded(string indexed symbol, address indexed tokenAddress, uint8 decimals);
    event TokenStatusUpdated(string indexed symbol, bool isActive);
    event TokenDistributed(address indexed user, string indexed symbol, uint256 amount, uint256 timestamp);
    event BatchDistributionCompleted(string indexed symbol, uint256 totalAmount, uint256 userCount);
    event EmergencyWithdraw(address indexed to, string indexed symbol, uint256 amount);

    function setUp() public {
        // Deploy mock tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 1000 ether);
        usdc = new MockERC20("USD Coin", "USDC", 6, 1000000 * 10 ** 6);
        usdt = new MockERC20("Tether USD", "USDT", 6, 1000000 * 10 ** 6);

        // Deploy distribution contract
        vm.prank(owner);
        distribution = new MultiTokenDistribution(owner);

        // Fund the distribution contract
        weth.transfer(address(distribution), 100 ether);
        usdc.transfer(address(distribution), 100000 * 10 ** 6);
        usdt.transfer(address(distribution), 100000 * 10 ** 6);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TOKEN MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_addToken_Success() public {
        vm.prank(owner);
        
        vm.expectEmit(true, true, false, true);
        emit TokenAdded("WETH", address(weth), 18);
        
        distribution.addToken("WETH", address(weth), 18);

        (address tokenAddress, uint8 decimals, bool isActive, uint256 totalDistributed, uint256 totalUsers) = 
            distribution.supportedTokens("WETH");
        
        assertEq(tokenAddress, address(weth));
        assertEq(decimals, 18);
        assertTrue(isActive);
        assertEq(totalDistributed, 0);
        assertEq(totalUsers, 0);
    }

    function test_addToken_RevertIfNotOwner() public {
        vm.prank(user1);
        vm.expectRevert();
        distribution.addToken("WETH", address(weth), 18);
    }

    function test_addToken_RevertIfTokenAlreadyExists() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.TokenAlreadyExists.selector, "WETH"));
        distribution.addToken("WETH", address(weth), 18);
        vm.stopPrank();
    }

    function test_addToken_RevertIfInvalidAddress() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidTokenAddress.selector, address(0)));
        distribution.addToken("WETH", address(0), 18);
    }

    function test_addToken_RevertIfInvalidSymbol() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidSymbol.selector, ""));
        distribution.addToken("", address(weth), 18);
    }

    function test_setTokenStatus_Success() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        vm.expectEmit(true, false, false, true);
        emit TokenStatusUpdated("WETH", false);
        
        distribution.setTokenStatus("WETH", false);
        
        (, , bool isActive, ,) = distribution.supportedTokens("WETH");
        assertFalse(isActive);
        vm.stopPrank();
    }

    function test_setTokenStatus_RevertIfTokenNotSupported() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.TokenNotSupported.selector, "WETH"));
        distribution.setTokenStatus("WETH", false);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          DISTRIBUTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_distributeToken_Success() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        uint256 initialBalance = weth.balanceOf(user1);
        uint256 distributionAmount = 1 ether;
        
        vm.expectEmit(true, true, false, true);
        emit TokenDistributed(user1, "WETH", distributionAmount, block.timestamp);
        
        distribution.distributeToken("WETH", user1, distributionAmount);
        
        assertEq(weth.balanceOf(user1), initialBalance + distributionAmount);
        assertEq(distribution.userReceivedAmounts(user1, "WETH"), distributionAmount);
        assertEq(distribution.totalDistributions(), 1);
        assertEq(distribution.totalUsers(), 1);
        
        (, , , uint256 totalDistributed, uint256 totalUsers) = distribution.supportedTokens("WETH");
        assertEq(totalDistributed, distributionAmount);
        assertEq(totalUsers, 1);
        vm.stopPrank();
    }

    function test_distributeToken_RevertIfNotOwner() public {
        vm.prank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        vm.prank(user1);
        vm.expectRevert();
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    function test_distributeToken_RevertIfTokenNotSupported() public {
        vm.prank(owner);
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.TokenNotSupported.selector, "WETH"));
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    function test_distributeToken_RevertIfTokenNotActive() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        distribution.setTokenStatus("WETH", false);
        
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.TokenNotActive.selector, "WETH"));
        distribution.distributeToken("WETH", user1, 1 ether);
        vm.stopPrank();
    }

    function test_distributeToken_RevertIfInvalidUser() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidUser.selector, address(0)));
        distribution.distributeToken("WETH", address(0), 1 ether);
        vm.stopPrank();
    }

    function test_distributeToken_RevertIfInvalidAmount() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidAmount.selector, 0));
        distribution.distributeToken("WETH", user1, 0);
        vm.stopPrank();
    }

    function test_distributeToken_RevertIfInsufficientBalance() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        uint256 contractBalance = weth.balanceOf(address(distribution));
        uint256 excessiveAmount = contractBalance + 1 ether;
        
        vm.expectRevert(abi.encodeWithSelector(
            MultiTokenDistribution.InsufficientBalance.selector, 
            "WETH", 
            excessiveAmount, 
            contractBalance
        ));
        distribution.distributeToken("WETH", user1, excessiveAmount);
        vm.stopPrank();
    }

    function test_batchDistributeToken_Success() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        
        uint256 totalAmount = 6 ether;
        
        vm.expectEmit(true, false, false, true);
        emit BatchDistributionCompleted("WETH", totalAmount, 3);
        
        distribution.batchDistributeToken("WETH", users, amounts);
        
        assertEq(weth.balanceOf(user1), 1 ether);
        assertEq(weth.balanceOf(user2), 2 ether);
        assertEq(weth.balanceOf(user3), 3 ether);
        assertEq(distribution.totalDistributions(), 3);
        assertEq(distribution.totalUsers(), 3);
        
        (, , , uint256 totalDistributed, uint256 totalUsers) = distribution.supportedTokens("WETH");
        assertEq(totalDistributed, totalAmount);
        assertEq(totalUsers, 3);
        vm.stopPrank();
    }

    function test_batchDistributeToken_RevertIfInvalidArrayLength() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;
        
        uint256[] memory amounts = new uint256[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;
        
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidArrayLength.selector, 2, 3));
        distribution.batchDistributeToken("WETH", users, amounts);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           EMERGENCY FUNCTIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_emergencyWithdraw_Success() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        uint256 withdrawAmount = 10 ether;
        uint256 initialBalance = weth.balanceOf(owner);
        
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(owner, "WETH", withdrawAmount);
        
        distribution.emergencyWithdraw("WETH", owner, withdrawAmount);
        
        assertEq(weth.balanceOf(owner), initialBalance + withdrawAmount);
        vm.stopPrank();
    }

    function test_emergencyWithdraw_WithdrawAll() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        uint256 contractBalance = weth.balanceOf(address(distribution));
        uint256 initialBalance = weth.balanceOf(owner);
        
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(owner, "WETH", contractBalance);
        
        distribution.emergencyWithdraw("WETH", owner, 0); // 0 means withdraw all
        
        assertEq(weth.balanceOf(owner), initialBalance + contractBalance);
        assertEq(weth.balanceOf(address(distribution)), 0);
        vm.stopPrank();
    }

    function test_pause_Success() public {
        vm.prank(owner);
        distribution.pause();
        assertTrue(distribution.paused());
    }

    function test_unpause_Success() public {
        vm.startPrank(owner);
        distribution.pause();
        distribution.unpause();
        assertFalse(distribution.paused());
        vm.stopPrank();
    }

    function test_distributeToken_RevertIfPaused() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        distribution.pause();
        
        vm.expectRevert();
        distribution.distributeToken("WETH", user1, 1 ether);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_getTokenCount() public {
        vm.startPrank(owner);
        assertEq(distribution.getTokenCount(), 0);
        
        distribution.addToken("WETH", address(weth), 18);
        assertEq(distribution.getTokenCount(), 1);
        
        distribution.addToken("USDC", address(usdc), 6);
        assertEq(distribution.getTokenCount(), 2);
        vm.stopPrank();
    }

    function test_getAllTokenSymbols() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        distribution.addToken("USDC", address(usdc), 6);
        
        string[] memory symbols = distribution.getAllTokenSymbols();
        assertEq(symbols.length, 2);
        assertEq(symbols[0], "WETH");
        assertEq(symbols[1], "USDC");
        vm.stopPrank();
    }

    function test_getTokenBalance() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        
        uint256 balance = distribution.getTokenBalance("WETH");
        assertEq(balance, weth.balanceOf(address(distribution)));
        vm.stopPrank();
    }

    function test_getUserDistributionHistory() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        distribution.addToken("USDC", address(usdc), 6);
        
        distribution.distributeToken("WETH", user1, 1 ether);
        distribution.distributeToken("USDC", user1, 1000 * 10 ** 6);
        
        MultiTokenDistribution.DistributionRecord[] memory history = 
            distribution.getUserDistributionHistory(user1);
        
        assertEq(history.length, 2);
        assertEq(history[0].amount, 1 ether);
        assertEq(history[0].tokenSymbol, "WETH");
        assertEq(history[1].amount, 1000 * 10 ** 6);
        assertEq(history[1].tokenSymbol, "USDC");
        vm.stopPrank();
    }

    function test_getUserTokenHistory() public {
        vm.startPrank(owner);
        distribution.addToken("WETH", address(weth), 18);
        distribution.addToken("USDC", address(usdc), 6);
        
        distribution.distributeToken("WETH", user1, 1 ether);
        distribution.distributeToken("USDC", user1, 1000 * 10 ** 6);
        distribution.distributeToken("WETH", user1, 2 ether);
        
        MultiTokenDistribution.DistributionRecord[] memory wethHistory = 
            distribution.getUserTokenHistory(user1, "WETH");
        
        assertEq(wethHistory.length, 2);
        assertEq(wethHistory[0].amount, 1 ether);
        assertEq(wethHistory[1].amount, 2 ether);
        
        MultiTokenDistribution.DistributionRecord[] memory usdcHistory = 
            distribution.getUserTokenHistory(user1, "USDC");
        
        assertEq(usdcHistory.length, 1);
        assertEq(usdcHistory[0].amount, 1000 * 10 ** 6);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              INTEGRATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_fullWorkflow() public {
        vm.startPrank(owner);
        
        // Add multiple tokens
        distribution.addToken("WETH", address(weth), 18);
        distribution.addToken("USDC", address(usdc), 6);
        distribution.addToken("USDT", address(usdt), 6);
        
        // Distribute to multiple users
        distribution.distributeToken("WETH", user1, 1 ether);
        distribution.distributeToken("USDC", user1, 1000 * 10 ** 6);
        distribution.distributeToken("USDT", user2, 500 * 10 ** 6);
        
        // Batch distribute
        address[] memory users = new address[](2);
        users[0] = user2;
        users[1] = user3;
        
        uint256[] memory amounts = new uint256[](2);
        amounts[0] = 2 ether;
        amounts[1] = 3 ether;
        
        distribution.batchDistributeToken("WETH", users, amounts);
        
        // Check final state
        assertEq(distribution.totalDistributions(), 5);
        assertEq(distribution.totalUsers(), 3);
        
        (, , , uint256 wethDistributed, uint256 wethUsers) = distribution.supportedTokens("WETH");
        assertEq(wethDistributed, 6 ether);
        assertEq(wethUsers, 3);
        
        (, , , uint256 usdcDistributed, uint256 usdcUsers) = distribution.supportedTokens("USDC");
        assertEq(usdcDistributed, 1000 * 10 ** 6);
        assertEq(usdcUsers, 1);
        
        // Check user balances
        assertEq(weth.balanceOf(user1), 1 ether);
        assertEq(weth.balanceOf(user2), 2 ether);
        assertEq(weth.balanceOf(user3), 3 ether);
        assertEq(usdc.balanceOf(user1), 1000 * 10 ** 6);
        assertEq(usdt.balanceOf(user2), 500 * 10 ** 6);
        
        vm.stopPrank();
    }
} 