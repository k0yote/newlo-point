// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { MultiTokenDistribution } from "../src/MultiTokenDistribution.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { ERC20 } from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import { AccessControl } from "@openzeppelin/contracts/access/AccessControl.sol";
import { IAccessControl } from "@openzeppelin/contracts/access/IAccessControl.sol";

// Mock ERC20 token for testing
contract MockERC20 is ERC20 {
    uint8 private _decimals;

    constructor(string memory name, string memory symbol, uint8 decimals_, uint initialSupply)
        ERC20(name, symbol)
    {
        _decimals = decimals_;
        _mint(msg.sender, initialSupply);
    }

    function decimals() public view override returns (uint8) {
        return _decimals;
    }

    function mint(address to, uint amount) external {
        _mint(to, amount);
    }
}

contract MultiTokenDistributionTest is Test {
    MultiTokenDistribution public distribution;
    MockERC20 public weth;
    MockERC20 public usdc;
    MockERC20 public usdt;

    // Role constants
    bytes32 public constant ADMIN_ROLE = 0x00;
    bytes32 public constant DISTRIBUTOR_ROLE = keccak256("DISTRIBUTOR_ROLE");
    bytes32 public constant TOKEN_MANAGER_ROLE = keccak256("TOKEN_MANAGER_ROLE");
    bytes32 public constant EMERGENCY_ROLE = keccak256("EMERGENCY_ROLE");

    // Test addresses
    address public admin = address(0x1);
    address public distributor = address(0x2);
    address public tokenManager = address(0x3);
    address public emergencyManager = address(0x4);
    address public user1 = address(0x5);
    address public user2 = address(0x6);
    address public user3 = address(0x7);
    address public unauthorized = address(0x8);

    event TokenAdded(string indexed symbol, address indexed tokenAddress, uint8 decimals);
    event TokenStatusUpdated(string indexed symbol, bool isActive);
    event TokenDistributed(
        address indexed user, string indexed symbol, uint amount, uint timestamp
    );
    event BatchDistributionCompleted(string indexed symbol, uint totalAmount, uint userCount);
    event EmergencyWithdraw(address indexed to, string indexed symbol, uint amount);

    function setUp() public {
        // Deploy mock tokens
        weth = new MockERC20("Wrapped Ether", "WETH", 18, 1000 ether);
        usdc = new MockERC20("USD Coin", "USDC", 6, 1000000 * 10 ** 6);
        usdt = new MockERC20("Tether USD", "USDT", 6, 1000000 * 10 ** 6);

        // Deploy distribution contract with admin
        vm.prank(admin);
        distribution = new MultiTokenDistribution(admin);

        // Grant specific roles to different users
        vm.startPrank(admin);
        distribution.grantRole(DISTRIBUTOR_ROLE, distributor);
        distribution.grantRole(TOKEN_MANAGER_ROLE, tokenManager);
        distribution.grantRole(EMERGENCY_ROLE, emergencyManager);
        vm.stopPrank();

        // Fund the distribution contract
        weth.transfer(address(distribution), 100 ether);
        usdc.transfer(address(distribution), 100000 * 10 ** 6);
        usdt.transfer(address(distribution), 100000 * 10 ** 6);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              ROLE MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_constructor_SetsInitialRoles() public {
        assertTrue(distribution.hasRole(ADMIN_ROLE, admin));
        assertTrue(distribution.hasRole(DISTRIBUTOR_ROLE, admin));
        assertTrue(distribution.hasRole(TOKEN_MANAGER_ROLE, admin));
        assertTrue(distribution.hasRole(EMERGENCY_ROLE, admin));
    }

    function test_grantRole_Success() public {
        vm.prank(admin);
        distribution.grantRole(DISTRIBUTOR_ROLE, user1);
        assertTrue(distribution.hasRole(DISTRIBUTOR_ROLE, user1));
    }

    function test_grantRole_RevertIfNotAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, ADMIN_ROLE
            )
        );
        distribution.grantRole(DISTRIBUTOR_ROLE, user1);
    }

    function test_revokeRole_Success() public {
        vm.startPrank(admin);
        distribution.grantRole(DISTRIBUTOR_ROLE, user1);
        assertTrue(distribution.hasRole(DISTRIBUTOR_ROLE, user1));

        distribution.revokeRole(DISTRIBUTOR_ROLE, user1);
        assertFalse(distribution.hasRole(DISTRIBUTOR_ROLE, user1));
        vm.stopPrank();
    }

    function test_revokeRole_RevertIfNotAdmin() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized, ADMIN_ROLE
            )
        );
        distribution.revokeRole(DISTRIBUTOR_ROLE, distributor);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           TOKEN MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_addToken_Success() public {
        vm.prank(tokenManager);

        vm.expectEmit(true, true, false, true);
        emit TokenAdded("WETH", address(weth), 18);

        distribution.addToken("WETH", address(weth), 18);

        (
            address tokenAddress,
            uint8 decimals,
            bool isActive,
            uint totalDistributed,
            uint totalUsers
        ) = distribution.supportedTokens("WETH");

        assertEq(tokenAddress, address(weth));
        assertEq(decimals, 18);
        assertTrue(isActive);
        assertEq(totalDistributed, 0);
        assertEq(totalUsers, 0);
    }

    function test_addToken_RevertIfNotTokenManager() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                TOKEN_MANAGER_ROLE
            )
        );
        distribution.addToken("WETH", address(weth), 18);
    }

    function test_addToken_RevertIfTokenAlreadyExists() public {
        vm.startPrank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.TokenAlreadyExists.selector, "WETH")
        );
        distribution.addToken("WETH", address(weth), 18);
        vm.stopPrank();
    }

    function test_addToken_RevertIfInvalidAddress() public {
        vm.prank(tokenManager);
        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.InvalidTokenAddress.selector, address(0))
        );
        distribution.addToken("WETH", address(0), 18);
    }

    function test_addToken_RevertIfInvalidSymbol() public {
        vm.prank(tokenManager);
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidSymbol.selector, ""));
        distribution.addToken("", address(weth), 18);
    }

    function test_setTokenStatus_Success() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        vm.expectEmit(true, false, false, true);
        emit TokenStatusUpdated("WETH", false);

        distribution.setTokenStatus("WETH", false);

        (,, bool isActive,,) = distribution.supportedTokens("WETH");
        assertFalse(isActive);
    }

    function test_setTokenStatus_RevertIfNotTokenManager() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                TOKEN_MANAGER_ROLE
            )
        );
        distribution.setTokenStatus("WETH", false);
    }

    function test_setTokenStatus_RevertIfTokenNotSupported() public {
        vm.prank(tokenManager);
        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.TokenNotSupported.selector, "WETH")
        );
        distribution.setTokenStatus("WETH", false);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          DISTRIBUTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_distributeToken_Success() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        uint initialBalance = weth.balanceOf(user1);
        uint distributionAmount = 1 ether;

        vm.prank(distributor);
        vm.expectEmit(true, true, false, true);
        emit TokenDistributed(user1, "WETH", distributionAmount, block.timestamp);

        distribution.distributeToken("WETH", user1, distributionAmount);

        assertEq(weth.balanceOf(user1), initialBalance + distributionAmount);
        assertEq(distribution.userReceivedAmounts(user1, "WETH"), distributionAmount);
        assertEq(distribution.totalDistributions(), 1);
        assertEq(distribution.totalUsers(), 1);

        (,,, uint totalDistributed, uint totalUsers) = distribution.supportedTokens("WETH");
        assertEq(totalDistributed, distributionAmount);
        assertEq(totalUsers, 1);
    }

    function test_distributeToken_RevertIfNotDistributor() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DISTRIBUTOR_ROLE
            )
        );
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    function test_distributeToken_RevertIfTokenNotSupported() public {
        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.TokenNotSupported.selector, "WETH")
        );
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    function test_distributeToken_RevertIfTokenNotActive() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        distribution.setTokenStatus("WETH", false);

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.TokenNotActive.selector, "WETH")
        );
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    function test_distributeToken_RevertIfInvalidUser() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.InvalidUser.selector, address(0))
        );
        distribution.distributeToken("WETH", address(0), 1 ether);
    }

    function test_distributeToken_RevertIfInvalidAmount() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(distributor);
        vm.expectRevert(abi.encodeWithSelector(MultiTokenDistribution.InvalidAmount.selector, 0));
        distribution.distributeToken("WETH", user1, 0);
    }

    function test_distributeToken_RevertIfInsufficientBalance() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        uint contractBalance = weth.balanceOf(address(distribution));
        uint excessiveAmount = contractBalance + 1 ether;

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                MultiTokenDistribution.InsufficientBalance.selector,
                "WETH",
                excessiveAmount,
                contractBalance
            )
        );
        distribution.distributeToken("WETH", user1, excessiveAmount);
    }

    function test_batchDistributeToken_Success() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        address[] memory users = new address[](3);
        users[0] = user1;
        users[1] = user2;
        users[2] = user3;

        uint[] memory amounts = new uint[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        uint totalAmount = 6 ether;

        vm.prank(distributor);
        vm.expectEmit(true, false, false, true);
        emit BatchDistributionCompleted("WETH", totalAmount, 3);

        distribution.batchDistributeToken("WETH", users, amounts);

        assertEq(weth.balanceOf(user1), 1 ether);
        assertEq(weth.balanceOf(user2), 2 ether);
        assertEq(weth.balanceOf(user3), 3 ether);
        assertEq(distribution.totalDistributions(), 3);
        assertEq(distribution.totalUsers(), 3);

        (,,, uint totalDistributed, uint totalUsers) = distribution.supportedTokens("WETH");
        assertEq(totalDistributed, totalAmount);
        assertEq(totalUsers, 3);
    }

    function test_batchDistributeToken_RevertIfNotDistributor() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        address[] memory users = new address[](1);
        users[0] = user1;

        uint[] memory amounts = new uint[](1);
        amounts[0] = 1 ether;

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                DISTRIBUTOR_ROLE
            )
        );
        distribution.batchDistributeToken("WETH", users, amounts);
    }

    function test_batchDistributeToken_RevertIfInvalidArrayLength() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        address[] memory users = new address[](2);
        users[0] = user1;
        users[1] = user2;

        uint[] memory amounts = new uint[](3);
        amounts[0] = 1 ether;
        amounts[1] = 2 ether;
        amounts[2] = 3 ether;

        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(MultiTokenDistribution.InvalidArrayLength.selector, 2, 3)
        );
        distribution.batchDistributeToken("WETH", users, amounts);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           EMERGENCY FUNCTIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_emergencyWithdraw_Success() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        uint withdrawAmount = 10 ether;
        uint initialBalance = weth.balanceOf(admin);

        vm.prank(emergencyManager);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(admin, "WETH", withdrawAmount);

        distribution.emergencyWithdraw("WETH", admin, withdrawAmount);

        assertEq(weth.balanceOf(admin), initialBalance + withdrawAmount);
    }

    function test_emergencyWithdraw_RevertIfNotEmergencyManager() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                EMERGENCY_ROLE
            )
        );
        distribution.emergencyWithdraw("WETH", admin, 10 ether);
    }

    function test_emergencyWithdraw_WithdrawAll() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        uint contractBalance = weth.balanceOf(address(distribution));
        uint initialBalance = weth.balanceOf(admin);

        vm.prank(emergencyManager);
        vm.expectEmit(true, true, false, true);
        emit EmergencyWithdraw(admin, "WETH", contractBalance);

        distribution.emergencyWithdraw("WETH", admin, 0); // 0 means withdraw all

        assertEq(weth.balanceOf(admin), initialBalance + contractBalance);
        assertEq(weth.balanceOf(address(distribution)), 0);
    }

    function test_pause_Success() public {
        vm.prank(emergencyManager);
        distribution.pause();
        assertTrue(distribution.paused());
    }

    function test_pause_RevertIfNotEmergencyManager() public {
        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                EMERGENCY_ROLE
            )
        );
        distribution.pause();
    }

    function test_unpause_Success() public {
        vm.prank(emergencyManager);
        distribution.pause();

        vm.prank(emergencyManager);
        distribution.unpause();
        assertFalse(distribution.paused());
    }

    function test_unpause_RevertIfNotEmergencyManager() public {
        vm.prank(emergencyManager);
        distribution.pause();

        vm.prank(unauthorized);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                unauthorized,
                EMERGENCY_ROLE
            )
        );
        distribution.unpause();
    }

    function test_distributeToken_RevertIfPaused() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(emergencyManager);
        distribution.pause();

        vm.prank(distributor);
        vm.expectRevert();
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTIONS TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_getTokenCount() public {
        assertEq(distribution.getTokenCount(), 0);

        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);
        assertEq(distribution.getTokenCount(), 1);

        vm.prank(tokenManager);
        distribution.addToken("USDC", address(usdc), 6);
        assertEq(distribution.getTokenCount(), 2);
    }

    function test_getAllTokenSymbols() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        distribution.addToken("USDC", address(usdc), 6);

        string[] memory symbols = distribution.getAllTokenSymbols();
        assertEq(symbols.length, 2);
        assertEq(symbols[0], "WETH");
        assertEq(symbols[1], "USDC");
    }

    function test_getTokenBalance() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        uint balance = distribution.getTokenBalance("WETH");
        assertEq(balance, weth.balanceOf(address(distribution)));
    }

    function test_getUserDistributionHistory() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        distribution.addToken("USDC", address(usdc), 6);

        vm.prank(distributor);
        distribution.distributeToken("WETH", user1, 1 ether);

        vm.prank(distributor);
        distribution.distributeToken("USDC", user1, 1000 * 10 ** 6);

        MultiTokenDistribution.DistributionRecord[] memory history =
            distribution.getUserDistributionHistory(user1);

        assertEq(history.length, 2);
        assertEq(history[0].amount, 1 ether);
        assertEq(history[0].tokenSymbol, "WETH");
        assertEq(history[1].amount, 1000 * 10 ** 6);
        assertEq(history[1].tokenSymbol, "USDC");
    }

    function test_getUserTokenHistory() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        distribution.addToken("USDC", address(usdc), 6);

        vm.prank(distributor);
        distribution.distributeToken("WETH", user1, 1 ether);

        vm.prank(distributor);
        distribution.distributeToken("USDC", user1, 1000 * 10 ** 6);

        vm.prank(distributor);
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
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              INTEGRATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_fullWorkflow() public {
        // Add multiple tokens
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        distribution.addToken("USDC", address(usdc), 6);

        vm.prank(tokenManager);
        distribution.addToken("USDT", address(usdt), 6);

        // Distribute to multiple users
        vm.prank(distributor);
        distribution.distributeToken("WETH", user1, 1 ether);

        vm.prank(distributor);
        distribution.distributeToken("USDC", user1, 1000 * 10 ** 6);

        vm.prank(distributor);
        distribution.distributeToken("USDT", user2, 500 * 10 ** 6);

        // Batch distribute
        address[] memory users = new address[](2);
        users[0] = user2;
        users[1] = user3;

        uint[] memory amounts = new uint[](2);
        amounts[0] = 2 ether;
        amounts[1] = 3 ether;

        vm.prank(distributor);
        distribution.batchDistributeToken("WETH", users, amounts);

        // Check final state
        assertEq(distribution.totalDistributions(), 5);
        assertEq(distribution.totalUsers(), 3);

        (,,, uint wethDistributed, uint wethUsers) = distribution.supportedTokens("WETH");
        assertEq(wethDistributed, 6 ether);
        assertEq(wethUsers, 3);

        (,,, uint usdcDistributed, uint usdcUsers) = distribution.supportedTokens("USDC");
        assertEq(usdcDistributed, 1000 * 10 ** 6);
        assertEq(usdcUsers, 1);

        // Check user balances
        assertEq(weth.balanceOf(user1), 1 ether);
        assertEq(weth.balanceOf(user2), 2 ether);
        assertEq(weth.balanceOf(user3), 3 ether);
        assertEq(usdc.balanceOf(user1), 1000 * 10 ** 6);
        assertEq(usdt.balanceOf(user2), 500 * 10 ** 6);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                         CROSS-ROLE ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_adminCanPerformAllOperations() public {
        // Admin can do token management
        vm.prank(admin);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(admin);
        distribution.setTokenStatus("WETH", false);

        // Admin can do distribution
        vm.prank(admin);
        distribution.setTokenStatus("WETH", true);

        vm.prank(admin);
        distribution.distributeToken("WETH", user1, 1 ether);

        // Admin can do emergency operations
        vm.prank(admin);
        distribution.pause();

        vm.prank(admin);
        distribution.unpause();

        vm.prank(admin);
        distribution.emergencyWithdraw("WETH", admin, 1 ether);

        // Verify operations were successful
        assertEq(weth.balanceOf(user1), 1 ether);
        assertEq(weth.balanceOf(admin), 1 ether);
        assertFalse(distribution.paused());
    }

    function test_distributorCannotDoTokenManagement() public {
        vm.prank(distributor);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                distributor,
                TOKEN_MANAGER_ROLE
            )
        );
        distribution.addToken("WETH", address(weth), 18);
    }

    function test_tokenManagerCannotDoDistribution() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(tokenManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                tokenManager,
                DISTRIBUTOR_ROLE
            )
        );
        distribution.distributeToken("WETH", user1, 1 ether);
    }

    function test_emergencyManagerCannotDoDistribution() public {
        vm.prank(tokenManager);
        distribution.addToken("WETH", address(weth), 18);

        vm.prank(emergencyManager);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                emergencyManager,
                DISTRIBUTOR_ROLE
            )
        );
        distribution.distributeToken("WETH", user1, 1 ether);
    }
}
