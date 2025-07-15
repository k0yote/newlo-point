// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Test } from "forge-std/Test.sol";
import { NLPToETHExchange } from "../src/NLPToETHExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";

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
    int constant INITIAL_JPY_USD_PRICE = 677093; // ¥1 = $0.00677093 (8 decimals) - actual Chainlink data
    uint constant INITIAL_ETH_BALANCE = 100 ether;
    uint constant USER_NLP_BALANCE = 10000 * 10 ** 18;

    address public owner = address(0x1);
    address public relayer = address(0x3);

    // Permit signature parameters
    uint userPrivateKey = 0x123;
    address userAddress;

    function setUp() public {
        // Calculate user address from private key
        userAddress = vm.addr(userPrivateKey);

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

        // Deploy token implementation and proxy
        NewLoPoint impl = new NewLoPoint();
        ProxyAdmin adminProxy = new ProxyAdmin(owner);

        bytes memory initData = abi.encodeWithSelector(
            impl.initialize.selector,
            admin, // admin
            admin, // pauser
            admin // minter
        );

        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(adminProxy), initData);

        nlpToken = NewLoPoint(address(proxy));

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
        nlpToken.mint(userAddress, USER_NLP_BALANCE); // Mint for permit test user
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

    /**
     * @notice Test permit-based gasless exchange functionality
     */
    function testExchangeNLPToETHWithPermit() public {
        uint nlpAmount = 1000 * 10 ** 18; // 1000 NLP
        uint deadline = block.timestamp + 1 hours;

        // Calculate expected ETH amount
        uint ethUsdPrice = uint(INITIAL_ETH_USD_PRICE) * 10 ** 10; // Convert to 18 decimals
        uint jpyUsdPrice = uint(INITIAL_JPY_USD_PRICE) * 10 ** 10; // Convert to 18 decimals
        uint expectedEthAmount = (nlpAmount * jpyUsdPrice) / ethUsdPrice;

        // Create permit signature
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            userAddress, address(exchange), nlpAmount, deadline, userPrivateKey
        );

        // Record initial balances
        uint initialUserBalance = userAddress.balance;
        uint initialNLPBalance = nlpToken.balanceOf(userAddress);

        // Execute gasless exchange via relayer
        vm.prank(relayer);
        exchange.exchangeNLPToETHWithPermit(nlpAmount, deadline, v, r, s, userAddress);

        // Verify results
        assertEq(nlpToken.balanceOf(userAddress), initialNLPBalance - nlpAmount, "NLP not burned");
        assertEq(userAddress.balance, initialUserBalance + expectedEthAmount, "ETH not received");

        // Verify statistics updated
        assertEq(exchange.totalExchanged(), nlpAmount, "Total exchanged not updated");
        assertEq(
            exchange.userExchangeAmount(userAddress), nlpAmount, "User exchange amount not updated"
        );
    }

    /**
     * @notice Test permit signature validation
     */
    function testPermitSignatureValidation() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;

        // Create invalid signature (wrong private key)
        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            userAddress,
            address(exchange),
            nlpAmount,
            deadline,
            0x456 // Wrong private key
        );

        // Should revert with permit failed
        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToETHExchange.PermitFailed.selector, userAddress, nlpAmount, deadline
            )
        );
        exchange.exchangeNLPToETHWithPermit(nlpAmount, deadline, v, r, s, userAddress);
    }

    /**
     * @notice Test expired permit
     */
    function testExpiredPermit() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp - 1; // Expired deadline

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            userAddress, address(exchange), nlpAmount, deadline, userPrivateKey
        );

        vm.prank(relayer);
        vm.expectRevert(
            abi.encodeWithSelector(
                NLPToETHExchange.PermitFailed.selector, userAddress, nlpAmount, deadline
            )
        );
        exchange.exchangeNLPToETHWithPermit(nlpAmount, deadline, v, r, s, userAddress);
    }

    /**
     * @notice Test gasless exchange event emission
     */
    function testGaslessExchangeEvent() public {
        uint nlpAmount = 1000 * 10 ** 18;
        uint deadline = block.timestamp + 1 hours;

        (uint8 v, bytes32 r, bytes32 s) = _createPermitSignature(
            userAddress, address(exchange), nlpAmount, deadline, userPrivateKey
        );

        // Calculate expected ETH amount
        uint ethUsdPrice = uint(INITIAL_ETH_USD_PRICE) * 10 ** 10; // Convert to 18 decimals
        uint jpyUsdPrice = uint(INITIAL_JPY_USD_PRICE) * 10 ** 10; // Convert to 18 decimals
        uint expectedEthAmount = (nlpAmount * jpyUsdPrice) / ethUsdPrice;

        // Expect GaslessExchangeExecuted event
        vm.expectEmit(true, true, false, true);
        emit NLPToETHExchange.GaslessExchangeExecuted(
            userAddress, // user
            relayer, // relayer
            nlpAmount, // nlp amount
            expectedEthAmount, // expected eth amount (calculated)
            ethUsdPrice, // eth rate
            jpyUsdPrice, // jpy rate
            0 // fee (0% initially)
        );

        vm.prank(relayer);
        exchange.exchangeNLPToETHWithPermit(nlpAmount, deadline, v, r, s, userAddress);
    }

    /**
     * @notice Helper function to create permit signature
     */
    function _createPermitSignature(
        address tokenOwner,
        address spender,
        uint value,
        uint deadline,
        uint privateKey
    ) internal view returns (uint8 v, bytes32 r, bytes32 s) {
        bytes32 domainSeparator = nlpToken.DOMAIN_SEPARATOR();
        bytes32 typeHash = keccak256(
            "Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)"
        );

        uint nonce = nlpToken.nonces(tokenOwner);

        bytes32 structHash =
            keccak256(abi.encode(typeHash, tokenOwner, spender, value, nonce, deadline));

        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", domainSeparator, structHash));

        return vm.sign(privateKey, digest);
    }

    receive() external payable { }
}
