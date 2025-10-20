// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenKaiaExchangeV2 } from "../src/NLPToMultiTokenKaiaExchangeV2.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

/**
 * @title DeployKaiaExchangeV2
 * @dev Deployment script for NLPToMultiTokenKaiaExchangeV2 contract on Kaia blockchain
 * @notice V2 does not use oracles - all prices are updated externally via backend API
 */
contract DeployKaiaExchangeV2 is Script {
    // Kaia mainnet addresses (Update these with actual addresses)
    address KAIA_ADMIN = vm.envAddress("KAIA_ADMIN");
    address KAIA_PRICE_UPDATER = vm.envAddress("KAIA_PRICE_UPDATER");
    address KAIA_FEE_MANAGER = vm.envAddress("KAIA_FEE_MANAGER");
    address KAIA_EMERGENCY_MANAGER = vm.envAddress("KAIA_EMERGENCY_MANAGER");
    address KAIA_CONFIG_MANAGER = vm.envAddress("KAIA_CONFIG_MANAGER");
    address KAIA_FEE_RECIPIENT = vm.envAddress("KAIA_FEE_RECIPIENT");
    address KAIA_WHITELIST_MANAGER = vm.envAddress("KAIA_WHITELIST_MANAGER");

    // Token addresses
    address KAIA_NLP_TOKEN = vm.envAddress("KAIA_NLP_TOKEN");
    address KAIA_USDC_TOKEN = vm.envAddress("KAIA_USDC_TOKEN");
    address KAIA_USDT_TOKEN = vm.envAddress("KAIA_USDT_TOKEN");

    // Treasury address for emergency withdrawals
    address KAIA_TREASURY = vm.envAddress("KAIA_TREASURY");

    // Access control configuration
    string INITIAL_EXCHANGE_MODE = vm.envOr("INITIAL_EXCHANGE_MODE", string("PUBLIC")); // "PUBLIC" or "WHITELIST"

    // Initial price data (8 decimals format - must be updated with current market prices)
    int INITIAL_KAIA_USD_PRICE = int(vm.envOr("INITIAL_KAIA_USD_PRICE", uint(15000000))); // 0.15 USD
    int INITIAL_USDC_USD_PRICE = int(vm.envOr("INITIAL_USDC_USD_PRICE", uint(100000000))); // 1.00 USD
    int INITIAL_USDT_USD_PRICE = int(vm.envOr("INITIAL_USDT_USD_PRICE", uint(100000000))); // 1.00 USD
    int INITIAL_JPY_USD_PRICE = int(vm.envOr("INITIAL_JPY_USD_PRICE", uint(677093))); // 0.00677093 USD

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

        console.log(
            "Deploying NLPToMultiTokenKaiaExchangeV2 on Kaia blockchain with external price feeds..."
        );
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

        // Deploy the V2 exchange contract with simplified constructor (no oracle dependencies)
        NLPToMultiTokenKaiaExchangeV2 exchange =
            new NLPToMultiTokenKaiaExchangeV2(KAIA_NLP_TOKEN, KAIA_ADMIN);

        console.log("NLPToMultiTokenKaiaExchangeV2 deployed at:", address(exchange));

        // Set treasury address
        exchange.setTreasury(KAIA_TREASURY);

        // Grant roles to designated addresses
        exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), KAIA_PRICE_UPDATER);
        exchange.grantRole(exchange.FEE_MANAGER_ROLE(), KAIA_FEE_MANAGER);
        exchange.grantRole(exchange.EMERGENCY_MANAGER_ROLE(), KAIA_EMERGENCY_MANAGER);
        exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), KAIA_CONFIG_MANAGER);
        exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), KAIA_WHITELIST_MANAGER);

        console.log("Roles granted successfully");

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
            KAIA_USDC_TOKEN,
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDT,
            KAIA_USDT_TOKEN,
            6,
            75, // 0.75% exchange fee
            "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            50, // 0.5% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDC,
            25, // 0.25% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDT,
            30, // 0.3% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        console.log("Operational fee configurations completed");

        // Set initial external price data
        // WARNING: These prices are for deployment only and MUST be updated immediately
        // with current market prices from backend API before enabling exchanges
        uint currentTime = block.timestamp;

        exchange.updateKAIAUSDRoundData(
            1, // roundId
            INITIAL_KAIA_USD_PRICE, // answer (8 decimals)
            currentTime, // startedAt
            currentTime, // updatedAt
            1 // answeredInRound
        );

        exchange.updateUSDCUSDRoundData(
            1, // roundId
            INITIAL_USDC_USD_PRICE, // answer (8 decimals)
            currentTime, // startedAt
            currentTime, // updatedAt
            1 // answeredInRound
        );

        exchange.updateUSDTUSDRoundData(
            1, // roundId
            INITIAL_USDT_USD_PRICE, // answer (8 decimals)
            currentTime, // startedAt
            currentTime, // updatedAt
            1 // answeredInRound
        );

        exchange.updateJPYUSDRoundData(
            1, // roundId
            INITIAL_JPY_USD_PRICE, // answer (8 decimals)
            currentTime, // startedAt
            currentTime, // updatedAt
            1 // answeredInRound
        );

        console.log("Initial external price data set (WARNING: Update with current prices!)");

        // Configure access control settings
        console.log("Configuring access control...");

        // Set exchange mode
        NLPToMultiTokenKaiaExchangeV2.ExchangeMode mode;
        if (keccak256(bytes(INITIAL_EXCHANGE_MODE)) == keccak256(bytes("WHITELIST"))) {
            mode = NLPToMultiTokenKaiaExchangeV2.ExchangeMode.WHITELIST;
        } else {
            mode = NLPToMultiTokenKaiaExchangeV2.ExchangeMode.PUBLIC;
        }

        exchange.setExchangeMode(mode);
        console.log("Exchange mode set to:", INITIAL_EXCHANGE_MODE);

        // Add initial whitelist if provided
        address[] memory initialWhitelist = getInitialWhitelist();
        if (
            initialWhitelist.length > 0
                && mode == NLPToMultiTokenKaiaExchangeV2.ExchangeMode.WHITELIST
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
        console.log("External Price Feed Configuration (V2):");
        console.log("All prices are managed via backend API updates");
        console.log("Initial KAIA/USD Price (8 decimals):", INITIAL_KAIA_USD_PRICE);
        console.log("Initial USDC/USD Price (8 decimals):", INITIAL_USDC_USD_PRICE);
        console.log("Initial USDT/USD Price (8 decimals):", INITIAL_USDT_USD_PRICE);
        console.log("Initial JPY/USD Price (8 decimals):", INITIAL_JPY_USD_PRICE);
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("Exchange Mode:", INITIAL_EXCHANGE_MODE);
        console.log("Initial Whitelist Count:", initialWhitelist.length);
        console.log("========================================");
        console.log("Next steps:");
        console.log("1. Fund the contract with KAIA, USDC, and USDT");
        console.log("2. Update all external price data via backend API with current market prices:");
        console.log("   - exchange.updateKAIAUSDRoundData(...)");
        console.log("   - exchange.updateUSDCUSDRoundData(...)");
        console.log("   - exchange.updateUSDTUSDRoundData(...)");
        console.log("   - exchange.updateJPYUSDRoundData(...)");
        console.log("3. Configure monitoring and alerts for price updates");
        console.log("4. Set up automated price update service from backend");
        console.log("5. Test exchanges with small amounts before going live");
        console.log("========================================");
        console.log("IMPORTANT WARNINGS:");
        console.log(
            "1. V2 DOES NOT USE ORACLES - All prices must be updated via backend API"
        );
        console.log("2. Update all price feeds with current market data before enabling exchanges");
        console.log("3. Set up regular price updates from backend (recommended: every 1-5 minutes)");
        console.log("4. Monitor contract balance and refill as needed");
        console.log("5. Test all functionality on testnet first");
        console.log("6. Implement price staleness monitoring in backend");
        console.log("========================================");
    }
}

/**
 * @title DeployKaiaExchangeV2Local
 * @dev Local deployment script for testing NLPToMultiTokenKaiaExchangeV2 without oracle dependencies
 */
contract DeployKaiaExchangeV2Local is Script {
    // Mock price data (8 decimals format matching Chainlink)
    int64 constant KAIA_USD_PRICE = 15000000; // 0.15 USD
    int64 constant USDC_USD_PRICE = 100000000; // 1.00 USD
    int64 constant USDT_USD_PRICE = 100000000; // 1.00 USD
    int64 constant JPY_USD_PRICE = 677093; // 0.00677093 USD

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenKaiaExchangeV2 locally (no oracle dependencies)...");
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

        // Deploy the V2 exchange contract with simplified constructor
        NLPToMultiTokenKaiaExchangeV2 exchange =
            new NLPToMultiTokenKaiaExchangeV2(address(nlpToken), deployer);

        console.log("NLPToMultiTokenKaiaExchangeV2 deployed at:", address(exchange));

        // Set treasury
        exchange.setTreasury(deployer);

        // Configure tokens (no oracle addresses needed)
        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA,
            address(0), // Native KAIA
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDC, address(usdcToken), 6, 50, "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDT, address(usdtToken), 6, 75, "USDT"
        );

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.KAIA, 50, deployer, true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDC, 25, deployer, true
        );

        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchangeV2.TokenType.USDT, 30, deployer, true
        );

        console.log("Operational fee configurations completed");

        // Set initial external price data for local testing
        uint currentTime = block.timestamp;

        exchange.updateKAIAUSDRoundData(1, KAIA_USD_PRICE, currentTime, currentTime, 1);
        exchange.updateUSDCUSDRoundData(1, USDC_USD_PRICE, currentTime, currentTime, 1);
        exchange.updateUSDTUSDRoundData(1, USDT_USD_PRICE, currentTime, currentTime, 1);
        exchange.updateJPYUSDRoundData(1, JPY_USD_PRICE, currentTime, currentTime, 1);

        console.log("Test external price data set for local testing");

        // Configure access control for local testing
        console.log("Configuring access control for local testing...");

        // Start with PUBLIC mode for easy testing
        exchange.setExchangeMode(NLPToMultiTokenKaiaExchangeV2.ExchangeMode.PUBLIC);
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
        console.log("External Price Feed Configuration (V2):");
        console.log("KAIA/USD Price (8 decimals):", KAIA_USD_PRICE);
        console.log("USDC/USD Price (8 decimals):", USDC_USD_PRICE);
        console.log("USDT/USD Price (8 decimals):", USDT_USD_PRICE);
        console.log("JPY/USD Price (8 decimals):", JPY_USD_PRICE);
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("- Exchange Mode: PUBLIC");
        console.log("========================================");
        console.log("Test Exchange Examples:");
        console.log("1. Exchange NLP for KAIA: exchange.exchangeNLP(0, amount)");
        console.log("2. Exchange NLP for USDC: exchange.exchangeNLP(1, amount)");
        console.log("3. Exchange NLP for USDT: exchange.exchangeNLP(2, amount)");
        console.log("========================================");
        console.log("Test Price Updates (via external API simulation):");
        console.log("1. Update KAIA price: exchange.updateKAIAUSDRoundData(roundId, price, ...)");
        console.log("2. Update USDC price: exchange.updateUSDCUSDRoundData(roundId, price, ...)");
        console.log("3. Update USDT price: exchange.updateUSDTUSDRoundData(roundId, price, ...)");
        console.log("4. Update JPY price: exchange.updateJPYUSDRoundData(roundId, price, ...)");
        console.log("========================================");
        console.log("Test Gasless Exchange:");
        console.log(
            "1. With permit: exchange.exchangeNLPWithPermit(type, amount, deadline, v, r, s, user)"
        );
        console.log(
            "2. With slippage: exchange.exchangeNLPWithPermitAndSlippage(type, amount, minOut, ...)"
        );
        console.log("========================================");
        console.log("View Functions:");
        console.log("1. Get quote: exchange.getExchangeQuote(tokenType, nlpAmount)");
        console.log(
            "2. Get quote with slippage: exchange.getExchangeQuoteWithSlippage(type, amount, slippage)"
        );
        console.log("3. Get KAIA price: exchange.getLatestKAIAPrice()");
        console.log("4. Get USDC price: exchange.getLatestUSDCPrice()");
        console.log("5. Get USDT price: exchange.getLatestUSDTPrice()");
        console.log("6. Get JPY price: exchange.getLatestJPYPrice()");
        console.log("========================================");
        console.log("To test different modes:");
        console.log("1. WHITELIST mode: exchange.setExchangeMode(1)");
        console.log("2. Add to whitelist: exchange.updateWhitelist([address], [true])");
        console.log("========================================");
    }
}

