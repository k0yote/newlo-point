// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenKaiaExchange } from "../src/NLPToMultiTokenKaiaExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

/**
 * @title DeployKaiaExchange
 * @dev Deployment script for NLPToMultiTokenKaiaExchange contract on Kaia blockchain
 */
contract DeployKaiaExchange is Script {
    // Kaia mainnet addresses (Update these with actual addresses)
    address KAIA_ADMIN = vm.envAddress("KAIA_ADMIN"); // Replace with actual admin
    address KAIA_PRICE_UPDATER = vm.envAddress("KAIA_PRICE_UPDATER"); // Replace with actual price updater
    address KAIA_FEE_MANAGER = vm.envAddress("KAIA_FEE_MANAGER"); // Replace with actual fee manager
    address KAIA_EMERGENCY_MANAGER = vm.envAddress("KAIA_EMERGENCY_MANAGER"); // Replace with actual emergency manager
    address KAIA_CONFIG_MANAGER = vm.envAddress("KAIA_CONFIG_MANAGER"); // Replace with actual config manager
    address KAIA_FEE_RECIPIENT = vm.envAddress("KAIA_FEE_RECIPIENT"); // Replace with actual fee recipient
    address KAIA_WHITELIST_MANAGER = vm.envAddress("KAIA_WHITELIST_MANAGER"); // Replace with actual whitelist manager

    // Token addresses (Update these with actual addresses)
    address KAIA_NLP_TOKEN = vm.envAddress("KAIA_NLP_TOKEN"); // Replace with actual NLP token
    address KAIA_USDC_TOKEN = vm.envAddress("KAIA_USDC_TOKEN"); // Replace with actual USDC
    address KAIA_USDT_TOKEN = vm.envAddress("KAIA_USDT_TOKEN"); // Replace with actual USDT

    // Treasury address for emergency withdrawals
    address KAIA_TREASURY = vm.envAddress("KAIA_TREASURY"); // Replace with actual treasury

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

        console.log("Deploying NLPToMultiTokenKaiaExchange on Kaia blockchain...");
        console.log("Deployer:", deployer);

        // Validate addresses before deployment
        require(KAIA_ADMIN != address(0), "Admin address cannot be zero");
        require(KAIA_PRICE_UPDATER != address(0), "Price updater address cannot be zero");
        require(KAIA_FEE_MANAGER != address(0), "Fee manager address cannot be zero");
        require(KAIA_EMERGENCY_MANAGER != address(0), "Emergency manager address cannot be zero");
        require(KAIA_CONFIG_MANAGER != address(0), "Config manager address cannot be zero");
        require(KAIA_FEE_RECIPIENT != address(0), "Fee recipient address cannot be zero");
        require(KAIA_NLP_TOKEN != address(0), "NLP token address cannot be zero");
        require(KAIA_USDC_TOKEN != address(0), "USDC token address cannot be zero");
        require(KAIA_USDT_TOKEN != address(0), "USDT token address cannot be zero");
        require(KAIA_TREASURY != address(0), "Treasury address cannot be zero");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the exchange contract
        NLPToMultiTokenKaiaExchange exchange =
            new NLPToMultiTokenKaiaExchange(KAIA_NLP_TOKEN, KAIA_ADMIN);

        console.log("NLPToMultiTokenKaiaExchange deployed at:", address(exchange));

        // Set treasury address
        exchange.setTreasury(KAIA_TREASURY);

        // Grant roles to designated addresses
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), KAIA_PRICE_UPDATER);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), KAIA_FEE_MANAGER);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), KAIA_EMERGENCY_MANAGER);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), KAIA_CONFIG_MANAGER);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), KAIA_WHITELIST_MANAGER);

        console.log("Roles granted successfully");

        // Configure KAIA token
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        // Configure USDC token
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            KAIA_USDC_TOKEN,
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        // Configure USDT token
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            KAIA_USDT_TOKEN,
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            50, // 0.5% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            25, // 0.25% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            30, // 0.3% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external prices
        // WARNING: These prices are for deployment only and MUST be updated immediately
        // with current market prices before enabling exchanges

        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD (example price)
        uint kaiaUsdPrice = 0.15e18; // 1 KAIA = 0.15 USD (example price)
        uint usdcUsdPrice = 1e18; // 1 USDC = 1 USD
        uint usdtUsdPrice = 1e18; // 1 USDT = 1 USD

        // Validate price values
        require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");
        require(kaiaUsdPrice > 0, "KAIA/USD price must be greater than zero");
        require(usdcUsdPrice > 0, "USDC/USD price must be greater than zero");
        require(usdtUsdPrice > 0, "USDT/USD price must be greater than zero");

        // Convert 18 decimals to 8 decimals for Chainlink format and set external prices
        exchange.updateJPYUSDRoundData(
            1, // roundId
            int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        exchange.updateKAIAUSDRoundData(
            1, // roundId
            int(kaiaUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        exchange.updateUSDCUSDRoundData(
            1, // roundId
            int(usdcUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        exchange.updateUSDTUSDRoundData(
            1, // roundId
            int(usdtUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        console.log("Initial price data set (WARNING: Update with current prices!)");

        // Configure access control settings
        console.log("Configuring access control...");

        // Set exchange mode
        NLPToMultiTokenKaiaExchange.ExchangeMode mode;
        if (keccak256(bytes(INITIAL_EXCHANGE_MODE)) == keccak256(bytes("WHITELIST"))) {
            mode = NLPToMultiTokenKaiaExchange.ExchangeMode.WHITELIST;
        } else {
            mode = NLPToMultiTokenKaiaExchange.ExchangeMode.PUBLIC;
        }

        exchange.setExchangeMode(mode);
        console.log("Exchange mode set to:", INITIAL_EXCHANGE_MODE);

        // Add initial whitelist if provided
        address[] memory initialWhitelist = getInitialWhitelist();
        if (
            initialWhitelist.length > 0
                && mode == NLPToMultiTokenKaiaExchange.ExchangeMode.WHITELIST
        ) {
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
        console.log("Admin:", KAIA_ADMIN);
        console.log("Treasury:", KAIA_TREASURY);
        console.log("Price Updater:", KAIA_PRICE_UPDATER);
        console.log("Fee Manager:", KAIA_FEE_MANAGER);
        console.log("Emergency Manager:", KAIA_EMERGENCY_MANAGER);
        console.log("Config Manager:", KAIA_CONFIG_MANAGER);
        console.log("Fee Recipient:", KAIA_FEE_RECIPIENT);
        console.log("Whitelist Manager:", KAIA_WHITELIST_MANAGER);
        console.log("========================================");
        console.log("Token Addresses:");
        console.log("NLP Token:", KAIA_NLP_TOKEN);
        console.log("USDC Token:", KAIA_USDC_TOKEN);
        console.log("USDT Token:", KAIA_USDT_TOKEN);
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("Exchange Mode:", INITIAL_EXCHANGE_MODE);
        console.log("Initial Whitelist Count:", initialWhitelist.length);
        console.log("========================================");
        console.log("Next steps:");
        console.log("1. Fund the contract with KAIA, USDC, and USDT");
        console.log("2. Set up automated price updates using Pyth Network");
        console.log("3. Update external price data with current market prices");
        console.log("4. Configure monitoring and alerts");
        console.log("5. Test exchanges with small amounts before going live");
        console.log("========================================");
        console.log("IMPORTANT WARNINGS:");
        console.log("1. Update all price feeds with current market data before enabling exchanges");
        console.log("2. Set up regular price updates (recommended: every 5-10 minutes)");
        console.log("3. Monitor contract balance and refill as needed");
        console.log("4. Test all functionality on testnet first");
    }
}

/**
 * @title DeployKaiaExchangeLocal
 * @dev Local deployment script for testing NLPToMultiTokenKaiaExchange
 */
contract DeployKaiaExchangeLocal is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenKaiaExchange locally...");
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
        NLPToMultiTokenKaiaExchange exchange =
            new NLPToMultiTokenKaiaExchange(address(nlpToken), deployer);

        console.log("NLPToMultiTokenKaiaExchange deployed at:", address(exchange));

        // Set treasury
        exchange.setTreasury(deployer);

        // Configure KAIA token
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        // Configure USDC token
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            address(usdcToken),
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        // Configure USDT token
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            address(usdtToken),
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            50, // 0.5% operational fee
            deployer, // Fee recipient
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            25, // 0.25% operational fee
            deployer, // Fee recipient
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            30, // 0.3% operational fee
            deployer, // Fee recipient
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external prices for local testing
        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD
        uint kaiaUsdPrice = 0.15e18; // 1 KAIA = 0.15 USD
        uint usdcUsdPrice = 1e18; // 1 USDC = 1 USD
        uint usdtUsdPrice = 1e18; // 1 USDT = 1 USD

        // Validate price values
        require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");
        require(kaiaUsdPrice > 0, "KAIA/USD price must be greater than zero");
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

        exchange.updateKAIAUSDRoundData(
            1, // roundId
            int(kaiaUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        exchange.updateUSDCUSDRoundData(
            1, // roundId
            int(usdcUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        exchange.updateUSDTUSDRoundData(
            1, // roundId
            int(usdtUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        console.log("Test price data set for local testing");

        // Configure access control for local testing
        console.log("Configuring access control for local testing...");

        // Start with PUBLIC mode for easy testing
        exchange.setExchangeMode(NLPToMultiTokenKaiaExchange.ExchangeMode.PUBLIC);
        console.log("Exchange mode set to: PUBLIC (for testing)");

        // Fund the exchange contract with test liquidity
        uint kaiaAmount = 10 ether;
        uint usdcAmount = 100000 * 10 ** 6; // 100k USDC
        uint usdtAmount = 100000 * 10 ** 6; // 100k USDT

        vm.deal(address(exchange), kaiaAmount);

        // Mint tokens to exchange contract
        usdcToken.mint(address(exchange), usdcAmount);
        usdtToken.mint(address(exchange), usdtAmount);

        // Mint NLP tokens to deployer for testing
        nlpToken.mint(deployer, 1000000 * 10 ** 18); // 1M NLP tokens

        console.log("Exchange contract funded with test liquidity:");
        console.log("KAIA:", kaiaAmount / 1e18, "KAIA");
        console.log("USDC:", usdcAmount / 1e6, "USDC");
        console.log("USDT:", usdtAmount / 1e6, "USDT");
        console.log("NLP tokens minted to deployer:", 1000000, "NLP");

        // Verify funding
        require(address(exchange).balance >= kaiaAmount, "KAIA funding failed");
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
        console.log("- Exchange Mode: PUBLIC");
        console.log("========================================");
        console.log("Test Exchange Examples:");
        console.log("1. Exchange NLP for KAIA: exchange.exchangeNLP(0, amount)");
        console.log("2. Exchange NLP for USDC: exchange.exchangeNLP(1, amount)");
        console.log("3. Exchange NLP for USDT: exchange.exchangeNLP(2, amount)");
        console.log("========================================");
        console.log("To test different modes:");
        console.log("1. WHITELIST mode: exchange.setExchangeMode(1)");
        console.log("========================================");
    }
}
