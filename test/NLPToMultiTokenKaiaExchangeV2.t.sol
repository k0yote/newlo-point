// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenKaiaExchangeV2 } from "../src/NLPToMultiTokenKaiaExchangeV2.sol";
import { IERC20Extended } from "../src/interfaces/IERC20Extended.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/access/IAccessControl.sol";

contract MockNLPTokenKaiaV2 is ERC20DecimalsWithMint {
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

contract MockTokenKaiaV2 is ERC20DecimalsWithMint {
    constructor(string memory name, string memory symbol, uint8 decimals_)
        ERC20DecimalsWithMint(name, symbol, decimals_)
    { }

    function mint(address to, uint amount) external override {
        _mint(to, amount);
    }
}

contract NLPToMultiTokenKaiaExchangeV2Test is Test {
    // Event declarations for testing
    event ExchangeModeUpdated(
        NLPToMultiTokenKaiaExchangeV2.ExchangeMode oldMode,
        NLPToMultiTokenKaiaExchangeV2.ExchangeMode newMode,
        address updatedBy
    );

    event KAIAUSDExternalPriceUpdated(uint newPrice, uint updatedAt, address updatedBy);
    event USDCUSDExternalPriceUpdated(uint newPrice, uint updatedAt, address updatedBy);
    event USDTUSDExternalPriceUpdated(uint newPrice, uint updatedAt, address updatedBy);
    event JPYUSDExternalPriceUpdated(uint newPrice, uint updatedAt, address updatedBy);

    NLPToMultiTokenKaiaExchangeV2 public exchange;
    MockNLPTokenKaiaV2 public nlpToken;
    MockTokenKaiaV2 public usdcToken;
    MockTokenKaiaV2 public usdtToken;

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

    // Mock price data (8 decimals format matching Chainlink)
    int64 public constant JPY_USD_PRICE = 677093; // 1 JPY = 0.00677093 USD
    int64 public constant KAIA_USD_PRICE = 15000000; // 1 KAIA = 0.15 USD
    int64 public constant USDC_USD_PRICE = 99971995; // 1 USDC = ~1 USD
    int64 public constant USDT_USD_PRICE = 100000000; // 1 USDT = 1 USD

    event ExchangeExecuted(
        address indexed user,
        NLPToMultiTokenKaiaExchangeV2.TokenType indexed tokenType,
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
        NLPToMultiTokenKaiaExchangeV2.TokenType indexed tokenType,
        uint nlpAmount,
        uint tokenAmount,
        uint tokenUsdRate,
        uint jpyUsdRate,
        uint exchangeFee,
        uint operationalFee
    );

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        nlpToken = new MockNLPTokenKaiaV2();
        usdcToken = new MockTokenKaiaV2("USD Coin", "USDC", 6);
        usdtToken = new MockTokenKaiaV2("Tether USD", "USDT", 6);

        // Deploy exchange contract with simplified V2 constructor (no oracle dependencies)
        exchange = new NLPToMultiTokenKaiaExchangeV2(address(nlpToken), owner);

        console.log("NLPToMultiTokenKaiaExchangeV2 deployed at:", address(exchange));

        // Grant roles
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), feeManager);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), configManager);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), whitelistManager);

        // Set treasury
        exchange.setTreasury(feeRecipient);

        // Configure tokens (no oracle addresses needed in V2)
        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            address(0), // Native KAIA
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDC,
            address(usdcToken),
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDT,
            address(usdtToken),
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            50, // 0.5% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDC,
            25, // 0.25% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDT,
            30, // 0.3% operational fee
            feeRecipient,
            true
        );

        // Update all price data via external update functions
        _updateAllPriceData();

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
            uint(exchange.exchangeMode()), uint(NLPToMultiTokenKaiaExchangeV2.ExchangeMode.PUBLIC)
        );

        vm.stopPrank();
    }

    function _updateAllPriceData() internal {
        uint currentTime = block.timestamp;

        // Update all external price data
        exchange.updateKAIAUSDRoundData(1, KAIA_USD_PRICE, currentTime, currentTime, 1);
        exchange.updateUSDCUSDRoundData(1, USDC_USD_PRICE, currentTime, currentTime, 1);
        exchange.updateUSDTUSDRoundData(1, USDT_USD_PRICE, currentTime, currentTime, 1);
        exchange.updateJPYUSDRoundData(1, JPY_USD_PRICE, currentTime, currentTime, 1);
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
        NLPToMultiTokenKaiaExchangeV2.TokenConfig memory config =
            exchange.getTokenConfig(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA);

        assertEq(config.tokenAddress, address(0));
        assertEq(config.decimals, 18);
        assertEq(config.exchangeFee, 100);
        assertTrue(config.isEnabled);
        assertEq(config.symbol, "KAIA");
    }

    function testPriceUpdates() public view {
        // Test all external prices
        uint jpyPrice = exchange.getLatestJPYPrice();
        assertEq(jpyPrice, uint(int(JPY_USD_PRICE)) * 1e10); // Convert 8->18 decimals

        uint kaiaPrice = exchange.getLatestKAIAPrice();
        assertEq(kaiaPrice, uint(int(KAIA_USD_PRICE)) * 1e10);

        uint usdcPrice = exchange.getLatestUSDCPrice();
        assertEq(usdcPrice, uint(int(USDC_USD_PRICE)) * 1e10);

        uint usdtPrice = exchange.getLatestUSDTPrice();
        assertEq(usdtPrice, uint(int(USDT_USD_PRICE)) * 1e10);
    }

    function testUpdateKAIAPriceData() public {
        uint currentTime = block.timestamp;
        int newPrice = 20000000; // 0.20 USD

        vm.expectEmit(true, true, true, true);
        emit KAIAUSDExternalPriceUpdated(uint(newPrice), currentTime, priceUpdater);

        vm.prank(priceUpdater);
        exchange.updateKAIAUSDRoundData(2, newPrice, currentTime, currentTime, 2);

        uint kaiaPrice = exchange.getLatestKAIAPrice();
        assertEq(kaiaPrice, uint(int(newPrice)) * 1e10);
    }

    function testUpdateUSDCPriceData() public {
        uint currentTime = block.timestamp;
        int newPrice = 100000000; // 1.00 USD

        vm.expectEmit(true, true, true, true);
        emit USDCUSDExternalPriceUpdated(uint(newPrice), currentTime, priceUpdater);

        vm.prank(priceUpdater);
        exchange.updateUSDCUSDRoundData(2, newPrice, currentTime, currentTime, 2);

        uint usdcPrice = exchange.getLatestUSDCPrice();
        assertEq(usdcPrice, uint(int(newPrice)) * 1e10);
    }

    function testUpdateUSDTPriceData() public {
        uint currentTime = block.timestamp;
        int newPrice = 100050000; // 1.0005 USD

        vm.expectEmit(true, true, true, true);
        emit USDTUSDExternalPriceUpdated(uint(newPrice), currentTime, priceUpdater);

        vm.prank(priceUpdater);
        exchange.updateUSDTUSDRoundData(2, newPrice, currentTime, currentTime, 2);

        uint usdtPrice = exchange.getLatestUSDTPrice();
        assertEq(usdtPrice, uint(int(newPrice)) * 1e10);
    }

    function testUpdateJPYPriceData() public {
        uint currentTime = block.timestamp;
        int newPrice = 700000; // 0.007 USD

        vm.expectEmit(true, true, true, true);
        emit JPYUSDExternalPriceUpdated(uint(newPrice), currentTime, priceUpdater);

        vm.prank(priceUpdater);
        exchange.updateJPYUSDRoundData(2, newPrice, currentTime, currentTime, 2);

        uint jpyPrice = exchange.getLatestJPYPrice();
        assertEq(jpyPrice, uint(int(newPrice)) * 1e10);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                             ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testOnlyPriceUpdaterCanUpdatePrices() public {
        uint currentTime = block.timestamp;

        vm.prank(user);
        vm.expectRevert();
        exchange.updateKAIAUSDRoundData(2, 20000000, currentTime, currentTime, 2);

        vm.prank(priceUpdater);
        exchange.updateKAIAUSDRoundData(2, 20000000, currentTime, currentTime, 2);
    }

    function testOnlyConfigManagerCanConfigureTokens() public {
        vm.prank(user);
        vm.expectRevert();
        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, address(0), 18, 100, "KAIA"
        );

        vm.prank(owner);
        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, address(0), 18, 100, "KAIA"
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
                              EXCHANGE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testExchangeNLPForKAIA() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Get initial balances
        uint userNLPBalanceBefore = nlpToken.balanceOf(user);
        uint userKAIABalanceBefore = user.balance;

        // Approve and exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        vm.expectEmit(true, true, true, false);
        emit ExchangeExecuted(
            user,
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            nlpAmount,
            0, // tokenAmount - we don't check exact amount
            0, // tokenUsdRate
            0, // jpyUsdRate
            0, // exchangeFee
            0 // operationalFee
        );

        exchange.exchangeNLP(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount);
        vm.stopPrank();

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), userNLPBalanceBefore - nlpAmount);

        // Verify user received KAIA
        assertTrue(user.balance > userKAIABalanceBefore);
    }

    function testExchangeNLPForUSDC() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Get initial balances
        uint userNLPBalanceBefore = nlpToken.balanceOf(user);
        uint userUSDCBalanceBefore = usdcToken.balanceOf(user);

        // Approve and exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchangeV2.TokenType.USDC, nlpAmount);
        vm.stopPrank();

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), userNLPBalanceBefore - nlpAmount);

        // Verify user received USDC
        assertTrue(usdcToken.balanceOf(user) > userUSDCBalanceBefore);
    }

    function testExchangeNLPWithSlippage() public {
        uint nlpAmount = 1000 * 10 ** 18;

        // Get quote to calculate minAmountOut
        (uint minAmountOut,) = exchange.calculateMinAmountOut(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount, 100 // 1% slippage
        );

        // Approve and exchange with slippage protection
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLPWithSlippage(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount, minAmountOut
        );
        vm.stopPrank();
    }

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

        // Set up permit allowance for testing
        vm.prank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Execute gasless exchange via relayer
        vm.prank(relayer);
        vm.expectEmit(true, true, true, false);
        emit GaslessExchangeExecuted(
            user,
            relayer,
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            nlpAmount,
            0, // tokenAmount
            0, // tokenUsdRate
            0, // jpyUsdRate
            0, // exchangeFee
            0 // operationalFee
        );

        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            nlpAmount,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user), userNLPBalanceBefore - nlpAmount);

        // Verify user received KAIA
        assertTrue(user.balance > userKAIABalanceBefore);
    }

    function testExchangeNLPWithPermitAndSlippage() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;
        address relayer = address(0x99);

        // Get quote to calculate minAmountOut
        (uint minAmountOut,) = exchange.calculateMinAmountOut(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount, 100 // 1% slippage
        );

        // Set up permit allowance for testing
        vm.prank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        // Execute gasless exchange with slippage protection
        vm.prank(relayer);
        exchange.exchangeNLPWithPermitAndSlippage(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            nlpAmount,
            minAmountOut,
            deadline,
            0, // v
            bytes32(0), // r
            bytes32(0), // s
            user
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              VIEW FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testGetExchangeQuote() public view {
        uint nlpAmount = 1000 * 10 ** 18;

        (uint tokenAmount, uint tokenUsdRate, uint jpyUsdRate, uint exchangeFee, uint operationalFee)
        = exchange.getExchangeQuote(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount);

        assertTrue(tokenAmount > 0);
        assertTrue(tokenUsdRate > 0);
        assertTrue(jpyUsdRate > 0);
        assertTrue(exchangeFee > 0);
        assertTrue(operationalFee > 0);
    }

    function testGetExchangeQuoteWithSlippage() public view {
        uint nlpAmount = 1000 * 10 ** 18;

        (
            uint tokenAmount,
            uint tokenUsdRate,
            uint jpyUsdRate,
            uint exchangeFee,
            uint operationalFee,
            uint minAmountOut,
            uint maxSlippageAmount
        ) = exchange.getExchangeQuoteWithSlippage(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount, 100 // 1% slippage
        );

        assertTrue(tokenAmount > 0);
        assertTrue(tokenUsdRate > 0);
        assertTrue(jpyUsdRate > 0);
        assertTrue(exchangeFee > 0);
        assertTrue(operationalFee > 0);
        assertTrue(minAmountOut > 0);
        assertTrue(maxSlippageAmount > 0);
        assertEq(minAmountOut + maxSlippageAmount, tokenAmount);
    }

    function testGetExternalRoundData() public view {
        // Test all external round data getters
        NLPToMultiTokenKaiaExchangeV2.RoundData memory kaiaData =
            exchange.getKAIAUSDExternalRoundData();
        assertEq(kaiaData.answer, KAIA_USD_PRICE);

        NLPToMultiTokenKaiaExchangeV2.RoundData memory usdcData =
            exchange.getUSDCUSDExternalRoundData();
        assertEq(usdcData.answer, USDC_USD_PRICE);

        NLPToMultiTokenKaiaExchangeV2.RoundData memory usdtData =
            exchange.getUSDTUSDExternalRoundData();
        assertEq(usdtData.answer, USDT_USD_PRICE);

        NLPToMultiTokenKaiaExchangeV2.RoundData memory jpyData =
            exchange.getJPYUSDExternalRoundData();
        assertEq(jpyData.answer, JPY_USD_PRICE);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              WHITELIST MODE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testWhitelistMode() public {
        // Set to whitelist mode
        vm.prank(owner);
        exchange.setExchangeMode(NLPToMultiTokenKaiaExchangeV2.ExchangeMode.WHITELIST);

        // User not whitelisted should fail
        uint nlpAmount = 1000 * 10 ** 18;
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenKaiaExchangeV2.NotWhitelisted.selector, user)
        );
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount);
        vm.stopPrank();

        // Add user to whitelist
        address[] memory accounts = new address[](1);
        bool[] memory whitelisted = new bool[](1);
        accounts[0] = user;
        whitelisted[0] = true;

        vm.prank(whitelistManager);
        exchange.updateWhitelist(accounts, whitelisted);

        // Now user should be able to exchange
        vm.startPrank(user);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount);
        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              ADMIN FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testEmergencyWithdrawKAIA() public {
        uint withdrawAmount = 1 ether;

        // Pause the contract
        vm.prank(emergencyManager);
        exchange.pause();

        uint balanceBefore = feeRecipient.balance;

        vm.prank(emergencyManager);
        exchange.emergencyWithdrawKAIA(withdrawAmount);

        assertEq(feeRecipient.balance, balanceBefore + withdrawAmount);
    }

    function testContractStatus() public view {
        (uint kaiaBalance, bool isPaused, uint jpyUsdPrice) = exchange.getContractStatus();

        assertEq(kaiaBalance, 100 ether);
        assertFalse(isPaused);
        assertTrue(jpyUsdPrice > 0);
    }

    function testOperationalFeeWithdrawal() public {
        uint nlpAmount = 1000 * 10 ** 18; // Reduced to 1000 NLP to fit within contract balance

        // Execute exchange to generate operational fees
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, nlpAmount);
        vm.stopPrank();

        // Check collected fees
        uint collectedFees =
            exchange.getCollectedOperationalFee(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA);
        assertTrue(collectedFees > 0);

        // Withdraw fees
        uint recipientBalanceBefore = feeRecipient.balance;

        vm.prank(feeManager);
        exchange.withdrawOperationalFee(NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, 0); // 0 = withdraw all

        assertEq(feeRecipient.balance, recipientBalanceBefore + collectedFees);
    }

    receive() external payable { }
}

