// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenExchange } from "../src/NLPToMultiTokenExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

/**
 * @title DeployMultiTokenExchange
 * @dev Deployment script for NLPToMultiTokenExchange contract
 */
contract DeployMultiTokenExchange is Script {
    // Soneium mainnet addresses (Update these with actual addresses)
    address constant SONEIUM_ADMIN = 0x742D35Cc6634c0532925a3b8d91d9128d0c9C3E1; // Replace with actual admin
    address constant SONEIUM_PRICE_UPDATER = 0x742d35CC6634C0532925a3B8d91D9128d0c9c3e2; // Replace with actual price updater
    address constant SONEIUM_FEE_MANAGER = 0x742D35CC6634c0532925A3B8D91d9128D0C9c3E3; // Replace with actual fee manager
    address constant SONEIUM_EMERGENCY_MANAGER = 0x742d35CC6634C0532925A3b8d91d9128D0c9c3E4; // Replace with actual emergency manager
    address constant SONEIUM_CONFIG_MANAGER = 0x742d35cC6634c0532925a3b8D91D9128D0C9C3E5; // Replace with actual config manager
    address constant SONEIUM_FEE_RECIPIENT = 0x742d35CC6634c0532925a3B8d91d9128D0c9c3E6; // Replace with actual fee recipient

    // Token addresses (Update these with actual addresses)
    address constant SONEIUM_NLP_TOKEN = 0x0000000000000000000000000000000000000000; // Replace with actual NLP token
    address constant SONEIUM_USDC_TOKEN = 0x0000000000000000000000000000000000000000; // Replace with actual USDC
    address constant SONEIUM_USDT_TOKEN = 0x0000000000000000000000000000000000000000; // Replace with actual USDT

    // Oracle addresses (ETH/USD available on Soneium, JPY/USD not available)
    address constant SONEIUM_JPY_USD_ORACLE = address(0); // No oracle available on Soneium yet
    address constant SONEIUM_ETH_USD_ORACLE = 0x0000000000000000000000000000000000000000; // Replace with actual ETH/USD oracle on Soneium
    address constant SONEIUM_USDC_USD_ORACLE = 0x0000000000000000000000000000000000000000; // Replace with actual USDC/USD oracle on Soneium
    address constant SONEIUM_USDT_USD_ORACLE = 0x0000000000000000000000000000000000000000; // Replace with actual USDT/USD oracle on Soneium

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenExchange on Soneium...");
        console.log("Deployer:", deployer);

        // Validate addresses before deployment
        require(SONEIUM_ADMIN != address(0), "Admin address cannot be zero");
        require(SONEIUM_PRICE_UPDATER != address(0), "Price updater address cannot be zero");
        require(SONEIUM_FEE_MANAGER != address(0), "Fee manager address cannot be zero");
        require(SONEIUM_EMERGENCY_MANAGER != address(0), "Emergency manager address cannot be zero");
        require(SONEIUM_CONFIG_MANAGER != address(0), "Config manager address cannot be zero");
        require(SONEIUM_FEE_RECIPIENT != address(0), "Fee recipient address cannot be zero");
        require(SONEIUM_NLP_TOKEN != address(0), "NLP token address cannot be zero");
        require(SONEIUM_USDC_TOKEN != address(0), "USDC token address cannot be zero");
        require(SONEIUM_USDT_TOKEN != address(0), "USDT token address cannot be zero");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the exchange contract
        NLPToMultiTokenExchange exchange = new NLPToMultiTokenExchange(
            SONEIUM_NLP_TOKEN,
            SONEIUM_ETH_USD_ORACLE,
            SONEIUM_JPY_USD_ORACLE,
            SONEIUM_USDC_USD_ORACLE,
            SONEIUM_USDT_USD_ORACLE,
            SONEIUM_ADMIN
        );

        console.log("NLPToMultiTokenExchange deployed at:", address(exchange));

        // Grant roles to designated addresses
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), SONEIUM_PRICE_UPDATER);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), SONEIUM_FEE_MANAGER);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), SONEIUM_EMERGENCY_MANAGER);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), SONEIUM_CONFIG_MANAGER);

        console.log("Roles granted successfully");

        // Configure ETH token
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH,
            address(0), // ETH
            SONEIUM_ETH_USD_ORACLE,
            18,
            100, // 1% exchange fee
            "ETH"
        );

        // Configure USDC token
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDC,
            SONEIUM_USDC_TOKEN,
            SONEIUM_USDC_USD_ORACLE,
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        // Configure USDT token
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDT,
            SONEIUM_USDT_TOKEN,
            SONEIUM_USDT_USD_ORACLE,
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            50, // 0.5% operational fee
            SONEIUM_FEE_RECIPIENT,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDC,
            25, // 0.25% operational fee
            SONEIUM_FEE_RECIPIENT,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDT,
            30, // 0.3% operational fee
            SONEIUM_FEE_RECIPIENT,
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external prices (since oracles are not available on Soneium)
        // WARNING: These prices are for deployment only and MUST be updated immediately
        // with current market prices before enabling exchanges

        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD
        uint ethUsdPrice = 2500e18; // 1 ETH = 2500 USD
        uint usdcUsdPrice = 1e18; // 1 USDC = 1 USD
        uint usdtUsdPrice = 1e18; // 1 USDT = 1 USD

        // Validate price values
        require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");
        require(ethUsdPrice > 0, "ETH/USD price must be greater than zero");
        require(usdcUsdPrice > 0, "USDC/USD price must be greater than zero");
        require(usdtUsdPrice > 0, "USDT/USD price must be greater than zero");

        exchange.updateJPYUSDExternalPrice(jpyUsdPrice);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, ethUsdPrice);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.USDC, usdcUsdPrice);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.USDT, usdtUsdPrice);

        console.log("Initial external prices set");
        console.log("WARNING: Update prices with current market values before enabling exchanges!");

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("========================================");
        console.log("Contract Address:", address(exchange));
        console.log("Admin:", SONEIUM_ADMIN);
        console.log("Price Updater:", SONEIUM_PRICE_UPDATER);
        console.log("Fee Manager:", SONEIUM_FEE_MANAGER);
        console.log("Emergency Manager:", SONEIUM_EMERGENCY_MANAGER);
        console.log("Config Manager:", SONEIUM_CONFIG_MANAGER);
        console.log("Fee Recipient:", SONEIUM_FEE_RECIPIENT);
        console.log("========================================");
        console.log("Next steps:");
        console.log("1. Update token addresses in script if needed");
        console.log("2. Fund the contract with ETH, USDC, and USDT");
        console.log("3. Set up automated price updates");
        console.log("4. Configure monitoring and alerts");
        console.log("5. Update external price data regularly");
    }
}

/**
 * @title DeployMultiTokenExchangeLocal
 * @dev Local deployment script for testing
 */
contract DeployMultiTokenExchangeLocal is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenExchange locally...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock NLP token
        NewLoPoint nlpToken = new NewLoPoint();
        nlpToken.initialize(deployer, deployer, deployer);

        // Deploy mock USDC token
        ERC20DecimalsWithMint usdcToken = new ERC20DecimalsWithMint("USD Coin", "USDC", 6);

        // Deploy mock USDT token
        ERC20DecimalsWithMint usdtToken = new ERC20DecimalsWithMint("Tether USD", "USDT", 6);

        console.log("Mock tokens deployed");
        console.log("NLP Token:", address(nlpToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("USDT Token:", address(usdtToken));

        // Deploy the exchange contract
        NLPToMultiTokenExchange exchange = new NLPToMultiTokenExchange(
            address(nlpToken),
            address(0), // No ETH/USD oracle in local test
            address(0), // No JPY/USD oracle
            address(0), // No USDC/USD oracle in local test
            address(0), // No USDT/USD oracle in local test
            deployer
        );

        console.log("NLPToMultiTokenExchange deployed at:", address(exchange));

        // Configure ETH token
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH,
            address(0), // ETH
            address(0), // No oracle
            18,
            100, // 1% exchange fee
            "ETH"
        );

        // Configure USDC token
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDC,
            address(usdcToken),
            address(0), // No oracle
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        // Configure USDT token
        exchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDT,
            address(usdtToken),
            address(0), // No oracle
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            50, // 0.5% operational fee
            deployer, // Fee recipient
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDC,
            25, // 0.25% operational fee
            deployer, // Fee recipient
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDT,
            30, // 0.3% operational fee
            deployer, // Fee recipient
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external prices for local testing
        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD
        uint ethUsdPrice = 2500e18; // 1 ETH = 2500 USD
        uint usdcUsdPrice = 1e18; // 1 USDC = 1 USD
        uint usdtUsdPrice = 1e18; // 1 USDT = 1 USD

        // Validate price values
        require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");
        require(ethUsdPrice > 0, "ETH/USD price must be greater than zero");
        require(usdcUsdPrice > 0, "USDC/USD price must be greater than zero");
        require(usdtUsdPrice > 0, "USDT/USD price must be greater than zero");

        exchange.updateJPYUSDExternalPrice(jpyUsdPrice);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.ETH, ethUsdPrice);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.USDC, usdcUsdPrice);
        exchange.updateExternalPrice(NLPToMultiTokenExchange.TokenType.USDT, usdtUsdPrice);

        console.log("Initial external prices set for local testing");

        // Fund the exchange contract with test liquidity
        uint ethAmount = 10 ether;
        uint usdcAmount = 100000 * 10 ** 6; // 100k USDC
        uint usdtAmount = 100000 * 10 ** 6; // 100k USDT

        vm.deal(address(exchange), ethAmount);

        // Mint tokens to exchange contract
        usdcToken.mint(address(exchange), usdcAmount);
        usdtToken.mint(address(exchange), usdtAmount);

        console.log("Exchange contract funded with test liquidity:");
        console.log("ETH:", ethAmount / 1e18, "ETH");
        console.log("USDC:", usdcAmount / 1e6, "USDC");
        console.log("USDT:", usdtAmount / 1e6, "USDT");

        // Verify funding
        require(address(exchange).balance >= ethAmount, "ETH funding failed");
        require(usdcToken.balanceOf(address(exchange)) >= usdcAmount, "USDC funding failed");
        require(usdtToken.balanceOf(address(exchange)) >= usdtAmount, "USDT funding failed");

        vm.stopBroadcast();

        console.log("Local deployment completed successfully!");
        console.log("========================================");
        console.log("Exchange Contract:", address(exchange));
        console.log("NLP Token:", address(nlpToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("USDT Token:", address(usdtToken));
        console.log("Admin/Owner:", deployer);
        console.log("========================================");
    }
}
