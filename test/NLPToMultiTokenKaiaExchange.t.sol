// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenKaiaExchange } from "../src/NLPToMultiTokenKaiaExchange.sol";
import { IERC20Extended } from "../src/interfaces/IERC20Extended.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";
import { PythAggregatorV3 } from "../src/pyth/PythAggregatorV3.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract MockNLPTokenKaia is ERC20DecimalsWithMint {
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

contract MockTokenKaia is ERC20DecimalsWithMint {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20DecimalsWithMint(name, symbol, decimals_)
    { }

    function mint(address to, uint amount) external override {
        _mint(to, amount);
    }
}

// Mock Pyth Network contract for testing
contract MockPyth {
    struct PriceData {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }

    mapping(bytes32 => PriceData) public prices;

    function updatePrice(bytes32 id, int64 price, uint64 conf, int32 expo) external {
        prices[id] = PriceData(price, conf, expo, block.timestamp);
    }

    function getPriceUnsafe(bytes32 id) external view returns (PriceData memory) {
        return prices[id];
    }

    function getUpdateFee(bytes[] calldata) external pure returns (uint) {
        return 0;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        // Mock implementation - do nothing
    }
}

contract NLPToMultiTokenKaiaExchangeTest is Test {
    // Event declarations for testing
    event ExchangeModeUpdated(
        NLPToMultiTokenKaiaExchange.ExchangeMode oldMode,
        NLPToMultiTokenKaiaExchange.ExchangeMode newMode,
        address updatedBy
    );

    event KAIAUSDOracleUpdated(
        address indexed oldOracle, bytes32 oldPriceId, address indexed newOracle, bytes32 newPriceId
    );

    event USDCUSDOracleUpdated(
        address indexed oldOracle, bytes32 oldPriceId, address indexed newOracle, bytes32 newPriceId
    );

    event USDTUSDOracleUpdated(
        address indexed oldOracle, bytes32 oldPriceId, address indexed newOracle, bytes32 newPriceId
    );

    NLPToMultiTokenKaiaExchange public exchange;
    MockNLPTokenKaia public nlpToken;
    MockTokenKaia public usdcToken;
    MockTokenKaia public usdtToken;
    MockPyth public mockPyth;

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

    // Mock price data (matching Pyth format)
    int64 public constant JPY_USD_PRICE = 677093; // 1 JPY = 0.00677093 USD (8 decimals)
    int64 public constant KAIA_USD_PRICE = 15000000; // 1 KAIA = 0.15 USD (8 decimals)
    int64 public constant USDC_USD_PRICE = 99971995; // 1 USDC = 1 USD (8 decimals)
    int64 public constant USDT_USD_PRICE = 100000000; // 1 USDT = 1 USD (8 decimals)

    // Pyth price IDs
    bytes32 public constant KAIA_USD_PRICE_ID = keccak256("KAIA/USD");
    bytes32 public constant USDC_USD_PRICE_ID = keccak256("USDC/USD");
    bytes32 public constant USDT_USD_PRICE_ID = keccak256("USDT/USD");

    event ExchangeExecuted(
        address indexed user,
        NLPToMultiTokenKaiaExchange.TokenType indexed tokenType,
        uint nlpAmount,
        uint tokenAmount,
        uint tokenUsdRate,
        uint jpyUsdRate,
        uint exchangeFee,
        uint operationalFee
    );

    event GaslessExchangeExecuted(
        address indexed user,
        address indexed relayer,
        NLPToMultiTokenKaiaExchange.TokenType indexed tokenType,
        uint nlpAmount,
        uint tokenAmount,
        uint tokenUsdRate,
        uint jpyUsdRate,
        uint exchangeFee,
        uint operationalFee
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens and Pyth
        nlpToken = new MockNLPTokenKaia();
        usdcToken = new MockTokenKaia("USD Coin", "USDC", 6);
        usdtToken = new MockTokenKaia("Tether USD", "USDT", 6);
        mockPyth = new MockPyth();

        // Set up mock Pyth prices
        mockPyth.updatePrice(KAIA_USD_PRICE_ID, KAIA_USD_PRICE, 0, -8);
        mockPyth.updatePrice(USDC_USD_PRICE_ID, USDC_USD_PRICE, 0, -8);
        mockPyth.updatePrice(USDT_USD_PRICE_ID, USDT_USD_PRICE, 0, -8);

        // Deploy exchange contract with simplified constructor
        exchange = new NLPToMultiTokenKaiaExchange(address(nlpToken), address(mockPyth), owner);

        console.log("NLPToMultiTokenKaiaExchange deployed at:", address(exchange));

        // Grant roles
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), feeManager);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), configManager);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), whitelistManager);

        // Set treasury
        exchange.setTreasury(feeRecipient);

        // Configure tokens using the new configureToken function
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            KAIA_USD_PRICE_ID,
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            address(usdcToken),
            USDC_USD_PRICE_ID,
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            address(usdtToken),
            USDT_USD_PRICE_ID,
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            50, // 0.5% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            25, // 0.25% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            30, // 0.3% operational fee
            feeRecipient,
            true
        );

        // Update JPY/USD price data (external data source)
        _updateJPYPriceData();

        // Fund the exchange contract
        vm.deal(address(exchange), 100 ether);
        usdcToken.mint(address(exchange), 1000000 * 10 ** 6); // 1M USDC
        usdtToken.mint(address(exchange), 1000000 * 10 ** 6); // 1M USDT

        // Fund users with NLP tokens
        nlpToken.transfer(user, 100000 * 10 ** 18);
        nlpToken.transfer(user2, 50000 * 10 ** 18);
        nlpToken.transfer(user3, 50000 * 10 ** 18);

        // Exchange mode is PUBLIC by default (gas optimized, no access restrictions)
        assertEq(
            uint(exchange.exchangeMode()), uint(NLPToMultiTokenKaiaExchange.ExchangeMode.PUBLIC)
        );

        vm.stopPrank();
    }

    function _updateJPYPriceData() internal {
        uint currentTime = block.timestamp;

        // JPY/USD uses external data source (not Pyth)
        exchange.updateJPYUSDRoundData(1, int(JPY_USD_PRICE), currentTime, currentTime, 1);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                               BASIC TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testInitialConfiguration() public view {
        assertEq(address(exchange.nlpToken()), address(nlpToken));
        assertEq(exchange.getNLPToJPYRate(), 100);
        assertEq(exchange.getNLPToJPYRateDenominator(), 100);
        assertTrue(exchange.hasRole(exchange.DEFAULT_ADMIN_ROLE(), owner));
        assertTrue(exchange.hasRole(exchange.CONFIG_MANAGER_ROLE(), owner));
        assertTrue(exchange.hasRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater));
        assertTrue(exchange.hasRole(exchange.FEE_MANAGER_ROLE(), feeManager));
        assertTrue(exchange.hasRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager));
    }

    function testTokenConfiguration() public view {
        NLPToMultiTokenKaiaExchange.TokenConfig memory config =
            exchange.getTokenConfig(NLPToMultiTokenKaiaExchange.TokenType.KAIA);

        assertEq(config.tokenAddress, address(0));
        assertEq(config.decimals, 18);
        assertEq(config.exchangeFee, 100);
        assertTrue(config.isEnabled);
        assertTrue(config.hasOracle);
        assertEq(config.symbol, "KAIA");
    }

    function testPriceUpdates() public view {
        // Test JPY/USD price (external data)
        uint jpyPrice = exchange.getLatestJPYPrice();
        assertEq(jpyPrice, uint(int(JPY_USD_PRICE)) * 1e10); // Convert 8->18 decimals

        // Test KAIA/USD price (via getLatestKAIAPrice)
        uint kaiaPrice = exchange.getLatestKAIAPrice();
        assertEq(kaiaPrice, uint(int(KAIA_USD_PRICE)) * 1e10);
    }

    function testUpdateKAIAOracle() public {
        bytes32 newPriceId = keccak256("NEW_KAIA/USD");
        // address newPythAddress = address(0x999);

        // Deploy new mock Pyth
        MockPyth newMockPyth = new MockPyth();
        newMockPyth.updatePrice(newPriceId, KAIA_USD_PRICE, 0, -8);

        vm.expectEmit(true, true, true, true);
        emit KAIAUSDOracleUpdated(
            address(mockPyth), KAIA_USD_PRICE_ID, address(mockPyth), newPriceId
        );

        vm.prank(owner);
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            newPriceId,
            18,
            100, // Keep same fee
            "KAIA"
        );
    }

    function testUpdateUSDCOracle() public {
        bytes32 newPriceId = keccak256("NEW_USDC/USD");

        // Deploy new mock Pyth
        MockPyth newMockPyth = new MockPyth();
        newMockPyth.updatePrice(newPriceId, USDC_USD_PRICE, 0, -8);

        vm.expectEmit(true, true, true, true);
        emit USDCUSDOracleUpdated(
            address(mockPyth), USDC_USD_PRICE_ID, address(mockPyth), newPriceId
        );

        vm.prank(owner);
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            address(usdcToken),
            newPriceId,
            6,
            50, // Keep same fee
            "USDC"
        );
    }

    function testUpdateUSDTOracle() public {
        bytes32 newPriceId = keccak256("NEW_USDT/USD");

        // Deploy new mock Pyth
        MockPyth newMockPyth = new MockPyth();
        newMockPyth.updatePrice(newPriceId, USDT_USD_PRICE, 0, -8);

        vm.expectEmit(true, true, true, true);
        emit USDTUSDOracleUpdated(
            address(mockPyth), USDT_USD_PRICE_ID, address(mockPyth), newPriceId
        );

        vm.prank(owner);
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            address(usdtToken),
            newPriceId,
            6,
            75, // Keep same fee
            "USDT"
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          OPERATIONAL FEE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /* ═══════════════════════════════════════════════════════════════════════
                             ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testOnlyPriceUpdaterCanUpdateJPYPrice() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.updateJPYUSDRoundData(1, 68000000, block.timestamp, block.timestamp, 1);

        vm.prank(priceUpdater);
        exchange.updateJPYUSDRoundData(1, 68000000, block.timestamp, block.timestamp, 1);
    }

    function testOnlyConfigManagerCanReconfigureTokens() public {
        bytes32 newPriceId = keccak256("NEW_PRICE_ID");

        vm.prank(user);
        vm.expectRevert();
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            newPriceId,
            18,
            100, // Keep same fee
            "KAIA"
        );

        vm.prank(owner);
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            newPriceId,
            18,
            100, // Keep same fee
            "KAIA"
        );
    }

    function testOnlyEmergencyManagerCanPause() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.pause();

        vm.prank(emergencyManager);
        exchange.pause();
        assertTrue(exchange.paused());
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              SLIPPAGE PROTECTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    /* ═══════════════════════════════════════════════════════════════════════
                              GASLESS EXCHANGE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testExchangeNLPWithPermitKAIA() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Get initial balances
        uint userNLPBalanceBefore = nlpToken.balanceOf(user);
        uint userKAIABalanceBefore = user.balance;
        uint contractKAIABalanceBefore = address(exchange).balance;

        // Set up permit allowance for testing
        vm.prank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Execute gasless exchange via relayer
        vm.prank(relayer);
        vm.expectEmit(true, true, true, false);
        emit GaslessExchangeExecuted(
            user,
            relayer,
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            0, // tokenAmount - we don't check exact amount
            0, // tokenUsdRate - we don't check exact rate
            0, // jpyUsdRate - we don't check exact rate
            0, // exchangeFee - we don't check exact fee
            0 // operationalFee - we don't check exact fee
        );

        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), userNLPBalanceBefore - nlpAmount);

        // Verify user received KAIA (should be > 0)
        assertTrue(user.balance > userKAIABalanceBefore);

        // Verify contract KAIA balance decreased
        assertTrue(address(exchange).balance < contractKAIABalanceBefore);
    }

    function testExchangeNLPWithPermitUSDC() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Get initial balances
        uint userNLPBalanceBefore = nlpToken.balanceOf(user);
        uint userUSDCBalanceBefore = usdcToken.balanceOf(user);
        uint contractUSDCBalanceBefore = usdcToken.balanceOf(address(exchange));

        // Set up permit allowance for testing
        vm.prank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Execute gasless exchange via relayer
        vm.prank(relayer);
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), userNLPBalanceBefore - nlpAmount);

        // Verify user received USDC (should be > 0)
        assertTrue(usdcToken.balanceOf(user) > userUSDCBalanceBefore);

        // Verify contract USDC balance decreased
        assertTrue(usdcToken.balanceOf(address(exchange)) < contractUSDCBalanceBefore);
    }

    function testExchangeNLPWithPermitUSDT() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Get initial balances
        uint userNLPBalanceBefore = nlpToken.balanceOf(user);
        uint userUSDTBalanceBefore = usdtToken.balanceOf(user);
        uint contractUSDTBalanceBefore = usdtToken.balanceOf(address(exchange));

        // Set up permit allowance for testing
        vm.prank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Execute gasless exchange via relayer
        vm.prank(relayer);
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), userNLPBalanceBefore - nlpAmount);

        // Verify user received USDT (should be > 0)
        assertTrue(usdtToken.balanceOf(user) > userUSDTBalanceBefore);

        // Verify contract USDT balance decreased
        assertTrue(usdtToken.balanceOf(address(exchange)) < contractUSDTBalanceBefore);
    }

    function testExchangeNLPWithPermitFailsWithZeroAmount() public {
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenKaiaExchange.InvalidExchangeAmount.selector, 0)
        );
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            0, // Zero amount should fail
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );
    }

    function testExchangeNLPWithPermitFailsWithZeroUser() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenKaiaExchange.InvalidUser.selector, address(0))
        );
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            address(0) // Zero address should fail
        );
    }

    function testExchangeNLPWithPermitFailsWithDisabledToken() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Disable KAIA token
        vm.prank(owner);
        exchange.setTokenEnabled(NLPToMultiTokenKaiaExchange.TokenType.KAIA, false);

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToMultiTokenKaiaExchange.TokenNotEnabled.selector,
                NLPToMultiTokenKaiaExchange.TokenType.KAIA
            )
        );
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );
    }

    function testExchangeNLPWithPermitFailsWhenPaused() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Pause the contract
        vm.prank(emergencyManager);
        exchange.pause();

        vm.prank(relayer);
        vm.expectRevert(); // Accept any revert due to paused state
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );
    }

    function testExchangeNLPWithPermitWorksInWhitelistMode() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Set to whitelist mode
        vm.prank(owner);
        exchange.setExchangeMode(NLPToMultiTokenKaiaExchange.ExchangeMode.WHITELIST);

        // Add relayer to whitelist
        address[] memory accounts = new address[](1);
        bool[] memory whitelisted = new bool[](1);
        accounts[0] = relayer;
        whitelisted[0] = true;

        vm.prank(whitelistManager);
        exchange.updateWhitelist(accounts, whitelisted);

        // Set up permit allowance for testing
        vm.prank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Should work with whitelisted relayer
        vm.prank(relayer);
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );
    }

    function testExchangeNLPWithPermitFailsInWhitelistModeWithoutWhitelist() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Set to whitelist mode
        vm.prank(owner);
        exchange.setExchangeMode(NLPToMultiTokenKaiaExchange.ExchangeMode.WHITELIST);

        // Don't add relayer to whitelist

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenKaiaExchange.NotWhitelisted.selector, relayer)
        );
        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              ADMIN FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testEmergencyWithdrawETH() public {
        uint withdrawAmount = 1 ether;

        // Pause the contract
        vm.prank(emergencyManager);
        exchange.pause();

        uint balanceBefore = feeRecipient.balance;

        vm.prank(emergencyManager);
        exchange.emergencyWithdrawETH(withdrawAmount);

        assertEq(feeRecipient.balance, balanceBefore + withdrawAmount);
    }

    function testContractStatus() public view {
        (uint ethBalance, bool isPaused, uint jpyUsdPrice) = exchange.getContractStatus();

        assertEq(ethBalance, 100 ether);
        assertFalse(isPaused);
        assertTrue(jpyUsdPrice > 0);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              OPTIONAL PRICE FEED TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testOptionalPriceFeedDeploy() public {
        // Test deployment with simplified constructor
        NLPToMultiTokenKaiaExchange testExchange =
            new NLPToMultiTokenKaiaExchange(address(nlpToken), address(mockPyth), owner);

        // Configure only KAIA token (no USDC/USDT)
        vm.prank(owner);
        testExchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            KAIA_USD_PRICE_ID,
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        // Verify contract deployed successfully
        assertTrue(address(testExchange) != address(0));
        assertEq(address(testExchange.nlpToken()), address(nlpToken));
    }

    receive() external payable { }
}
