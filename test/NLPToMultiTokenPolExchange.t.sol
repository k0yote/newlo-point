// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test, console } from "forge-std/Test.sol";
import { NLPToMultiTokenPolExchange } from "../src/NLPToMultiTokenPolExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title NLPToMultiTokenPolExchange Test Suite
 * @notice Comprehensive tests for Polygon exchange contract with JPYC support
 */
contract NLPToMultiTokenPolExchangeTest is Test {
    NLPToMultiTokenPolExchange public exchange;
    NewLoPoint public nlpToken;
    ERC20DecimalsWithMint public usdcToken;
    ERC20DecimalsWithMint public usdtToken;
    ERC20DecimalsWithMint public jpycToken;

    MockV3Aggregator public maticUsdOracle;
    MockV3Aggregator public jpyUsdOracle;

    address public admin = makeAddr("admin");
    address public user = makeAddr("user");
    address public relayer = makeAddr("relayer");
    address public feeRecipient = makeAddr("feeRecipient");
    address public treasury = makeAddr("treasury");

    // Price feed decimals
    uint8 constant ORACLE_DECIMALS = 8;

    // Initial prices (8 decimals for oracle)
    int constant MATIC_USD_PRICE = 0.5e8; // $0.50
    int constant JPY_USD_PRICE = 0.0067e8; // ~¥150 per USD

    // Test amounts
    uint constant NLP_AMOUNT = 1000 * 1e18; // 1000 NLP
    uint constant JPYC_LIQUIDITY = 1000000 * 1e18; // 1M JPYC
    uint constant USDC_LIQUIDITY = 100000 * 1e6; // 100k USDC
    uint constant MATIC_LIQUIDITY = 100 ether; // 100 MATIC (increased for tests)

    event ExchangeExecuted(
        address indexed user,
        NLPToMultiTokenPolExchange.TokenType indexed tokenType,
        uint nlpAmount,
        uint tokenAmount,
        uint tokenUsdRate,
        uint jpyUsdRate,
        uint exchangeFee,
        uint operationalFee
    );

    function setUp() public {
        vm.startPrank(admin);

        // Deploy NLP token with proxy
        NewLoPoint nlpImpl = new NewLoPoint();
        ProxyAdmin nlpProxyAdmin = new ProxyAdmin(admin);
        bytes memory nlpData =
            abi.encodeWithSelector(nlpImpl.initialize.selector, admin, admin, admin);
        TransparentUpgradeableProxy nlpProxy =
            new TransparentUpgradeableProxy(address(nlpImpl), address(nlpProxyAdmin), nlpData);
        nlpToken = NewLoPoint(address(nlpProxy));

        usdcToken = new ERC20DecimalsWithMint("USD Coin", "USDC", 6);
        usdtToken = new ERC20DecimalsWithMint("Tether USD", "USDT", 6);
        jpycToken = new ERC20DecimalsWithMint("JPY Coin", "JPYC", 18);

        // Deploy mock oracles
        maticUsdOracle = new MockV3Aggregator(ORACLE_DECIMALS, MATIC_USD_PRICE);
        jpyUsdOracle = new MockV3Aggregator(ORACLE_DECIMALS, JPY_USD_PRICE);

        // Deploy exchange contract
        exchange = new NLPToMultiTokenPolExchange(
            address(nlpToken),
            address(maticUsdOracle),
            address(jpyUsdOracle),
            address(0), // No USDC oracle for testing
            address(0), // No USDT oracle for testing
            admin
        );

        // Configure MATIC
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.MATIC,
            address(0),
            address(maticUsdOracle),
            18,
            100, // 1% exchange fee
            false, // Not direct exchange
            "MATIC"
        );

        // Configure USDC
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.USDC,
            address(usdcToken),
            address(0),
            6,
            50, // 0.5% exchange fee
            false, // Not direct exchange
            "USDC"
        );

        // Configure USDT
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.USDT,
            address(usdtToken),
            address(0),
            6,
            75, // 0.75% exchange fee
            false, // Not direct exchange
            "USDT"
        );

        // Configure JPYC (1:1 direct exchange)
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            address(jpycToken),
            address(0), // No oracle needed
            18,
            25, // 0.25% exchange fee
            true, // DIRECT EXCHANGE
            "JPYC"
        );

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            10, // 0.1% operational fee
            feeRecipient,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.MATIC,
            50, // 0.5% operational fee
            feeRecipient,
            true
        );

        // Set treasury
        exchange.setTreasury(treasury);

        // Fund exchange contract
        vm.deal(address(exchange), MATIC_LIQUIDITY);
        jpycToken.mint(address(exchange), JPYC_LIQUIDITY);
        usdcToken.mint(address(exchange), USDC_LIQUIDITY);

        // Mint NLP to user
        nlpToken.mint(user, NLP_AMOUNT * 10);

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            JPYC 1:1 EXCHANGE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_JPYCDirectExchange() public {
        vm.startPrank(user);

        uint nlpAmount = 1000 * 1e18;

        // Approve NLP
        nlpToken.approve(address(exchange), nlpAmount);

        // Get quote before exchange
        (uint expectedAmount,,, uint expectedExchangeFee, uint expectedOpFee) =
            exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        console.log("Expected JPYC amount:", expectedAmount / 1e18);
        console.log("Expected exchange fee:", expectedExchangeFee / 1e18);
        console.log("Expected operational fee:", expectedOpFee / 1e18);

        // Expected calculation:
        // grossAmount = 1000 JPYC (1:1)
        // exchangeFee = 1000 * 0.25% = 2.5 JPYC
        // operationalFee = 1000 * 0.1% = 1 JPYC
        // netAmount = 1000 - 2.5 - 1 = 996.5 JPYC

        assertEq(expectedAmount, 996.5 * 1e18, "Expected amount should be 996.5 JPYC");
        assertEq(expectedExchangeFee, 2.5 * 1e18, "Exchange fee should be 2.5 JPYC");
        assertEq(expectedOpFee, 1 * 1e18, "Operational fee should be 1 JPYC");

        // Execute exchange
        uint balanceBefore = jpycToken.balanceOf(user);

        vm.expectEmit(true, true, false, true);
        emit ExchangeExecuted(
            user,
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            nlpAmount,
            expectedAmount,
            1e18, // tokenUsdRate (1.0 for direct exchange)
            1e18, // jpyUsdRate (1.0 for direct exchange)
            expectedExchangeFee,
            expectedOpFee
        );

        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        uint balanceAfter = jpycToken.balanceOf(user);

        assertEq(balanceAfter - balanceBefore, 996.5 * 1e18, "User should receive 996.5 JPYC");
        assertEq(nlpToken.balanceOf(user), (NLP_AMOUNT * 10) - nlpAmount, "NLP should be burned");

        vm.stopPrank();
    }

    function test_JPYCExchangeNoSlippageRisk() public {
        // JPYC is 1:1, so there's no slippage risk
        vm.startPrank(user);

        uint nlpAmount = 1000 * 1e18;
        nlpToken.approve(address(exchange), nlpAmount);

        // Get quote multiple times - should always be the same
        (uint quote1,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        vm.warp(block.timestamp + 100); // Time passes

        (uint quote2,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        assertEq(quote1, quote2, "JPYC quote should be stable (no oracle dependency)");

        vm.stopPrank();
    }

    function test_JPYCExchangeWithDifferentAmounts() public {
        vm.startPrank(user);

        uint[] memory amounts = new uint[](4);
        amounts[0] = 100 * 1e18; // 100 NLP
        amounts[1] = 500 * 1e18; // 500 NLP
        amounts[2] = 1000 * 1e18; // 1000 NLP
        amounts[3] = 5000 * 1e18; // 5000 NLP

        for (uint i = 0; i < amounts.length; i++) {
            uint nlpAmount = amounts[i];

            // Expected: nlpAmount * (1 - 0.0025 - 0.001) = nlpAmount * 0.9965
            uint expectedJPYC = (nlpAmount * 9965) / 10000;

            (uint quote,,,,) =
                exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

            assertEq(quote, expectedJPYC, "JPYC amount should follow 1:1 ratio with fees");
        }

        vm.stopPrank();
    }

    function test_JPYCExchangeStats() public {
        vm.startPrank(user);

        uint nlpAmount = 1000 * 1e18;
        nlpToken.approve(address(exchange), nlpAmount);

        // Check stats before
        NLPToMultiTokenPolExchange.TokenStats memory statsBefore =
            exchange.getTokenStats(NLPToMultiTokenPolExchange.TokenType.JPYC);

        assertEq(statsBefore.totalExchanged, 0);
        assertEq(statsBefore.totalTokenSent, 0);

        // Execute exchange
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        // Check stats after
        NLPToMultiTokenPolExchange.TokenStats memory stats =
            exchange.getTokenStats(NLPToMultiTokenPolExchange.TokenType.JPYC);

        uint totalExchanged = stats.totalExchanged;
        uint totalSent = stats.totalTokenSent;
        uint totalExchangeFee = stats.totalExchangeFeeCollected;
        uint totalOpFee = stats.totalOperationalFeeCollected;
        uint exchangeCount = stats.exchangeCount;

        assertEq(totalExchanged, nlpAmount, "Total NLP exchanged should match");
        assertEq(totalSent, 996.5 * 1e18, "Total JPYC sent should be 996.5");
        assertEq(totalExchangeFee, 2.5 * 1e18, "Exchange fee collected");
        assertEq(totalOpFee, 1 * 1e18, "Operational fee collected");
        assertEq(exchangeCount, 1, "Exchange count should be 1");

        vm.stopPrank();
    }

    function test_JPYCOperationalFeeWithdrawal() public {
        // First do an exchange to collect fees
        vm.startPrank(user);
        uint nlpAmount = 1000 * 1e18;
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);
        vm.stopPrank();

        // Admin withdraws operational fee
        vm.startPrank(admin);

        uint collectedFee =
            exchange.getCollectedOperationalFee(NLPToMultiTokenPolExchange.TokenType.JPYC);
        assertEq(collectedFee, 1 * 1e18, "Collected operational fee should be 1 JPYC");

        uint balanceBefore = jpycToken.balanceOf(feeRecipient);

        exchange.withdrawOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            0 // Withdraw all
        );

        uint balanceAfter = jpycToken.balanceOf(feeRecipient);
        assertEq(balanceAfter - balanceBefore, 1 * 1e18, "Fee recipient should receive 1 JPYC");

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ORACLE-BASED EXCHANGE TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_MATICExchangeWithOracle() public {
        vm.startPrank(user);

        uint nlpAmount = 1000 * 1e18;
        nlpToken.approve(address(exchange), nlpAmount);

        // Get quote
        (uint expectedAmount, uint tokenUsdRate, uint jpyUsdRate,,) =
            exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.MATIC, nlpAmount);

        console.log("Expected MATIC amount:", expectedAmount);
        console.log("MATIC/USD rate:", tokenUsdRate);
        console.log("JPY/USD rate:", jpyUsdRate);

        // Execute exchange
        uint balanceBefore = address(user).balance;

        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.MATIC, nlpAmount);

        uint balanceAfter = address(user).balance;

        assertGt(balanceAfter, balanceBefore, "User should receive MATIC");
        assertEq(balanceAfter - balanceBefore, expectedAmount, "Should receive expected amount");

        vm.stopPrank();
    }

    function test_OraclePriceUpdate() public {
        vm.startPrank(admin);

        // Update oracle price
        maticUsdOracle.updateAnswer(1e8); // $1.00

        // Get new quote
        (uint newQuote,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.MATIC, 1000 * 1e18);

        // Update oracle again
        maticUsdOracle.updateAnswer(2e8); // $2.00

        (uint newerQuote,,,,) =
            exchange.getExchangeQuote(NLPToMultiTokenPolExchange.TokenType.MATIC, 1000 * 1e18);

        // Higher price = less tokens received
        assertLt(newerQuote, newQuote, "Higher price should result in fewer tokens");

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            GASLESS EXCHANGE (PERMIT) TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_JPYCExchangeWithPermit() public {
        // Setup user private key for signing
        uint userPrivateKey = 0x1234;
        address userAddr = vm.addr(userPrivateKey);

        // Mint NLP to the user
        vm.prank(admin);
        nlpToken.mint(userAddr, 1000 * 1e18);

        uint nlpAmount = 1000 * 1e18;
        uint deadline = block.timestamp + 1 hours;

        // Create permit signature
        bytes32 permitHash = keccak256(
            abi.encodePacked(
                "\x19\x01",
                nlpToken.DOMAIN_SEPARATOR(),
                keccak256(
                    abi.encode(
                        keccak256(
                            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
                        ),
                        userAddr,
                        address(exchange),
                        nlpAmount,
                        nlpToken.nonces(userAddr),
                        deadline
                    )
                )
            )
        );

        (uint8 v, bytes32 r, bytes32 s) = vm.sign(userPrivateKey, permitHash);

        // Relayer executes gasless exchange
        vm.prank(relayer);

        uint balanceBefore = jpycToken.balanceOf(userAddr);

        exchange.exchangeNLPWithPermit(
            NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount, deadline, v, r, s, userAddr
        );

        uint balanceAfter = jpycToken.balanceOf(userAddr);

        assertEq(
            balanceAfter - balanceBefore, 996.5 * 1e18, "User should receive 996.5 JPYC via permit"
        );
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ACCESS CONTROL TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_WhitelistMode() public {
        vm.startPrank(admin);

        // Set to whitelist mode
        exchange.setExchangeMode(NLPToMultiTokenPolExchange.ExchangeMode.WHITELIST);

        vm.stopPrank();

        // User tries to exchange (not whitelisted)
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenPolExchange.NotWhitelisted.selector, user)
        );
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, 1000 * 1e18);

        vm.stopPrank();

        // Admin adds user to whitelist
        vm.startPrank(admin);
        address[] memory accounts = new address[](1);
        accounts[0] = user;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;

        exchange.updateWhitelist(accounts, whitelisted);
        vm.stopPrank();

        // User can now exchange
        vm.startPrank(user);
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, 1000 * 1e18);
        vm.stopPrank();
    }

    function test_EmergencyPause() public {
        vm.startPrank(admin);
        exchange.pause();
        vm.stopPrank();

        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 1e18);

        // OpenZeppelin Pausable v5.x uses custom errors
        vm.expectRevert(abi.encodeWithSignature("EnforcedPause()"));
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, 1000 * 1e18);

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            ERROR HANDLING TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_RevertInsufficientBalance() public {
        // Drain JPYC from exchange
        vm.prank(admin);
        exchange.pause();

        vm.prank(admin);
        exchange.emergencyWithdrawToken(NLPToMultiTokenPolExchange.TokenType.JPYC, JPYC_LIQUIDITY);

        vm.prank(admin);
        exchange.unpause();

        // Try to exchange
        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 1e18);

        vm.expectRevert();
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, 1000 * 1e18);

        vm.stopPrank();
    }

    function test_RevertZeroAmount() public {
        vm.startPrank(user);

        vm.expectRevert(
            abi.encodeWithSelector(NLPToMultiTokenPolExchange.InvalidExchangeAmount.selector, 0)
        );
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, 0);

        vm.stopPrank();
    }

    function test_RevertTokenNotEnabled() public {
        // Disable JPYC
        vm.prank(admin);
        exchange.setTokenEnabled(NLPToMultiTokenPolExchange.TokenType.JPYC, false);

        vm.startPrank(user);
        nlpToken.approve(address(exchange), 1000 * 1e18);

        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToMultiTokenPolExchange.TokenNotEnabled.selector,
                NLPToMultiTokenPolExchange.TokenType.JPYC
            )
        );
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, 1000 * 1e18);

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            FUZZ TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function testFuzz_JPYCExchange(uint nlpAmount) public {
        // Bound amount to reasonable range (avoid extreme values for precision)
        nlpAmount = bound(nlpAmount, 100 * 1e18, 10000 * 1e18);

        // Ensure user has enough NLP
        vm.prank(admin);
        nlpToken.mint(user, nlpAmount);

        // Ensure exchange has enough JPYC
        uint requiredJPYC = (nlpAmount * 9965) / 10000 + 1; // Add buffer
        if (jpycToken.balanceOf(address(exchange)) < requiredJPYC) {
            vm.prank(admin);
            jpycToken.mint(address(exchange), requiredJPYC);
        }

        vm.startPrank(user);
        nlpToken.approve(address(exchange), nlpAmount);

        uint balanceBefore = jpycToken.balanceOf(user);

        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        uint balanceAfter = jpycToken.balanceOf(user);
        uint received = balanceAfter - balanceBefore;

        // Verify 1:1 ratio with fees (0.35% total fees) - allow for minor rounding
        uint expected = (nlpAmount * 9965) / 10000;
        assertApproxEqAbs(received, expected, 2, "Fuzz: JPYC amount should match 1:1 with fees");

        vm.stopPrank();
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            VIEW FUNCTION TESTS
    ═══════════════════════════════════════════════════════════════════════ */

    function test_GetTokenConfig() public view {
        NLPToMultiTokenPolExchange.TokenConfig memory config =
            exchange.getTokenConfig(NLPToMultiTokenPolExchange.TokenType.JPYC);

        assertEq(config.tokenAddress, address(jpycToken));
        assertEq(config.decimals, 18);
        assertEq(config.exchangeFee, 25);
        assertTrue(config.isEnabled);
        assertFalse(config.hasOracle);
        assertTrue(config.isDirectExchange);
        assertEq(config.symbol, "JPYC");
    }

    function test_GetUserExchangeHistory() public {
        vm.startPrank(user);

        uint nlpAmount = 1000 * 1e18;
        nlpToken.approve(address(exchange), nlpAmount);
        exchange.exchangeNLP(NLPToMultiTokenPolExchange.TokenType.JPYC, nlpAmount);

        (uint exchangedNLP, uint receivedTokens) =
            exchange.getUserExchangeHistory(user, NLPToMultiTokenPolExchange.TokenType.JPYC);

        assertEq(exchangedNLP, nlpAmount);
        assertEq(receivedTokens, 996.5 * 1e18);

        vm.stopPrank();
    }

    function test_GetContractStatus() public view {
        (uint maticBalance, bool isPaused, uint jpyUsdPrice) = exchange.getContractStatus();

        assertEq(maticBalance, MATIC_LIQUIDITY);
        assertFalse(isPaused);
        assertGt(jpyUsdPrice, 0);
    }

    receive() external payable { }
}
