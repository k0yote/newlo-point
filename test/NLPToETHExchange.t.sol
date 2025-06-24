// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { NLPToETHExchange } from "../src/NLPToETHExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";

contract NLPToETHExchangeTest is Test {
    NLPToETHExchange public exchange;
    NewLoPoint public nlpToken;
    NewLoPointFactory public factory;
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public jpyUsdPriceFeed;

    address public admin = makeAddr("admin");
    address public user1 = makeAddr("user1");
    address public user2 = makeAddr("user2");

    uint8 constant PRICE_FEED_DECIMALS = 8;
    int constant INITIAL_ETH_USD_PRICE = 2000_00000000; // $2000
    int constant INITIAL_JPY_USD_PRICE = 670000; // ¥1 = $0.0067 (8 decimals)
    uint constant INITIAL_ETH_BALANCE = 100 ether;
    uint constant USER_NLP_BALANCE = 10000 * 10 ** 18;

    function setUp() public {
        // Deploy mock price feeds
        ethUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, INITIAL_ETH_USD_PRICE);
        jpyUsdPriceFeed = new MockV3Aggregator(PRICE_FEED_DECIMALS, INITIAL_JPY_USD_PRICE);

        // Deploy NewLoPoint token via factory
        vm.startPrank(admin);
        factory = new NewLoPointFactory();

        bytes32 salt = keccak256("TEST_NLP_TOKEN");

        nlpToken = NewLoPoint(
            factory.deployToken(
                salt,
                admin, // admin role
                admin, // pauser role
                admin // minter role
            )
        );

        // Deploy exchange contract
        exchange = new NLPToETHExchange(
            address(nlpToken), address(ethUsdPriceFeed), address(jpyUsdPriceFeed), admin
        );

        // Fund exchange contract with ETH
        vm.deal(address(exchange), INITIAL_ETH_BALANCE);

        // Setup NLP token for testing
        nlpToken.setTransfersEnabled(true);
        nlpToken.mint(user1, USER_NLP_BALANCE);
        nlpToken.mint(user2, USER_NLP_BALANCE);
        vm.stopPrank();

        // Approve exchange contract to burn user tokens
        vm.prank(user1);
        nlpToken.approve(address(exchange), type(uint).max);

        vm.prank(user2);
        nlpToken.approve(address(exchange), type(uint).max);
    }

    function test_ExchangeNLPToETH_Success() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1,000 NLP
        uint initialUserBalance = user1.balance;
        uint initialContractBalance = address(exchange).balance;
        uint initialNLPBalance = nlpToken.balanceOf(user1);

        vm.prank(user1);
        exchange.exchangeNLPToETH(nlpAmount);

        // Verify NLP tokens were burned
        assertEq(nlpToken.balanceOf(user1), initialNLPBalance - nlpAmount, "NLP tokens not burned");

        // Verify user received ETH
        assertGt(user1.balance, initialUserBalance, "User should receive ETH");

        // Verify contract ETH balance decreased
        assertLt(
            address(exchange).balance,
            initialContractBalance,
            "Contract ETH balance should decrease"
        );

        // Verify statistics updated
        assertEq(exchange.totalExchanged(), nlpAmount, "Total exchanged not updated");
        assertEq(exchange.userExchangeAmount(user1), nlpAmount, "User exchange amount not updated");
    }

    function test_ExchangeQuote() public {
        uint nlpAmount = 1000 * 10 ** 18;

        (uint ethAmount, uint ethUsdRate, uint jpyUsdRate, uint fee) =
            exchange.getExchangeQuote(nlpAmount);

        assertGt(ethAmount, 0, "Should receive ETH");
        assertGt(ethUsdRate, 0, "ETH USD rate should be positive");
        assertGt(jpyUsdRate, 0, "JPY USD rate should be positive");
        assertEq(fee, 0, "Initial fee should be 0");
    }

    function test_RevertWhen_ExchangeZeroAmount() public {
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(NLPToETHExchange.InvalidExchangeAmount.selector, 0));
        exchange.exchangeNLPToETH(0);
    }

    function test_SetExchangeFee() public {
        uint newFee = 250; // 2.5%

        vm.prank(admin);
        exchange.setExchangeFee(newFee);

        assertEq(exchange.exchangeFee(), newFee, "Fee not updated");
    }

    function test_PauseUnpause() public {
        // Test pause
        vm.prank(admin);
        exchange.pause();
        assertTrue(exchange.paused(), "Contract should be paused");

        // Test unpause
        vm.prank(admin);
        exchange.unpause();
        assertFalse(exchange.paused(), "Contract should be unpaused");
    }

    receive() external payable { }
}
