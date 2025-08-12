// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenExchange } from "../src/NLPToMultiTokenExchange.sol";
import { IERC20Extended } from "../src/interfaces/IERC20Extended.sol";
import { AggregatorV3Interface } from
    "@chainlink/contracts/src/v0.8/shared/interfaces/AggregatorV3Interface.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract MockNLPToken is ERC20DecimalsWithMint {
    mapping(address => mapping(address => uint)) public allowances;
    mapping(address => uint) private _nonces;

    constructor() ERC20DecimalsWithMint("NewLo Point", "NLP", 18) {
        _mint(msg.sender, 1000000 * 10 ** 18);
    }

    function burnFrom(address account, uint amount) external {
        uint currentAllowance = allowances[account][msg.sender];
        require(currentAllowance >= amount, "ERC20: burn amount exceeds allowance");

        // Check if account has sufficient balance
        require(balanceOf(account) >= amount, "ERC20: burn amount exceeds balance");

        _burn(account, amount);
        allowances[account][msg.sender] = currentAllowance - amount;
    }

    function permit(
        address owner,
        address spender,
        uint value,
        uint deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external {
        require(deadline >= block.timestamp, "Permit deadline expired");
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        // In real implementation, signature verification would be here
        // For testing purposes, we'll simulate signature verification
        bytes32 digest = keccak256(abi.encodePacked(owner, spender, value, deadline, v, r, s));
        require(digest != bytes32(0), "Invalid signature parameters");

        allowances[owner][spender] = value;
        _nonces[owner]++;
    }

    function approve(address spender, uint amount) public override returns (bool) {
        allowances[msg.sender][spender] = amount;
        return true;
    }

    function allowance(address owner, address spender) public view override returns (uint) {
        return allowances[owner][spender];
    }

    function DOMAIN_SEPARATOR() external pure returns (bytes32) {
        return keccak256("MockDomainSeparator");
    }

    function nonces(address owner) external view returns (uint) {
        return _nonces[owner];
    }
}

contract MockToken is ERC20DecimalsWithMint {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20DecimalsWithMint(name, symbol, decimals_)
    { }

    function mint(address to, uint amount) external override {
        _mint(to, amount);
    }
}

contract NLPToMultiTokenExchangeTest is Test {
    // Event declarations for testing
    event ExchangeModeUpdated(
        NLPToMultiTokenExchange.ExchangeMode oldMode,
        NLPToMultiTokenExchange.ExchangeMode newMode,
        address updatedBy
    );

    NLPToMultiTokenExchange public exchange;
    MockNLPToken public nlpToken;
    MockToken public usdcToken;
    MockToken public usdtToken;
    MockV3Aggregator public jpyUsdPriceFeed;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public usdcUsdPriceFeed;
    MockV3Aggregator public usdtUsdPriceFeed;

    address public owner = address(0x1);
    address public user = address(0x2);
    address public priceUpdater = address(0x3);
    address public feeManager = address(0x4);
    address public emergencyManager = address(0x5);
    address public configManager = address(0x6);
    address public feeRecipient = address(0x7);
    address public whitelistManager = address(0x8);
    address public user2 = address(0x9);
    address public user3 = address(0x10);

    uint8 public constant JPY_USD_DECIMALS = 8;
    uint8 public constant ETH_USD_DECIMALS = 8;
    uint8 public constant USDC_USD_DECIMALS = 8;
    uint8 public constant USDT_USD_DECIMALS = 8;

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        nlpToken = new MockNLPToken();
        usdcToken = new MockToken("USD Coin", "USDC", 6);
        usdtToken = new MockToken("Tether USD", "USDT", 6);

        // Deploy mock price feeds
        jpyUsdPriceFeed = new MockV3Aggregator(JPY_USD_DECIMALS, 677093); // 1 JPY = 0.00677093 USD (actual Chainlink data)
        ethUsdPriceFeed = new MockV3Aggregator(ETH_USD_DECIMALS, 3483e8); // 1 ETH = 2500 USD
        usdcUsdPriceFeed = new MockV3Aggregator(USDC_USD_DECIMALS, 99971995); // 1 USDC = 1 USD
        usdtUsdPriceFeed = new MockV3Aggregator(USDT_USD_DECIMALS, 1e8); // 1 USDT = 1 USD

        // Deploy exchange contract
        exchange = new NLPToMultiTokenExchange(
            address(nlpToken),
            address(ethUsdPriceFeed),
            address(jpyUsdPriceFeed),
            address(usdcUsdPriceFeed),
            address(usdtUsdPriceFeed),
            owner
        );

        // Grant roles
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), feeManager);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), configManager);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), whitelistManager);

        // Configure tokens
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH,
            address(0),
            address(ethUsdPriceFeed),
            18,
            100, // 1% exchange fee
            "ETH"
        );

        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDC,
            address(usdcToken),
            address(usdcUsdPriceFeed),
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDT,
            address(usdtToken),
            address(usdtUsdPriceFeed),
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            50, // 0.5% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDC,
            25, // 0.25% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDT,
            30, // 0.3% operational fee
            feeRecipient,
            true
        );

        // Fund the exchange contract
        vm.deal(address(exchange), 100 ether);
        usdcToken.mint(address(exchange), 1000000 * 10 ** 6); // 1M USDC
        usdtToken.mint(address(exchange), 1000000 * 10 ** 6); // 1M USDT

        // Fund users with NLP tokens
        nlpToken.transfer(user, 100000 * 10 ** 18);
        nlpToken.transfer(user2, 50000 * 10 ** 18);
        nlpToken.transfer(user3, 50000 * 10 ** 18);

        // Exchange mode is PUBLIC by default (gas optimized, no access restrictions)
        // This ensures minimal gas costs for all exchange operations in tests
        // The exchange mode is already PUBLIC by default, but we can verify it:
        assertEq(uint(exchange.exchangeMode()), uint(NLPToMultiTokenExchange.ExchangeMode.PUBLIC));

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               BASIC TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testInitialConfiguration() public view {
        assertEq(address(exchange.nlpToken()), address(nlpToken));
        assertEq(address(exchange.jpyUsdPriceFeed()), address(jpyUsdPriceFeed));
        assertTrue(address(exchange.jpyUsdPriceFeed()) != address(0));
        assertTrue(exchange.hasRole(exchange.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(exchange.hasRole(exchange.CONFIG_MANAGER_ROLE(), owner));
        assertTrue(exchange.hasRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater));
        assertTrue(exchange.hasRole(exchange.FEE_MANAGER_ROLE(), feeManager));
        assertTrue(exchange.hasRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager));
    }

    function testTokenConfiguration() public view {
        NLPToMultiTokenExchange.TokenConfig memory config =
            exchange.getTokenConfig(NLPToMultiTokenExchange.TokenType.ETH);

        assertEq(config.tokenAddress, address(0));
        assertEq(address(config.priceFeed), address(ethUsdPriceFeed));
        assertEq(config.decimals, 18);
        assertEq(config.exchangeFee, 100);
        assertTrue(config.isEnabled);
        assertTrue(config.hasOracle);
        assertEq(config.symbol, "ETH");
    }

    function testOperationalFeeConfiguration() public view {
        NLPToMultiTokenExchange.OperationalFeeConfig memory config =
            exchange.getOperationalFeeConfig(NLPToMultiTokenExchange.TokenType.ETH);

        assertEq(config.feeRate, 50);
        assertEq(config.feeRecipient, feeRecipient);
        assertTrue(config.isEnabled);
    }

    function testBasicExchangeETH() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint userBalanceBefore = user.balance;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        assertEq(nlpToken.balanceOf(user), 100000 * 10 ** 18 - nlpAmount);
        assertTrue(user.balance > userBalanceBefore);
    }

    function testBasicExchangeUSDC() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint userBalanceBefore = usdcToken.balanceOf(user);

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.USDC, nlpAmount);
        vm.stopPrank();

        assertEq(nlpToken.balanceOf(user), 100000 * 10 ** 18 - nlpAmount);
        assertTrue(usdcToken.balanceOf(user) > userBalanceBefore);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          OPERATIONAL FEE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testOperationalFeeCollection() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint feeRecipientBalanceBefore = feeRecipient.balance;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Check that operational fees were collected
        uint collectedFee =
            exchange.getCollectedOperationalFee(NLPToMultiTokenExchange.TokenType.ETH);
        assertTrue(collectedFee > 0);

        // Withdraw operational fees
        vm.prank(feeManager);
        exchange.withdrawOperationalFee(NLPToMultiTokenExchange.TokenType.ETH, 0);

        // Check that fees were sent to recipient
        assertTrue(feeRecipient.balance > feeRecipientBalanceBefore);
        assertEq(exchange.getCollectedOperationalFee(NLPToMultiTokenExchange.TokenType.ETH), 0);
    }

    function testOperationalFeeConfigurationUpdate() public {
        vm.prank(feeManager);
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            100, // 1% fee
            address(0x99),
            true
        );

        NLPToMultiTokenExchange.OperationalFeeConfig memory config =
            exchange.getOperationalFeeConfig(NLPToMultiTokenExchange.TokenType.ETH);

        assertEq(config.feeRate, 100);
        assertEq(config.feeRecipient, address(0x99));
        assertTrue(config.isEnabled);
    }

    function testOperationalFeeDisabling() public {
        vm.prank(feeManager);
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH, 0, address(0), false
        );

        uint nlpAmount = 1000 * 10 ** 18;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // No operational fees should be collected
        assertEq(exchange.getCollectedOperationalFee(NLPToMultiTokenExchange.TokenType.ETH), 0);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                             ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testOnlyConfigManagerCanConfigureTokens() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH, address(0), address(0), 18, 100, "ETH"
        );

        vm.prank(configManager);
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH, address(0), address(0), 18, 100, "ETH"
        );
    }

    function testOnlyFeeManagerCanConfigureOperationalFees() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH, 50, feeRecipient, true
        );

        vm.prank(feeManager);
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH, 50, feeRecipient, true
        );
    }

    function testOnlyPriceUpdaterCanUpdateJPYPrice() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.updateJPYUSDRoundData(1, 68000000, block.timestamp, block.timestamp, 1);

        vm.prank(priceUpdater);
        exchange.updateJPYUSDRoundData(1, 68000000, block.timestamp, block.timestamp, 1);
    }

    function testOnlyEmergencyManagerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.pause();

        vm.prank(emergencyManager);
        exchange.pause();
        assertTrue(exchange.paused());
    }

    function testOnlyFeeManagerCanWithdrawOperationalFees() public {
        // First, collect some fees
        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Try to withdraw as non-fee manager
        vm.prank(user);
        vm.expectRevert();
        exchange.withdrawOperationalFee(NLPToMultiTokenExchange.TokenType.ETH, 0);

        // Withdraw as fee manager
        vm.prank(feeManager);
        exchange.withdrawOperationalFee(NLPToMultiTokenExchange.TokenType.ETH, 0);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              PRICE MANAGEMENT TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testETHPriceFromOracle() public view {
        // ETH price is now fetched from oracle only
        uint ethPrice = exchange.getLatestETHPrice();
        assertTrue(ethPrice > 0, "ETH price should be greater than 0");
    }

    function testOraclePricesAreWorking() public view {
        // Test that oracle prices are accessible for all tokens
        assertTrue(exchange.getLatestETHPrice() > 0, "ETH oracle price should work");

        // JPY price from external round data or oracle
        uint jpyPrice = exchange.getLatestJPYPrice();
        assertTrue(jpyPrice > 0, "JPY price should be available");
    }

    function testJPYUSDExternalPriceUpdate() public {
        uint newPrice = 0.0068e18; // New JPY/USD price
        int answer = int(newPrice / 10 ** 10); // Convert to 8 decimals

        vm.prank(priceUpdater);
        exchange.updateJPYUSDRoundData(
            1, // roundId
            answer, // answer in 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        (, int retrievedAnswer,,,) = exchange.jpyUsdExternalRoundData();
        assertEq(retrievedAnswer, answer);
        assertEq(uint(retrievedAnswer) * 10 ** 10, newPrice); // Check conversion back to 18 decimals
    }

    /* ═══════════════════════════════════════════════════════════════════════
                             ERROR HANDLING TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testInvalidOperationalFeeRate() public {
        vm.prank(feeManager);
        vm.expectRevert();
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            600, // 6% - exceeds maximum
            feeRecipient,
            true
        );
    }

    function testInvalidFeeRecipient() public {
        vm.prank(feeManager);
        vm.expectRevert();
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            50,
            address(0), // Invalid recipient
            true
        );
    }

    function testInsufficientOperationalFeeWithdrawal() public {
        vm.prank(feeManager);
        vm.expectRevert();
        exchange.withdrawOperationalFee(NLPToMultiTokenExchange.TokenType.ETH, 1000 ether);
    }

    function testInvalidExchangeFeeRate() public {
        vm.prank(configManager);
        vm.expectRevert();
        exchange.setTokenExchangeFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            600 // 6% - exceeds maximum
        );
    }

    function testUpdateMaxFee() public {
        uint newMaxFee = 300; // 3%

        vm.prank(owner);
        exchange.updateMaxFee(newMaxFee);

        assertEq(exchange.maxFee(), newMaxFee);

        // Test that the new limit is enforced
        vm.prank(configManager);
        vm.expectRevert();
        exchange.setTokenExchangeFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            400 // 4% - exceeds new maximum
        );
    }

    function testUpdateMaxFeeOnlyAdmin() public {
        vm.prank(configManager);
        vm.expectRevert();
        exchange.updateMaxFee(300);
    }

    function testUpdateMaxFeeExceedsAbsolute() public {
        vm.prank(owner);
        vm.expectRevert();
        exchange.updateMaxFee(10001); // Exceeds 100%
    }

    function testInvalidJPYPriceUpdate() public {
        vm.prank(priceUpdater);
        vm.expectRevert();
        exchange.updateJPYUSDRoundData(1, 0, block.timestamp, block.timestamp, 1); // Invalid price = 0
    }

    function testExchangeWhenPaused() public {
        vm.prank(emergencyManager);
        exchange.pause();

        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              GASLESS EXCHANGE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testGaslessExchange() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;

        address relayer = address(0x99);
        uint userBalanceBefore = user.balance;

        vm.prank(relayer);
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenExchange.TokenType.ETH,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );

        assertEq(nlpToken.balanceOf(user), 100000 * 10 ** 18 - nlpAmount);
        assertTrue(user.balance > userBalanceBefore);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              ADMIN FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testEmergencyWithdrawETH() public {
        uint withdrawAmount = 1 ether;

        // Set treasury first
        vm.prank(owner);
        exchange.setTreasury(address(0x99));

        // Pause the contract
        vm.prank(emergencyManager);
        exchange.pause();

        uint balanceBefore = address(0x99).balance;

        vm.prank(emergencyManager);
        exchange.emergencyWithdrawETH(withdrawAmount);

        assertEq(address(0x99).balance, balanceBefore + withdrawAmount);
    }

    function testEmergencyWithdrawToken() public {
        uint withdrawAmount = 1000 * 10 ** 6; // 1000 USDC
        address treasuryAddr = address(0x99);

        // Set treasury first
        vm.prank(owner);
        exchange.setTreasury(treasuryAddr);

        // Pause the contract
        vm.prank(emergencyManager);
        exchange.pause();

        uint balanceBefore = usdcToken.balanceOf(treasuryAddr);

        vm.prank(emergencyManager);
        exchange.emergencyWithdrawToken(NLPToMultiTokenExchange.TokenType.USDC, withdrawAmount);

        assertEq(usdcToken.balanceOf(treasuryAddr), balanceBefore + withdrawAmount);
    }

    function testSetTreasury() public {
        address newTreasury = address(0x99);

        vm.prank(owner);
        exchange.setTreasury(newTreasury);

        assertEq(exchange.treasury(), newTreasury);
    }

    function testSetTreasuryOnlyAdmin() public {
        vm.prank(configManager);
        vm.expectRevert();
        exchange.setTreasury(address(0x99));
    }

    function testSetTreasuryZeroAddress() public {
        vm.prank(owner);
        vm.expectRevert();
        exchange.setTreasury(address(0));
    }

    function testEmergencyWithdrawWithoutTreasury() public {
        vm.prank(emergencyManager);
        exchange.pause();

        vm.prank(emergencyManager);
        vm.expectRevert(abi.encodeWithSelector(NLPToMultiTokenExchange.TreasuryNotSet.selector));
        exchange.emergencyWithdrawETH(1 ether);
    }

    function testTokenEnableDisable() public {
        vm.prank(configManager);
        exchange.setTokenEnabled(NLPToMultiTokenExchange.TokenType.ETH, false);

        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              INTEGRATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testFullExchangeFlow() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Get quote
        (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee
        ) = exchange.getExchangeQuote(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);

        assertTrue(tokenAmount > 0);
        assertTrue(tokenUsdRate > 0);
        assertTrue(jpyUsdRate > 0);
        assertTrue(exchangeFee > 0);
        assertTrue(operationalFee > 0);

        // Execute exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Verify statistics
        NLPToMultiTokenExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenExchange.TokenType.ETH);

        assertEq(stats.totalExchanged, nlpAmount);
        assertEq(stats.totalTokenSent, tokenAmount);
        assertEq(stats.totalExchangeFeeCollected, exchangeFee);
        assertEq(stats.totalOperationalFeeCollected, operationalFee);
        assertEq(stats.exchangeCount, 1);
    }

    function testMultipleExchanges() public {
        uint nlpAmount = 500 * 10 ** 18;

        // First exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Second exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.USDC, nlpAmount);
        vm.stopPrank();

        // Verify user history
        (uint ethExchanged, uint ethReceived) =
            exchange.getUserExchangeHistory(user, NLPToMultiTokenExchange.TokenType.ETH);
        (uint usdcExchanged, uint usdcReceived) =
            exchange.getUserExchangeHistory(user, NLPToMultiTokenExchange.TokenType.USDC);

        assertEq(ethExchanged, nlpAmount);
        assertEq(usdcExchanged, nlpAmount);
        assertTrue(ethReceived > 0);
        assertTrue(usdcReceived > 0);
    }

    function testContractStatus() public view {
        (uint ethBalance, bool isPaused, uint jpyUsdPrice) = exchange.getContractStatus();

        assertEq(ethBalance, 100 ether);
        assertFalse(isPaused);
        assertTrue(jpyUsdPrice > 0);
    }

    function testOnlyOracleBasedPricing() public view {
        // Test that all token prices come from oracles
        // ETH price should come from dedicated oracle
        uint ethPrice = exchange.getLatestETHPrice();
        assertTrue(ethPrice > 0, "ETH price from oracle should be available");

        // JPY price should come from external round data
        uint jpyPrice = exchange.getLatestJPYPrice();
        assertTrue(jpyPrice > 0, "JPY price should be available");

        // Get quotes to ensure oracle-based pricing works
        (uint ethAmount,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenExchange.TokenType.ETH, 1000e18);
        assertTrue(ethAmount > 0, "ETH exchange quote should work");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              EDGE CASE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testZeroExchangeAmount() public {
        vm.prank(user);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenExchange.InvalidExchangeAmount.selector, 0)
        );
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 0);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              ORACLE UPDATE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testUpdateJPYUSDOracle() public {
        address newOracle = address(0x123);

        // vm.expectEmit(true, true, false, true);
        // emit JPYUSDOracleUpdated(address(jpyUsdPriceFeed), newOracle);

        vm.prank(owner);
        exchange.updateJPYUSDOracle(newOracle);

        assertEq(address(exchange.jpyUsdPriceFeed()), newOracle);
    }

    function testUpdateUSDCUSDOracle() public {
        address newOracle = address(0x456);

        // vm.expectEmit(true, true, false, true);
        // emit USDCUSDOracleUpdated(address(usdcUsdPriceFeed), newOracle);

        vm.prank(owner);
        exchange.updateUSDCUSDOracle(newOracle);

        assertEq(address(exchange.usdcUsdPriceFeed()), newOracle);
    }

    function testUpdateUSDTUSDOracle() public {
        address newOracle = address(0x789);

        // vm.expectEmit(true, true, false, true);
        // emit USDTUSDOracleUpdated(address(usdtUsdPriceFeed), newOracle);

        vm.prank(owner);
        exchange.updateUSDTUSDOracle(newOracle);

        assertEq(address(exchange.usdtUsdPriceFeed()), newOracle);
    }

    function testOnlyAdminCanUpdateOracles() public {
        address newOracle = address(0xABC);

        vm.expectRevert();
        vm.prank(user);
        exchange.updateJPYUSDOracle(newOracle);

        vm.expectRevert();
        vm.prank(user);
        exchange.updateUSDCUSDOracle(newOracle);

        vm.expectRevert();
        vm.prank(user);
        exchange.updateUSDTUSDOracle(newOracle);
    }

    function testOracleUpdateToAddressZero() public {
        // Test updating oracle to address(0) to disable it
        vm.startPrank(owner);

        exchange.updateJPYUSDOracle(address(0));
        assertEq(address(exchange.jpyUsdPriceFeed()), address(0));

        exchange.updateUSDCUSDOracle(address(0));
        assertEq(address(exchange.usdcUsdPriceFeed()), address(0));

        exchange.updateUSDTUSDOracle(address(0));
        assertEq(address(exchange.usdtUsdPriceFeed()), address(0));

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           NLP TO JPY RATE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test NLP to JPY rate update functionality
     */
    function testUpdateNLPToJPYRate() public {
        uint newRate = 150; // 1.5 JPY per NLP

        // Only admin can update rate
        vm.prank(owner);
        exchange.updateNLPToJPYRate(newRate);

        assertEq(exchange.getNLPToJPYRate(), newRate, "Rate should be updated");

        // Test calculation with new rate
        uint nlpAmount = 1000 * 10 ** 18;
        uint jpyAmount = exchange.calculateJPYAmount(nlpAmount);
        uint expectedJpyAmount = (nlpAmount * newRate) / exchange.getNLPToJPYRateDenominator();

        assertEq(jpyAmount, expectedJpyAmount, "JPY calculation should reflect new rate");
    }

    /**
     * @notice Test that only admin can update NLP to JPY rate
     */
    function testOnlyAdminCanUpdateNLPToJPYRate() public {
        uint newRate = 150;

        // Non-admin should fail
        vm.prank(user);
        vm.expectRevert();
        exchange.updateNLPToJPYRate(newRate);

        // Admin should succeed
        vm.prank(owner);
        exchange.updateNLPToJPYRate(newRate);

        assertEq(exchange.getNLPToJPYRate(), newRate, "Rate should be updated by admin");
    }

    /**
     * @notice Test rate validation (zero rate should fail)
     */
    function testZeroRateValidationMultiToken() public {
        vm.prank(owner);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenExchange.InvalidRateValue.selector, 0)
        );
        exchange.updateNLPToJPYRate(0);
    }

    /**
     * @notice Test rate denominator is correctly configured
     */
    function testRateDenominatorMultiToken() public view {
        uint denominator = exchange.getNLPToJPYRateDenominator();
        assertEq(denominator, 100, "Rate denominator should be 100");
    }

    /**
     * @notice Test exchange calculation with different rates for multi-token
     */
    function testExchangeWithDifferentRatesMultiToken() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Test with rate = 50 (0.5 JPY per NLP)
        vm.prank(owner);
        exchange.updateNLPToJPYRate(50);

        (uint tokenAmount1,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);

        // Test with rate = 200 (2.0 JPY per NLP)
        vm.prank(owner);
        exchange.updateNLPToJPYRate(200);

        (uint tokenAmount2,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);

        // Higher rate should give more tokens (200/50 = 4x more)
        assertApproxEqRel(
            tokenAmount2,
            tokenAmount1 * 4,
            0.001e18,
            "Higher rate should give proportionally more tokens"
        );
    }

    /**
     * @notice Test actual exchange with custom rate
     */
    function testActualExchangeWithCustomRate() public {
        // Set rate to 1.5 JPY per NLP (150/100)
        vm.prank(owner);
        exchange.updateNLPToJPYRate(150);

        uint nlpAmount = 1000 * 10 ** 18;
        uint initialUserBalance = user.balance;
        uint initialNLPBalance = nlpToken.balanceOf(user);

        // Execute exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), initialNLPBalance - nlpAmount, "NLP tokens not burned");

        // Verify user received ETH (should be 1.5x more than with default 0.9 rate)
        assertGt(user.balance, initialUserBalance, "User should receive ETH");

        // Verify statistics updated
        NLPToMultiTokenExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenExchange.TokenType.ETH);
        assertEq(stats.totalExchanged, nlpAmount, "Total exchanged not updated");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                           SLIPPAGE PROTECTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Test slippage protection quote calculation
     */
    function testSlippageQuoteCalculation() public view {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 100; // 1%

        (uint minAmountOut, uint quoteAmount) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, slippageTolerance
        );

        assertGt(quoteAmount, 0, "Quote amount should be greater than 0");
        assertLt(minAmountOut, quoteAmount, "Minimum amount should be less than quote");

        // Check that minAmountOut is 99% of quoteAmount (1% slippage)
        uint expectedMinAmount = (quoteAmount * 9900) / 10000;
        assertEq(minAmountOut, expectedMinAmount, "Minimum amount calculation incorrect");
    }

    /**
     * @notice Test comprehensive slippage quote with all return values
     */
    function testComprehensiveSlippageQuote() public view {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 250; // 2.5%

        (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee,
            uint minAmountOut,
            uint maxSlippageAmount
        ) = exchange.getExchangeQuoteWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, slippageTolerance
        );

        assertGt(tokenAmount, 0, "Token amount should be greater than 0");
        assertGt(tokenUsdRate, 0, "Token USD rate should be greater than 0");
        assertGt(jpyUsdRate, 0, "JPY USD rate should be greater than 0");
        assertGt(exchangeFee, 0, "Exchange fee should be greater than 0");
        assertGt(operationalFee, 0, "Operational fee should be greater than 0");
        assertLt(minAmountOut, tokenAmount, "Minimum amount should be less than token amount");

        // Check slippage calculations
        uint expectedMinAmount = (tokenAmount * 9750) / 10000; // 97.5% of tokenAmount
        assertEq(minAmountOut, expectedMinAmount, "Minimum amount calculation incorrect");
        assertEq(
            maxSlippageAmount, tokenAmount - minAmountOut, "Max slippage calculation incorrect"
        );
    }

    /**
     * @notice Test successful exchange with slippage protection
     */
    function testSuccessfulExchangeWithSlippage() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 100; // 1%

        // Get quote first
        (uint minAmountOut, uint quoteAmount) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, slippageTolerance
        );

        uint initialUserBalance = user.balance;
        uint initialNLPBalance = nlpToken.balanceOf(user);

        // Execute exchange with slippage protection
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLPWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, minAmountOut
        );
        vm.stopPrank();

        // Verify exchange was successful
        assertEq(nlpToken.balanceOf(user), initialNLPBalance - nlpAmount, "NLP tokens not burned");
        assertGe(
            user.balance, initialUserBalance + minAmountOut, "User didn't receive minimum amount"
        );
        assertLe(user.balance, initialUserBalance + quoteAmount, "User received more than expected");
    }

    /**
     * @notice Test exchange failure due to slippage protection
     */
    function testExchangeFailureSlippageProtection() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Get current quote
        (uint tokenAmount,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);

        // Set unrealistic minAmountOut (higher than possible)
        uint unrealisticMinAmount = tokenAmount * 2;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Expect SlippageToleranceExceeded error
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToMultiTokenExchange.SlippageToleranceExceeded.selector,
                tokenAmount,
                tokenAmount,
                unrealisticMinAmount
            )
        );

        exchange.exchangeNLPWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, unrealisticMinAmount
        );
        vm.stopPrank();
    }

    /**
     * @notice Test permit-based exchange with slippage protection
     */
    function testPermitExchangeWithSlippage() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 100; // 1%

        // Get quote
        (uint minAmountOut,) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.USDC, nlpAmount, slippageTolerance
        );

        uint initialUserUSDCBalance = usdcToken.balanceOf(user);
        uint initialNLPBalance = nlpToken.balanceOf(user);

        // Execute permit-based exchange with slippage protection
        vm.prank(user);
        exchange.exchangeNLPWithPermitAndSlippage(
            NLPToMultiTokenExchange.TokenType.USDC,
            nlpAmount,
            minAmountOut,
            block.timestamp + 1 hours,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );

        // Verify exchange was successful
        assertEq(nlpToken.balanceOf(user), initialNLPBalance - nlpAmount, "NLP tokens not burned");
        assertGe(
            usdcToken.balanceOf(user),
            initialUserUSDCBalance + minAmountOut,
            "User didn't receive minimum USDC amount"
        );
    }

    /**
     * @notice Test legacy functions still work (backward compatibility)
     */
    function testLegacyFunctionsBackwardCompatibility() public {
        uint nlpAmount = 1000 * 10 ** 18;

        uint initialUserBalance = user.balance;
        uint initialNLPBalance = nlpToken.balanceOf(user);

        // Test legacy exchange function (without slippage protection)
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Verify exchange was successful
        assertEq(nlpToken.balanceOf(user), initialNLPBalance - nlpAmount, "NLP tokens not burned");
        assertGt(user.balance, initialUserBalance, "User should receive ETH");
    }

    /**
     * @notice Test price change simulation with slippage protection
     */
    function testPriceChangeWithSlippageProtection() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 200; // 2%

        // Get initial quote
        (uint initialMinAmountOut,) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, slippageTolerance
        );

        // Simulate price drop by updating ETH price feed
        vm.prank(owner);
        ethUsdPriceFeed.updateAnswer(2000e8); // Drop from 3483 to 2000 USD

        uint userBalanceBefore = user.balance;

        // Exchange should still succeed with slippage protection
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLPWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, initialMinAmountOut
        );
        vm.stopPrank();

        // User should receive more ETH due to lower ETH price, but at least the minimum
        assertGe(
            user.balance, userBalanceBefore + initialMinAmountOut, "Slippage protection failed"
        );
    }

    /**
     * @notice Test extreme slippage tolerance validation
     */
    function testExtremeSlippageToleranceValidation() public view {
        uint nlpAmount = 1000 * 10 ** 18;

        // Test with 0% slippage (should work)
        (uint minAmountOut1, uint quoteAmount1) =
            exchange.calculateMinAmountOut(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, 0);
        assertEq(minAmountOut1, quoteAmount1, "0% slippage should give same amounts");

        // Test with 100% slippage (should give 0 min amount)
        (uint minAmountOut2,) =
            exchange.calculateMinAmountOut(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, 10000);
        assertEq(minAmountOut2, 0, "100% slippage should give 0 min amount");
    }

    /**
     * @notice Test slippage calculation with different tokens
     */
    function testSlippageCalculationDifferentTokens() public view {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 150; // 1.5%

        // Test ETH (18 decimals)
        (uint ethMinAmount, uint ethQuote) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, slippageTolerance
        );

        // Test USDC (6 decimals)
        (uint usdcMinAmount, uint usdcQuote) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.USDC, nlpAmount, slippageTolerance
        );

        // Test USDT (6 decimals)
        (uint usdtMinAmount, uint usdtQuote) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.USDT, nlpAmount, slippageTolerance
        );

        // All should have valid calculations
        assertGt(ethQuote, 0, "ETH quote should be positive");
        assertGt(usdcQuote, 0, "USDC quote should be positive");
        assertGt(usdtQuote, 0, "USDT quote should be positive");

        // All min amounts should be 98.5% of quotes
        assertEq(ethMinAmount, (ethQuote * 9850) / 10000, "ETH slippage calculation incorrect");
        assertEq(usdcMinAmount, (usdcQuote * 9850) / 10000, "USDC slippage calculation incorrect");
        assertEq(usdtMinAmount, (usdtQuote * 9850) / 10000, "USDT slippage calculation incorrect");
    }

    /**
     * @notice Test invalid slippage tolerance validation
     */
    function testInvalidSlippageToleranceValidation() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Test with slippage tolerance > 100% (should revert)
        vm.expectRevert("Slippage tolerance too high");
        exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.ETH,
            nlpAmount,
            10001 // 100.01%
        );

        // Test comprehensive quote with invalid slippage
        vm.expectRevert("Slippage tolerance too high");
        exchange.getExchangeQuoteWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH,
            nlpAmount,
            15000 // 150%
        );
    }

    /**
     * @notice Test slippage protection with disabled token
     */
    function testSlippageProtectionWithDisabledToken() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Disable ETH token
        vm.prank(configManager);
        exchange.setTokenEnabled(NLPToMultiTokenExchange.TokenType.ETH, false);

        // Should return zeros for disabled token
        (uint minAmountOut, uint quoteAmount) =
            exchange.calculateMinAmountOut(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, 100);

        assertEq(minAmountOut, 0, "Disabled token should return 0 min amount");
        assertEq(quoteAmount, 0, "Disabled token should return 0 quote");

        // Comprehensive quote should also return zeros
        (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee,
            uint minAmountOut2,
            uint maxSlippageAmount
        ) = exchange.getExchangeQuoteWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, 100
        );

        assertEq(tokenAmount, 0, "Disabled token should return 0 token amount");
        assertEq(tokenUsdRate, 0, "Disabled token should return 0 USD rate");
        assertEq(jpyUsdRate, 0, "Disabled token should return 0 JPY rate");
        assertEq(exchangeFee, 0, "Disabled token should return 0 exchange fee");
        assertEq(operationalFee, 0, "Disabled token should return 0 operational fee");
        assertEq(minAmountOut2, 0, "Disabled token should return 0 min amount");
        assertEq(maxSlippageAmount, 0, "Disabled token should return 0 max slippage");
    }

    /**
     * @notice Test slippage protection integration with gas optimization
     */
    function testSlippageProtectionGasOptimization() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 100; // 1%

        // Measure gas for slippage-protected exchange
        uint gasStart = gasleft();

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        (uint minAmountOut,) = exchange.calculateMinAmountOut(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, slippageTolerance
        );

        exchange.exchangeNLPWithSlippage(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, minAmountOut
        );
        vm.stopPrank();

        uint gasUsed = gasStart - gasleft();

        // Gas usage should be reasonable (less than 400k gas for complex operations)
        assertLt(gasUsed, 400000, "Gas usage should be reasonable for slippage protected exchange");

        // Should be more than basic transfer (shows the function is doing work)
        assertGt(gasUsed, 100000, "Should use meaningful amount of gas for complex operations");
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              RATE CONFIGURATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /* ═══════════════════════════════════════════════════════════════════════
                           ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testExchangeModePublic() public {
        // Default mode should be PUBLIC (already verified in setUp)
        // This test confirms any user can exchange without restrictions

        // Any user should be able to exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testExchangePauseFunctionality() public {
        // Test pause functionality instead of CLOSED mode
        vm.prank(owner);
        exchange.pause();

        // No user should be able to exchange when paused
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();

        // Unpause and should work again
        vm.prank(owner);
        exchange.unpause();

        // Now exchange should work
        vm.startPrank(user);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testExchangeModeWhitelist() public {
        // Set mode to WHITELIST
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);

        // Non-whitelisted user should fail
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenExchange.NotWhitelisted.selector, user)
        );
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();

        // Add user to whitelist
        address[] memory accounts = new address[](1);
        accounts[0] = user;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        vm.prank(whitelistManager);
        exchange.updateWhitelist(accounts, whitelisted);

        // Whitelisted user should succeed
        vm.startPrank(user);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18);
        vm.stopPrank();
    }

    function testWhitelistBatchUpdate() public {
        // Set mode to WHITELIST
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);

        // Batch add users to whitelist
        address[] memory accounts = new address[](3);
        accounts[0] = user;
        accounts[1] = user2;
        accounts[2] = user3;

        bool[] memory whitelisted = new bool[](3);
        whitelisted[0] = true;
        whitelisted[1] = true;
        whitelisted[2] = false;

        vm.prank(whitelistManager);
        exchange.updateWhitelist(accounts, whitelisted);

        // Check whitelist status
        assertTrue(exchange.whitelist(user));
        assertTrue(exchange.whitelist(user2));
        assertFalse(exchange.whitelist(user3));
    }

    function testAccessControlWithSlippage() public {
        // Set mode to WHITELIST
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);

        // Non-whitelisted user should fail even with slippage protection
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenExchange.NotWhitelisted.selector, user)
        );
        exchange.exchangeNLPWithSlippage(NLPToMultiTokenExchange.TokenType.ETH, 1000 * 10 ** 18, 0);
        vm.stopPrank();
    }

    function testAccessControlWithPermit() public {
        // Set mode to WHITELIST
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);

        // Prepare permit parameters
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        uint8 v = 27;
        bytes32 r = bytes32(uint(1));
        bytes32 s = bytes32(uint(2));

        // Non-whitelisted user should fail even with permit
        vm.prank(user2); // Acting as relayer
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenExchange.NotWhitelisted.selector, user)
        );
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenExchange.TokenType.ETH, nlpAmount, deadline, v, r, s, user
        );
    }

    function testRoleManagement() public {
        // Only admin role holders should be able to grant/revoke admin roles

        // Non-admin cannot grant roles - user doesn't have DEFAULT_ADMIN_ROLE
        bytes32 configManagerRole = exchange.CONFIG_MANAGER_ROLE();

        vm.startPrank(user);
        vm.expectRevert(); // Generic revert for AccessControl
        exchange.grantRole(configManagerRole, user2);
        vm.stopPrank();

        // Owner can grant administrative roles (test with CONFIG_MANAGER_ROLE)
        vm.startPrank(owner);
        exchange.grantRole(configManagerRole, user2);
        assertTrue(exchange.hasRole(configManagerRole, user2));

        // Owner can revoke roles
        exchange.revokeRole(configManagerRole, user2);
        assertFalse(exchange.hasRole(configManagerRole, user2));
        vm.stopPrank();
    }

    function testExchangeModeEvents() public {
        vm.prank(configManager);
        vm.expectEmit(true, true, false, true);
        emit NLPToMultiTokenExchange.ExchangeModeUpdated(
            NLPToMultiTokenExchange.ExchangeMode.PUBLIC,
            NLPToMultiTokenExchange.ExchangeMode.WHITELIST,
            configManager
        );
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);
    }

    /**
     * @notice Gas comparison test for different exchange modes
     * @dev This test demonstrates that PUBLIC mode uses the least gas for access control checks
     */
    function testGasComparisonBetweenModes() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Setup: Approve tokens once for all tests
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount * 4);
        vm.stopPrank();

        // Test 1: PUBLIC mode (default - should use least gas for access control)
        // The mode is already PUBLIC by default
        uint gasStartPublic = gasleft();
        vm.prank(user);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        uint gasUsedPublic = gasStartPublic - gasleft();

        // Test 2: WHITELIST mode
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);

        // Add user to whitelist
        address[] memory accounts = new address[](1);
        accounts[0] = user;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;
        vm.prank(whitelistManager);
        exchange.updateWhitelist(accounts, whitelisted);

        uint gasStartWhitelist = gasleft();
        vm.prank(user);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        uint gasUsedWhitelist = gasStartWhitelist - gasleft();

        // Log results for comparison
        console.log("=== Gas Usage Comparison for Exchange Operations ===");
        console.log("PUBLIC mode:      ", gasUsedPublic);
        console.log("WHITELIST mode:   ", gasUsedWhitelist);

        // Calculate additional gas costs (handle potential underflow)
        if (gasUsedWhitelist > gasUsedPublic) {
            console.log("Extra gas for WHITELIST vs PUBLIC: +", gasUsedWhitelist - gasUsedPublic);
        }

        console.log(
            "Note: Only PUBLIC and WHITELIST modes are supported for simplified access control"
        );

        // Note: The actual gas difference for access control is minimal (a few hundred gas)
        // The main benefit of PUBLIC mode is avoiding the storage reads for whitelist/role checks
        console.log("Note: PUBLIC mode optimizes by skipping access control checks entirely");

        // Reset to PUBLIC mode for other tests
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.PUBLIC);
    }

    receive() external payable { }
}
