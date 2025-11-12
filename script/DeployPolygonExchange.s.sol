// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenPolExchange } from "../src/NLPToMultiTokenPolExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

/**
 * @title DeployPolygonExchange
 * @dev Deployment script for NLPToMultiTokenPolExchange contract on Polygon
 */
contract DeployPolygonExchange is Script {
    // Polygon mainnet addresses (Update these with actual addresses)
    address POLYGON_ADMIN = vm.envAddress("POLYGON_ADMIN");
    address POLYGON_PRICE_UPDATER = vm.envAddress("POLYGON_PRICE_UPDATER");
    address POLYGON_FEE_MANAGER = vm.envAddress("POLYGON_FEE_MANAGER");
    address POLYGON_EMERGENCY_MANAGER = vm.envAddress("POLYGON_EMERGENCY_MANAGER");
    address POLYGON_CONFIG_MANAGER = vm.envAddress("POLYGON_CONFIG_MANAGER");
    address POLYGON_FEE_RECIPIENT = vm.envAddress("POLYGON_FEE_RECIPIENT");
    address POLYGON_WHITELIST_MANAGER = vm.envAddress("POLYGON_WHITELIST_MANAGER");

    // Token addresses on Polygon
    address POLYGON_NLP_TOKEN = vm.envAddress("POLYGON_NLP_TOKEN");
    address POLYGON_USDC_TOKEN =
        vm.envOr("POLYGON_USDC_TOKEN", address(0x3c499c542cEF5E3811e1192ce70d8cC03d5c3359)); // USDC on Polygon
    address POLYGON_USDT_TOKEN =
        vm.envOr("POLYGON_USDT_TOKEN", address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F)); // USDT on Polygon
    address POLYGON_JPYC_TOKEN = vm.envAddress("POLYGON_JPYC_TOKEN"); // JPYC token address

    // Chainlink Oracle addresses on Polygon
    // Polygon has Chainlink oracles available
    address POLYGON_MATIC_USD_ORACLE =
        vm.envOr("POLYGON_MATIC_USD_ORACLE", address(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0)); // MATIC/USD on Polygon
    address POLYGON_JPY_USD_ORACLE = vm.envOr("POLYGON_JPY_USD_ORACLE", address(0)); // JPY/USD (may not be available)
    address POLYGON_USDC_USD_ORACLE = vm.envOr("POLYGON_USDC_USD_ORACLE", address(0)); // USDC/USD on Polygon
    address POLYGON_USDT_USD_ORACLE = vm.envOr("POLYGON_USDT_USD_ORACLE", address(0)); // USDT/USD on Polygon

    // Access control configuration
    string INITIAL_EXCHANGE_MODE = vm.envOr("INITIAL_EXCHANGE_MODE", string("PUBLIC")); // "PUBLIC" or "WHITELIST"

    // Helper function to parse whitelist addresses from environment
    function getInitialWhitelist() internal view returns (address[] memory) {
        string memory whitelistStr = vm.envOr("INITIAL_WHITELIST", string(""));
        if (bytes(whitelistStr).length == 0) {
            return new address[](0);
        }
        return new address[](0);
    }

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenPolExchange on Polygon...");
        console.log("Deployer:", deployer);

        // Validate addresses before deployment
        require(POLYGON_ADMIN != address(0), "Admin address cannot be zero");
        require(POLYGON_PRICE_UPDATER != address(0), "Price updater address cannot be zero");
        require(POLYGON_FEE_MANAGER != address(0), "Fee manager address cannot be zero");
        require(POLYGON_EMERGENCY_MANAGER != address(0), "Emergency manager address cannot be zero");
        require(POLYGON_CONFIG_MANAGER != address(0), "Config manager address cannot be zero");
        require(POLYGON_FEE_RECIPIENT != address(0), "Fee recipient address cannot be zero");
        require(POLYGON_NLP_TOKEN != address(0), "NLP token address cannot be zero");
        require(POLYGON_JPYC_TOKEN != address(0), "JPYC token address cannot be zero");
        require(POLYGON_MATIC_USD_ORACLE != address(0), "MATIC/USD oracle address cannot be zero");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the exchange contract
        NLPToMultiTokenPolExchange exchange = new NLPToMultiTokenPolExchange(
            POLYGON_NLP_TOKEN,
            POLYGON_MATIC_USD_ORACLE,
            POLYGON_JPY_USD_ORACLE,
            POLYGON_USDC_USD_ORACLE,
            POLYGON_USDT_USD_ORACLE,
            POLYGON_ADMIN
        );

        console.log("NLPToMultiTokenPolExchange deployed at:", address(exchange));

        // Grant roles to designated addresses
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), POLYGON_PRICE_UPDATER);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), POLYGON_FEE_MANAGER);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), POLYGON_EMERGENCY_MANAGER);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), POLYGON_CONFIG_MANAGER);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), POLYGON_WHITELIST_MANAGER);

        console.log("Roles granted successfully");

        // Configure MATIC token
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.MATIC,
            address(0), // MATIC (native token)
            POLYGON_MATIC_USD_ORACLE,
            18,
            100, // 1% exchange fee
            false, // Not a direct exchange
            "MATIC"
        );

        // Configure USDC token (if available)
        if (POLYGON_USDC_TOKEN != address(0)) {
            exchange.configureToken(
                NLPToMultiTokenPolExchange.TokenType.USDC,
                POLYGON_USDC_TOKEN,
                POLYGON_USDC_USD_ORACLE,
                6, // USDC has 6 decimals
                50, // 0.5% exchange fee
                false, // Not a direct exchange
                "USDC"
            );
        }

        // Configure USDT token (if available)
        if (POLYGON_USDT_TOKEN != address(0)) {
            exchange.configureToken(
                NLPToMultiTokenPolExchange.TokenType.USDT,
                POLYGON_USDT_TOKEN,
                POLYGON_USDT_USD_ORACLE,
                6, // USDT has 6 decimals
                75, // 0.75% exchange fee
                false, // Not a direct exchange
                "USDT"
            );
        }

        // Configure JPYC token (1:1 direct exchange with NLP)
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            POLYGON_JPYC_TOKEN,
            address(0), // No oracle needed for 1:1 exchange
            18, // JPYC has 18 decimals
            25, // 0.25% exchange fee (lower fee for direct exchange)
            true, // DIRECT EXCHANGE - 1 NLP = 1 JPYC
            "JPYC"
        );

        console.log("Token configurations completed");
        console.log("JPYC configured with 1:1 direct exchange (no oracle needed)");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.MATIC,
            50, // 0.5% operational fee
            POLYGON_FEE_RECIPIENT,
            true
        );

        if (POLYGON_USDC_TOKEN != address(0)) {
            exchange.configureOperationalFee(
                NLPToMultiTokenPolExchange.TokenType.USDC,
                25, // 0.25% operational fee
                POLYGON_FEE_RECIPIENT,
                true
            );
        }

        if (POLYGON_USDT_TOKEN != address(0)) {
            exchange.configureOperationalFee(
                NLPToMultiTokenPolExchange.TokenType.USDT,
                30, // 0.3% operational fee
                POLYGON_FEE_RECIPIENT,
                true
            );
        }

        // Configure JPYC operational fee
        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            10, // 0.1% operational fee (lower for direct exchange)
            POLYGON_FEE_RECIPIENT,
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external prices if JPY/USD oracle is not available
        if (POLYGON_JPY_USD_ORACLE == address(0)) {
            uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD (approximate)

            require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");

            // Convert 18 decimals to 8 decimals for Chainlink format
            exchange.updateJPYUSDRoundData(
                1, // roundId
                int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
                block.timestamp, // startedAt
                block.timestamp, // updatedAt
                1 // answeredInRound
            );

            console.log("JPY/USD external price data set (oracle not available)");
            console.log("WARNING: Update JPY/USD price regularly via PRICE_UPDATER_ROLE");
        } else {
            console.log("JPY/USD oracle configured at:", POLYGON_JPY_USD_ORACLE);
        }

        // Configure access control settings
        console.log("Configuring access control...");

        // Set exchange mode
        NLPToMultiTokenPolExchange.ExchangeMode mode;
        if (keccak256(bytes(INITIAL_EXCHANGE_MODE)) == keccak256(bytes("WHITELIST"))) {
            mode = NLPToMultiTokenPolExchange.ExchangeMode.WHITELIST;
        } else {
            mode = NLPToMultiTokenPolExchange.ExchangeMode.PUBLIC;
        }

        exchange.setExchangeMode(mode);
        console.log("Exchange mode set to:", INITIAL_EXCHANGE_MODE);

        // Add initial whitelist if provided
        address[] memory initialWhitelist = getInitialWhitelist();
        if (
            initialWhitelist.length > 0 && mode == NLPToMultiTokenPolExchange.ExchangeMode.WHITELIST
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
        console.log("Admin:", POLYGON_ADMIN);
        console.log("Price Updater:", POLYGON_PRICE_UPDATER);
        console.log("Fee Manager:", POLYGON_FEE_MANAGER);
        console.log("Emergency Manager:", POLYGON_EMERGENCY_MANAGER);
        console.log("Config Manager:", POLYGON_CONFIG_MANAGER);
        console.log("Fee Recipient:", POLYGON_FEE_RECIPIENT);
        console.log("Whitelist Manager:", POLYGON_WHITELIST_MANAGER);
        console.log("========================================");
        console.log("Token Addresses:");
        console.log("NLP Token:", POLYGON_NLP_TOKEN);
        console.log("JPYC Token:", POLYGON_JPYC_TOKEN);
        console.log("USDC Token:", POLYGON_USDC_TOKEN);
        console.log("USDT Token:", POLYGON_USDT_TOKEN);
        console.log("========================================");
        console.log("Exchange Configuration:");
        console.log("JPYC: 1:1 direct exchange (1 NLP = 1 JPYC)");
        console.log("JPYC Fee: 0.25% exchange + 0.1% operational");
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("Exchange Mode:", INITIAL_EXCHANGE_MODE);
        console.log("Initial Whitelist Count:", initialWhitelist.length);
        console.log("========================================");
        console.log("Next steps:");
        console.log("1. Fund the contract with MATIC, USDC, USDT, and JPYC");
        console.log("2. If JPY/USD oracle unavailable, set up automated price updates");
        console.log("3. Verify MATIC/USD oracle is working properly");
        console.log("4. Configure monitoring and alerts");
        console.log("5. Test JPYC 1:1 exchange functionality");
        console.log("========================================");
    }
}

/**
 * @title DeployPolygonExchangeLocal
 * @dev Local deployment script for testing Polygon exchange with JPYC
 */
contract DeployPolygonExchangeLocal is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenPolExchange locally...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock NLP token
        NewLoPoint nlpToken = new NewLoPoint();
        nlpToken.initialize(deployer, deployer, deployer);

        // Deploy mock USDC token
        ERC20DecimalsWithMint usdcToken = new ERC20DecimalsWithMint("USD Coin", "USDC", 6);

        // Deploy mock USDT token
        ERC20DecimalsWithMint usdtToken = new ERC20DecimalsWithMint("Tether USD", "USDT", 6);

        // Deploy mock JPYC token (18 decimals like standard ERC20)
        ERC20DecimalsWithMint jpycToken = new ERC20DecimalsWithMint("JPY Coin", "JPYC", 18);

        console.log("Mock tokens deployed");
        console.log("NLP Token:", address(nlpToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("USDT Token:", address(usdtToken));
        console.log("JPYC Token:", address(jpycToken));

        // Deploy the exchange contract
        NLPToMultiTokenPolExchange exchange = new NLPToMultiTokenPolExchange(
            address(nlpToken),
            address(0), // No MATIC/USD oracle in local test
            address(0), // No JPY/USD oracle
            address(0), // No USDC/USD oracle in local test
            address(0), // No USDT/USD oracle in local test
            deployer
        );

        console.log("NLPToMultiTokenPolExchange deployed at:", address(exchange));

        // Configure MATIC token
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.MATIC,
            address(0), // MATIC
            address(0), // No oracle
            18,
            100, // 1% exchange fee
            false, // Not a direct exchange
            "MATIC"
        );

        // Configure USDC token
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.USDC,
            address(usdcToken),
            address(0), // No oracle
            6,
            50, // 0.5% exchange fee
            false, // Not a direct exchange
            "USDC"
        );

        // Configure USDT token
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.USDT,
            address(usdtToken),
            address(0), // No oracle
            6,
            75, // 0.75% exchange fee
            false, // Not a direct exchange
            "USDT"
        );

        // Configure JPYC token (1:1 direct exchange)
        exchange.configureToken(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            address(jpycToken),
            address(0), // No oracle needed for 1:1
            18,
            25, // 0.25% exchange fee
            true, // DIRECT EXCHANGE - 1 NLP = 1 JPYC
            "JPYC"
        );

        console.log("Token configurations completed");
        console.log("JPYC configured with 1:1 direct exchange");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.MATIC,
            50, // 0.5% operational fee
            deployer,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.USDC,
            25, // 0.25% operational fee
            deployer,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.USDT,
            30, // 0.3% operational fee
            deployer,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenPolExchange.TokenType.JPYC,
            10, // 0.1% operational fee
            deployer,
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external prices for local testing
        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD

        exchange.updateJPYUSDRoundData(
            1, // roundId
            int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        console.log("JPY/USD external price set for local testing");

        // Set exchange mode to PUBLIC for easier testing
        exchange.setExchangeMode(NLPToMultiTokenPolExchange.ExchangeMode.PUBLIC);
        console.log("Exchange mode set to: PUBLIC");

        // Fund the exchange contract with test liquidity
        uint maticAmount = 10 ether;
        uint usdcAmount = 100000 * 10 ** 6; // 100k USDC
        uint usdtAmount = 100000 * 10 ** 6; // 100k USDT
        uint jpycAmount = 1000000 * 10 ** 18; // 1M JPYC (18 decimals)

        vm.deal(address(exchange), maticAmount);

        // Mint tokens to exchange contract
        usdcToken.mint(address(exchange), usdcAmount);
        usdtToken.mint(address(exchange), usdtAmount);
        jpycToken.mint(address(exchange), jpycAmount);

        console.log("Exchange contract funded with test liquidity:");
        console.log("MATIC:", maticAmount / 1e18, "MATIC");
        console.log("USDC:", usdcAmount / 1e6, "USDC");
        console.log("USDT:", usdtAmount / 1e6, "USDT");
        console.log("JPYC:", jpycAmount / 1e18, "JPYC");

        // Verify funding
        require(address(exchange).balance >= maticAmount, "MATIC funding failed");
        require(usdcToken.balanceOf(address(exchange)) >= usdcAmount, "USDC funding failed");
        require(usdtToken.balanceOf(address(exchange)) >= usdtAmount, "USDT funding failed");
        require(jpycToken.balanceOf(address(exchange)) >= jpycAmount, "JPYC funding failed");

        // Mint some NLP to deployer for testing
        nlpToken.mint(deployer, 10000 * 1e18);
        console.log("Minted 10,000 NLP to deployer for testing");

        vm.stopBroadcast();

        console.log("Local deployment completed successfully!");
        console.log("========================================");
        console.log("Exchange Contract:", address(exchange));
        console.log("NLP Token:", address(nlpToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("USDT Token:", address(usdtToken));
        console.log("JPYC Token:", address(jpycToken));
        console.log("Admin/Owner:", deployer);
        console.log("========================================");
        console.log("JPYC Exchange Details:");
        console.log("- Exchange Rate: 1 NLP = 1 JPYC (direct 1:1)");
        console.log("- Exchange Fee: 0.25%");
        console.log("- Operational Fee: 0.1%");
        console.log("- Total Fee: 0.35%");
        console.log("========================================");
        console.log("Example: Exchange 1000 NLP for JPYC:");
        console.log("- Input: 1000 NLP");
        console.log("- Exchange Fee: 2.5 JPYC (0.25%)");
        console.log("- Operational Fee: 1.0 JPYC (0.1%)");
        console.log("- You receive: 996.5 JPYC");
        console.log("========================================");
        console.log("To test JPYC exchange:");
        console.log("1. Approve NLP: nlpToken.approve(exchange, amount)");
        console.log("2. Exchange: exchange.exchangeNLP(TokenType.JPYC, amount)");
        console.log("3. Check JPYC balance: jpycToken.balanceOf(yourAddress)");
        console.log("========================================");
    }
}
