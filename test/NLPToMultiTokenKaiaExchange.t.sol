// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenKaiaExchange } from "../src/NLPToMultiTokenKaiaExchange.sol";
import { IERC20Extended } from "../src/interfaces/IERC20Extended.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";
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

contract NLPToMultiTokenKaiaExchangeTest is Test {
    // Event declarations for testing
    event ExchangeModeUpdated(
        NLPToMultiTokenKaiaExchange.ExchangeMode oldMode,
        NLPToMultiTokenKaiaExchange.ExchangeMode newMode,
        address updatedBy
    );

    NLPToMultiTokenKaiaExchange public exchange;
    MockNLPTokenKaia public nlpToken;
    MockTokenKaia public usdcToken;
    MockTokenKaia public usdtToken;

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

    // Mock price data (8 decimals like Chainlink)
    int public constant JPY_USD_PRICE = 677093; // 1 JPY = 0.00677093 USD (actual data)
    int public constant KAIA_USD_PRICE = 15000000; // 1 KAIA = 0.15 USD
    int public constant USDC_USD_PRICE = 99971995; // 1 USDC = 1 USD
    int public constant USDT_USD_PRICE = 1e8; // 1 USDT = 1 USD

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

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock tokens
        nlpToken = new MockNLPTokenKaia();
        usdcToken = new MockTokenKaia("USD Coin", "USDC", 6);
        usdtToken = new MockTokenKaia("Tether USD", "USDT", 6);

        // Deploy exchange contract
        exchange = new NLPToMultiTokenKaiaExchange(address(nlpToken), owner);

        // Grant roles
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), priceUpdater);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), feeManager);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), emergencyManager);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), configManager);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), whitelistManager);

        // Set treasury
        exchange.setTreasury(feeRecipient);

        // Configure tokens
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0),
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            address(usdcToken),
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            address(usdtToken),
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

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

        // Update price data
        _updatePriceData();

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

    function _updatePriceData() internal {
        uint currentTime = block.timestamp;

        exchange.updateJPYUSDRoundData(1, JPY_USD_PRICE, currentTime, currentTime, 1);

        exchange.updateKAIAUSDRoundData(1, KAIA_USD_PRICE, currentTime, currentTime, 1);

        exchange.updateUSDCUSDRoundData(1, USDC_USD_PRICE, currentTime, currentTime, 1);

        exchange.updateUSDTUSDRoundData(1, USDT_USD_PRICE, currentTime, currentTime, 1);
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
        assertEq(config.symbol, "KAIA");
    }

    function testPriceUpdates() public view {
        // Test JPY/USD price
        uint jpyPrice = exchange.getLatestJPYPrice();
        assertEq(jpyPrice, uint(JPY_USD_PRICE) * 1e10); // Convert 8->18 decimals

        // Test KAIA/USD price
        uint kaiaPrice = exchange.getLatestKAIAPrice();
        assertEq(kaiaPrice, uint(KAIA_USD_PRICE) * 1e10);

        // Test USDC/USD price
        uint usdcPrice = exchange.getLatestUSDCPrice();
        assertEq(usdcPrice, uint(USDC_USD_PRICE) * 1e10);

        // Test USDT/USD price
        uint usdtPrice = exchange.getLatestUSDTPrice();
        assertEq(usdtPrice, uint(USDT_USD_PRICE) * 1e10);
    }

    function testBasicExchangeKAIA() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint userBalanceBefore = user.balance;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.KAIA, nlpAmount);
        vm.stopPrank();

        assertEq(nlpToken.balanceOf(user), 100000 * 10 ** 18 - nlpAmount);
        assertTrue(user.balance > userBalanceBefore);
    }

    function testBasicExchangeUSDC() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint userBalanceBefore = usdcToken.balanceOf(user);

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.USDC, nlpAmount);
        vm.stopPrank();

        assertEq(nlpToken.balanceOf(user), 100000 * 10 ** 18 - nlpAmount);
        assertTrue(usdcToken.balanceOf(user) > userBalanceBefore);
    }

    function testBasicExchangeUSDT() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint userBalanceBefore = usdtToken.balanceOf(user);

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.USDT, nlpAmount);
        vm.stopPrank();

        assertEq(nlpToken.balanceOf(user), 100000 * 10 ** 18 - nlpAmount);
        assertTrue(usdtToken.balanceOf(user) > userBalanceBefore);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                          OPERATIONAL FEE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testOperationalFeeCollection() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint feeRecipientBalanceBefore = feeRecipient.balance;

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.KAIA, nlpAmount);
        vm.stopPrank();

        // Check that operational fees were collected
        uint collectedFee =
            exchange.getCollectedOperationalFee(NLPToMultiTokenKaiaExchange.TokenType.KAIA);
        assertTrue(collectedFee > 0);

        // Withdraw operational fees
        vm.prank(feeManager);
        exchange.withdrawOperationalFee(NLPToMultiTokenKaiaExchange.TokenType.KAIA, 0);

        // Check that fees were sent to recipient
        assertTrue(feeRecipient.balance > feeRecipientBalanceBefore);
        assertEq(exchange.getCollectedOperationalFee(NLPToMultiTokenKaiaExchange.TokenType.KAIA), 0);
    }

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

    function testExchangeWithSlippageProtection() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint slippageTolerance = 100; // 1%

        // Get quote first
        (uint minAmountOut, uint quoteAmount) = exchange.calculateMinAmountOut(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA, nlpAmount, slippageTolerance
        );

        uint initialUserBalance = user.balance;
        uint initialNLPBalance = nlpToken.balanceOf(user);

        // Execute exchange with slippage protection
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLPWithSlippage(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA, nlpAmount, minAmountOut
        );
        vm.stopPrank();

        // Verify exchange was successful
        assertEq(nlpToken.balanceOf(user), initialNLPBalance - nlpAmount, "NLP tokens not burned");
        assertGe(
            user.balance, initialUserBalance + minAmountOut, "User didn't receive minimum amount"
        );
        assertLe(user.balance, initialUserBalance + quoteAmount, "User received more than expected");
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
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
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

    function testWhitelistMode() public {
        // Set mode to WHITELIST
        vm.prank(configManager);
        exchange.setExchangeMode(NLPToMultiTokenKaiaExchange.ExchangeMode.WHITELIST);

        // Non-whitelisted user should fail
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 10 ** 18);
        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenKaiaExchange.NotWhitelisted.selector, user)
        );
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.KAIA, 1000 * 10 ** 18);
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
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.KAIA, 1000 * 10 ** 18);
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
        ) = exchange.getExchangeQuote(NLPToMultiTokenKaiaExchange.TokenType.KAIA, nlpAmount);

        assertTrue(tokenAmount > 0);
        assertTrue(tokenUsdRate > 0);
        assertTrue(jpyUsdRate > 0);
        assertTrue(exchangeFee >= 0);
        assertTrue(operationalFee >= 0);

        // Execute exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenKaiaExchange.TokenType.KAIA, nlpAmount);
        vm.stopPrank();

        // Verify statistics
        NLPToMultiTokenKaiaExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenKaiaExchange.TokenType.KAIA);

        assertEq(stats.totalExchanged, nlpAmount);
        assertEq(stats.exchangeCount, 1);
    }

    function testContractStatus() public view {
        (uint kaiaBalance, bool isPaused, uint jpyUsdPrice) = exchange.getContractStatus();

        assertEq(kaiaBalance, 100 ether);
        assertFalse(isPaused);
        assertTrue(jpyUsdPrice > 0);
    }

    receive() external payable { }
}
