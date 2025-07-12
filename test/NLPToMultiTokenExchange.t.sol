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
        jpyUsdPriceFeed = new MockV3Aggregator(JPY_USD_DECIMALS, 0.0067e8); // 1 JPY = 0.0067 USD
        ethUsdPriceFeed = new MockV3Aggregator(ETH_USD_DECIMALS, 2500e8); // 1 ETH = 2500 USD
        usdcUsdPriceFeed = new MockV3Aggregator(USDC_USD_DECIMALS, 1e8); // 1 USDC = 1 USD
        usdtUsdPriceFeed = new MockV3Aggregator(USDT_USD_DECIMALS, 1e8); // 1 USDT = 1 USD

        // Deploy exchange contract
        exchange = new NLPToMultiTokenExchange(address(nlpToken), address(jpyUsdPriceFeed), owner);

        // Grant roles
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), feeManager);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), configManager);

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

        // Fund user with NLP tokens
        nlpToken.transfer(user, 100000 * 10 ** 18);

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               BASIC TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testInitialConfiguration() public view {
        assertEq(address(exchange.nlpToken()), address(nlpToken));
        assertEq(address(exchange.jpyUsdPriceFeed()), address(jpyUsdPriceFeed));
        assertTrue(exchange.hasJpyOracle());
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

    function testOnlyPriceUpdaterCanUpdatePrices() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 2600e18);

        vm.prank(priceUpdater);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 2600e18);
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

    function testExternalPriceUpdate() public {
        uint newPrice = 2600e18; // New ETH price

        vm.prank(priceUpdater);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, newPrice);

        (uint price,,,) = exchange.externalPrices(NLPToMultiTokenExchange.TokenType.ETH);
        assertEq(price, newPrice);
    }

    function testBatchPriceUpdate() public {
        NLPToMultiTokenExchange.TokenType[] memory tokenTypes =
            new NLPToMultiTokenExchange.TokenType[](2);
        tokenTypes[0] = NLPToMultiTokenExchange.TokenType.USDC;
        tokenTypes[1] = NLPToMultiTokenExchange.TokenType.USDT;

        uint[] memory prices = new uint[](2);
        prices[0] = 1.01e18; // USDC slightly above $1
        prices[1] = 0.99e18; // USDT slightly below $1

        uint jpyUsdPrice = 0.0068e18; // Updated JPY/USD price

        vm.prank(priceUpdater);
        exchange.batchUpdatePrices(tokenTypes, prices, jpyUsdPrice);

        (uint usdcPrice,,,) = exchange.externalPrices(NLPToMultiTokenExchange.TokenType.USDC);
        (uint usdtPrice,,,) = exchange.externalPrices(NLPToMultiTokenExchange.TokenType.USDT);
        (uint jpyPrice,,,) = exchange.jpyUsdExternalPrice();

        assertEq(usdcPrice, prices[0]);
        assertEq(usdtPrice, prices[1]);
        assertEq(jpyPrice, jpyUsdPrice);
    }

    function testJPYUSDExternalPriceUpdate() public {
        uint newPrice = 0.0068e18; // New JPY/USD price

        vm.prank(priceUpdater);
        exchange.updateJPYUSDExternalPrice(newPrice);

        (uint price,,,) = exchange.jpyUsdExternalPrice();
        assertEq(price, newPrice);
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

    function testInvalidPriceUpdate() public {
        vm.prank(priceUpdater);
        vm.expectRevert();
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 0);
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
        vm.expectRevert("Treasury not set");
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
            uint operationalFee,
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
        (uint ethBalance, bool isPaused, uint jpyUsdPrice,) = exchange.getContractStatus();

        assertEq(ethBalance, 100 ether);
        assertFalse(isPaused);
        assertTrue(jpyUsdPrice > 0);
    }

    function testExternalPriceFallback() public {
        // Disable oracle by setting invalid price feed
        vm.prank(configManager);
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH,
            address(0),
            address(0), // No oracle
            18,
            100,
            "ETH"
        );

        // Set external price
        vm.prank(priceUpdater);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 2600e18);

        // Exchange should still work
        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              EDGE CASE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testZeroExchangeAmount() public {
        vm.startPrank(user);
        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, 0);
        vm.stopPrank();
    }

    function testInsufficientBalance() public {
        // Empty the contract
        vm.prank(owner);
        exchange.setTreasury(owner);

        vm.prank(emergencyManager);
        exchange.pause();

        vm.prank(emergencyManager);
        exchange.emergencyWithdrawETH(0);

        vm.prank(emergencyManager);
        exchange.unpause();

        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              FUZZ TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testFuzzExchangeAmount(uint amount) public {
        // Set minimum amount to avoid precision issues with very small amounts
        amount = bound(amount, 1000 * 10 ** 18, nlpToken.balanceOf(user)); // Min 1000 NLP

        // Store initial balances
        uint initialNLPBalance = nlpToken.balanceOf(user);
        uint initialETHBalance = user.balance;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), amount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, amount);
        vm.stopPrank();

        // Verify NLP was burned
        assertEq(nlpToken.balanceOf(user), initialNLPBalance - amount);

        // Verify user received ETH (should be greater than before)
        assertTrue(user.balance > initialETHBalance);

        // Verify exchange statistics were updated
        NLPToMultiTokenExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenExchange.TokenType.ETH);
        assertEq(stats.totalExchanged, amount);
        assertTrue(stats.totalTokenSent > 0);
        assertTrue(stats.totalExchangeFeeCollected > 0);
    }

    function testFuzzOperationalFeeRate(uint feeRate) public {
        feeRate = bound(feeRate, 0, 200); // 0-2%

        vm.prank(feeManager);
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH, feeRate, feeRecipient, true
        );

        NLPToMultiTokenExchange.OperationalFeeConfig memory config =
            exchange.getOperationalFeeConfig(NLPToMultiTokenExchange.TokenType.ETH);

        assertEq(config.feeRate, feeRate);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              PRICE DATA VALIDATION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testStaleOracleData() public {
        // Set oracle price to be older than threshold
        vm.warp(block.timestamp + 3700); // 3700 seconds = more than 1 hour

        // Set valid external prices to ensure fallback works
        // Both token price and JPY/USD price need to be updated after warp
        vm.startPrank(priceUpdater);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 2600e18);
        exchange.updateJPYUSDExternalPrice(0.0067e18); // Update JPY/USD price as well
        vm.stopPrank();

        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Should use external price as fallback
        NLPToMultiTokenExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenExchange.TokenType.ETH);
        assertEq(stats.exchangeCount, 1);
    }

    function testInvalidOraclePrice() public {
        // Set negative price in oracle
        ethUsdPriceFeed.updateAnswer(-1);

        // Set valid external prices to ensure fallback works
        // Ensure both token price and JPY/USD price are available
        vm.startPrank(priceUpdater);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 2600e18);
        exchange.updateJPYUSDExternalPrice(0.0067e18); // Ensure fresh JPY/USD price
        vm.stopPrank();

        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();

        // Should use external price as fallback
        NLPToMultiTokenExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenExchange.TokenType.ETH);
        assertEq(stats.exchangeCount, 1);
    }

    function testNoValidPriceDataAvailable() public {
        // Disable oracle by setting zero price
        ethUsdPriceFeed.updateAnswer(0);
        jpyUsdPriceFeed.updateAnswer(0);

        // Set stale external prices
        vm.prank(priceUpdater);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, 2600e18);

        vm.prank(priceUpdater);
        exchange.updateJPYUSDExternalPrice(0.0067e18);

        // Make external prices stale
        vm.warp(block.timestamp + 3700);

        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenExchange.TokenType.ETH, nlpAmount);
        vm.stopPrank();
    }

    receive() external payable { }
}
