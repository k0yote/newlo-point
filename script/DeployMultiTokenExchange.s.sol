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
    address SONEIUM_ADMIN = vm.envAddress("SONEIUM_ADMIN"); // Replace with actual admin
    address SONEIUM_PRICE_UPDATER = vm.envAddress("SONEIUM_PRICE_UPDATER"); // Replace with actual price updater
    address SONEIUM_FEE_MANAGER = vm.envAddress("SONEIUM_FEE_MANAGER"); // Replace with actual fee manager
    address SONEIUM_EMERGENCY_MANAGER = vm.envAddress("SONEIUM_EMERGENCY_MANAGER"); // Replace with actual emergency manager
    address SONEIUM_CONFIG_MANAGER = vm.envAddress("SONEIUM_CONFIG_MANAGER"); // Replace with actual config manager
    address SONEIUM_FEE_RECIPIENT = vm.envAddress("SONEIUM_FEE_RECIPIENT"); // Replace with actual fee recipient
    address SONEIUM_WHITELIST_MANAGER = vm.envAddress("SONEIUM_WHITELIST_MANAGER"); // Replace with actual whitelist manager

    // Token addresses (Update these with actual addresses)
    address SONEIUM_NLP_TOKEN = vm.envAddress("SONEIUM_NLP_TOKEN"); // Replace with actual NLP token
    address SONEIUM_USDC_TOKEN = vm.envAddress("SONEIUM_USDC_TOKEN"); // Replace with actual USDC
    address SONEIUM_USDT_TOKEN = vm.envAddress("SONEIUM_USDT_TOKEN"); // Replace with actual USDT

    // Oracle addresses (ETH/USD available on Soneium, JPY/USD not available)
    address SONEIUM_JPY_USD_ORACLE = vm.envAddress("SONEIUM_JPY_USD_ORACLE"); // No oracle available on Soneium yet
    address SONEIUM_ETH_USD_ORACLE = vm.envAddress("SONEIUM_ETH_USD_ORACLE"); // Replace with actual ETH/USD oracle on Soneium
    address SONEIUM_USDC_USD_ORACLE = vm.envAddress("SONEIUM_USDC_USD_ORACLE"); // Replace with actual USDC/USD oracle on Soneium
    address SONEIUM_USDT_USD_ORACLE = vm.envAddress("SONEIUM_USDT_USD_ORACLE"); // Replace with actual USDT/USD oracle on Soneium

    // Access control configuration
    string INITIAL_EXCHANGE_MODE = vm.envOr("INITIAL_EXCHANGE_MODE", string("PUBLIC")); // "PUBLIC" or "WHITELIST"

    // Helper function to parse whitelist addresses from environment
    function getInitialWhitelist() internal view returns (address[] memory) {
        string memory whitelistStr = vm.envOr("INITIAL_WHITELIST", string(""));
        if (bytes(whitelistStr).length == 0) {
            return new address[](0);
        }
        // For simplicity, we'll handle this in the deployment script
        // In production, you would parse the comma-separated string
        return new address[](0);
    }

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
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), SONEIUM_WHITELIST_MANAGER);

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

        // Convert 18 decimals to 8 decimals for Chainlink format
        exchange.updateJPYUSDRoundData(
            1, // roundId
            int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );
        // Note: ETH/USDC/USDT prices are now fetched from Chainlink oracles only
        console.log("ETH/USDC/USDT prices will be fetched from Chainlink oracles");
        console.log("WARNING: Ensure oracles are working properly before enabling exchanges!");

        // Configure access control settings
        console.log("Configuring access control...");

        // Set exchange mode
        NLPToMultiTokenExchange.ExchangeMode mode;
        if (keccak256(bytes(INITIAL_EXCHANGE_MODE)) == keccak256(bytes("WHITELIST"))) {
            mode = NLPToMultiTokenExchange.ExchangeMode.WHITELIST;
        } else {
            mode = NLPToMultiTokenExchange.ExchangeMode.PUBLIC;
        }

        exchange.setExchangeMode(mode);
        console.log("Exchange mode set to:", INITIAL_EXCHANGE_MODE);

        // Add initial whitelist if provided
        address[] memory initialWhitelist = getInitialWhitelist();
        if (initialWhitelist.length > 0 && mode == NLPToMultiTokenExchange.ExchangeMode.WHITELIST) {
            bool[] memory whitelisted = new bool[](initialWhitelist.length);
            for (uint i = 0; i < initialWhitelist.length; i++) {
                whitelisted[i] = true;
            }
            exchange.updateWhitelist(initialWhitelist, whitelisted);
            console.log("Initial whitelist configured with", initialWhitelist.length, "addresses");
        }

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
        console.log("Whitelist Manager:", SONEIUM_WHITELIST_MANAGER);
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("Exchange Mode:", INITIAL_EXCHANGE_MODE);
        console.log("Initial Whitelist Count:", initialWhitelist.length);
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

        // Convert 18 decimals to 8 decimals for Chainlink format
        exchange.updateJPYUSDRoundData(
            1, // roundId
            int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );
        // Note: ETH/USDC/USDT prices are now fetched from Chainlink oracles only
        console.log("ETH/USDC/USDT prices will be fetched from Chainlink oracles for local testing");

        // Configure access control for local testing
        console.log("Configuring access control for local testing...");

        // Start with WHITELIST mode for testing
        exchange.setExchangeMode(NLPToMultiTokenExchange.ExchangeMode.WHITELIST);
        console.log("Exchange mode set to: WHITELIST (for testing)");

        // Add deployer to whitelist for testing
        address[] memory testWhitelist = new address[](1);
        testWhitelist[0] = deployer;
        bool[] memory whitelisted = new bool[](1);
        whitelisted[0] = true;
        exchange.updateWhitelist(testWhitelist, whitelisted);
        console.log("Deployer added to whitelist for testing");

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
        console.log("Access Control Settings:");
        console.log("- Exchange Mode: WHITELIST");
        console.log("- Daily Volume Limit: 10,000 NLP");
        console.log("- Whitelisted: deployer");
        console.log("========================================");
        console.log("To test different modes:");
        console.log("1. PUBLIC mode: exchange.setExchangeMode(3)");
        console.log("2. ROLE_BASED mode: exchange.setExchangeMode(2)");
        console.log("3. CLOSED mode: exchange.setExchangeMode(0)");
        console.log("========================================");
    }
}
