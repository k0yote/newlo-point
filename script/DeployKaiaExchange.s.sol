// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NLPToMultiTokenKaiaExchange } from "../src/NLPToMultiTokenKaiaExchange.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

// Mock Pyth Network contract for testing
contract MockPyth {
    struct PriceData {
        int64 price;
        uint64 conf;
        int32 expo;
        uint publishTime;
    }

    mapping(bytes32 => PriceData) public prices;

    function updatePrice(bytes32 id, int64 price, uint64 conf, int32 expo) external {
        prices[id] = PriceData(price, conf, expo, block.timestamp);
    }

    function getPriceUnsafe(bytes32 id) external view returns (PriceData memory) {
        return prices[id];
    }

    function getUpdateFee(bytes[] calldata) external pure returns (uint) {
        return 0;
    }

    function updatePriceFeeds(bytes[] calldata) external payable {
        // Mock implementation - do nothing
    }
}

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

    // Pyth Network configuration
    address KAIA_PYTH_ADDRESS = vm.envAddress("KAIA_PYTH_ADDRESS"); // Pyth Network contract address
    bytes32 KAIA_USD_PRICE_ID = vm.envBytes32("KAIA_USD_PRICE_ID"); // KAIA/USD price ID
    bytes32 USDC_USD_PRICE_ID = vm.envOr("USDC_USD_PRICE_ID", bytes32(0)); // USDC/USD price ID (optional)
    bytes32 USDT_USD_PRICE_ID = vm.envOr("USDT_USD_PRICE_ID", bytes32(0)); // USDT/USD price ID (optional)

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

        console.log(
            "Deploying NLPToMultiTokenKaiaExchange on Kaia blockchain with Pyth integration..."
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
        require(KAIA_PYTH_ADDRESS != address(0), "Pyth address cannot be zero");
        require(KAIA_USD_PRICE_ID != bytes32(0), "KAIA/USD price ID cannot be zero");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the exchange contract with simplified constructor
        NLPToMultiTokenKaiaExchange exchange = new NLPToMultiTokenKaiaExchange(
            KAIA_NLP_TOKEN,
            KAIA_PYTH_ADDRESS,
            KAIA_USD_PRICE_ID,
            USDC_USD_PRICE_ID, // Optional - can be bytes32(0)
            USDT_USD_PRICE_ID, // Optional - can be bytes32(0)
            KAIA_ADMIN
        );

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

        // Configure tokens using the new configureToken function
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            KAIA_PYTH_ADDRESS,
            KAIA_USD_PRICE_ID,
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        if (USDC_USD_PRICE_ID != bytes32(0)) {
            exchange.configureToken(
                NLPToMultiTokenKaiaExchange.TokenType.USDC,
                KAIA_USDC_TOKEN,
                KAIA_PYTH_ADDRESS,
                USDC_USD_PRICE_ID,
                6,
                50, // 0.5% exchange fee
                "USDC"
            );
        }

        if (USDT_USD_PRICE_ID != bytes32(0)) {
            exchange.configureToken(
                NLPToMultiTokenKaiaExchange.TokenType.USDT,
                KAIA_USDT_TOKEN,
                KAIA_PYTH_ADDRESS,
                USDT_USD_PRICE_ID,
                6,
                75, // 0.75% exchange fee
                "USDT"
            );
        }

        console.log("Token configurations completed");

        // Configure operational fees
        exchange.configureOperationalFee(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            50, // 0.5% operational fee
            KAIA_FEE_RECIPIENT,
            true
        );

        if (USDC_USD_PRICE_ID != bytes32(0)) {
            exchange.configureOperationalFee(
                NLPToMultiTokenKaiaExchange.TokenType.USDC,
                25, // 0.25% operational fee
                KAIA_FEE_RECIPIENT,
                true
            );
        }

        if (USDT_USD_PRICE_ID != bytes32(0)) {
            exchange.configureOperationalFee(
                NLPToMultiTokenKaiaExchange.TokenType.USDT,
                30, // 0.3% operational fee
                KAIA_FEE_RECIPIENT,
                true
            );
        }

        console.log("Operational fee configurations completed");

        // Set initial JPY/USD external price data
        // WARNING: This price is for deployment only and MUST be updated immediately
        // with current market prices before enabling exchanges
        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD (example price)

        // Validate price values
        require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");

        // Set external JPY/USD price data (8 decimals format)
        exchange.updateJPYUSDRoundData(
            1, // roundId
            int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        console.log("Initial JPY/USD price data set (WARNING: Update with current prices!)");

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
        console.log("Pyth Network Configuration:");
        console.log("Pyth Address:", KAIA_PYTH_ADDRESS);
        console.log("KAIA/USD Price ID:", vm.toString(KAIA_USD_PRICE_ID));
        if (USDC_USD_PRICE_ID != bytes32(0)) {
            console.log("USDC/USD Price ID:", vm.toString(USDC_USD_PRICE_ID));
        } else {
            console.log("USDC/USD Price ID: Not configured (will be set via configureToken)");
        }
        if (USDT_USD_PRICE_ID != bytes32(0)) {
            console.log("USDT/USD Price ID:", vm.toString(USDT_USD_PRICE_ID));
        } else {
            console.log("USDT/USD Price ID: Not configured (will be set via configureToken)");
        }
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("Exchange Mode:", INITIAL_EXCHANGE_MODE);
        console.log("Initial Whitelist Count:", initialWhitelist.length);
        console.log("========================================");
        console.log("Next steps:");
        console.log("1. Fund the contract with KAIA, USDC, and USDT");
        console.log("2. Update JPY/USD external price data with current market prices");
        console.log("3. Ensure Pyth Network is providing accurate price feeds");
        console.log("4. Configure additional tokens via configureToken if needed");
        console.log("5. Configure monitoring and alerts");
        console.log("6. Test exchanges with small amounts before going live");
        console.log("========================================");
        console.log("IMPORTANT WARNINGS:");
        console.log(
            "1. Update JPY/USD price feed with current market data before enabling exchanges"
        );
        console.log("2. Verify Pyth Network price feeds are working correctly");
        console.log("3. Monitor contract balance and refill as needed");
        console.log("4. Test all functionality on testnet first");
        console.log("5. Set up regular JPY/USD price updates if not automated");
        console.log(
            "6. Use updateKAIAUSDOracle, updateUSDCUSDOracle, updateUSDTUSDOracle to update oracles post-deployment"
        );
    }
}

/**
 * @title DeployKaiaExchangeLocal
 * @dev Local deployment script for testing NLPToMultiTokenKaiaExchange with mock Pyth
 */
contract DeployKaiaExchangeLocal is Script {
    // Pyth price IDs for local testing
    bytes32 constant KAIA_USD_PRICE_ID = keccak256("KAIA/USD");
    bytes32 constant USDC_USD_PRICE_ID = keccak256("USDC/USD");
    bytes32 constant USDT_USD_PRICE_ID = keccak256("USDT/USD");

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToMultiTokenKaiaExchange locally with mock Pyth...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock NLP token
        NewLoPoint nlpToken = new NewLoPoint();
        nlpToken.initialize(deployer, deployer, deployer);

        // Deploy mock USDC token
        ERC20DecimalsWithMint usdcToken = new ERC20DecimalsWithMint("USD Coin", "USDC", 6);

        // Deploy mock USDT token
        ERC20DecimalsWithMint usdtToken = new ERC20DecimalsWithMint("Tether USD", "USDT", 6);

        // Deploy mock Pyth contract
        MockPyth mockPyth = new MockPyth();

        console.log("Mock tokens and Pyth deployed");
        console.log("NLP Token:", address(nlpToken));
        console.log("USDC Token:", address(usdcToken));
        console.log("USDT Token:", address(usdtToken));
        console.log("Mock Pyth:", address(mockPyth));

        // Set up mock Pyth prices (8 decimals format)
        mockPyth.updatePrice(KAIA_USD_PRICE_ID, 15000000, 0, -8); // 0.15 USD
        mockPyth.updatePrice(USDC_USD_PRICE_ID, 99971995, 0, -8); // ~1.00 USD
        mockPyth.updatePrice(USDT_USD_PRICE_ID, 100000000, 0, -8); // 1.00 USD

        console.log("Mock Pyth prices initialized");

        // Deploy the exchange contract with simplified constructor
        NLPToMultiTokenKaiaExchange exchange = new NLPToMultiTokenKaiaExchange(
            address(nlpToken),
            address(mockPyth),
            KAIA_USD_PRICE_ID,
            USDC_USD_PRICE_ID, // Optional - can be bytes32(0)
            USDT_USD_PRICE_ID, // Optional - can be bytes32(0)
            deployer
        );

        console.log("NLPToMultiTokenKaiaExchange deployed at:", address(exchange));

        // Set treasury
        exchange.setTreasury(deployer);

        // Configure tokens using the new configureToken function
        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.KAIA,
            address(0), // Native KAIA
            address(mockPyth),
            KAIA_USD_PRICE_ID,
            18,
            100, // 1% exchange fee
            "KAIA"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDC,
            address(usdcToken),
            address(mockPyth),
            USDC_USD_PRICE_ID,
            6,
            50, // 0.5% exchange fee
            "USDC"
        );

        exchange.configureToken(
            NLPToMultiTokenKaiaExchange.TokenType.USDT,
            address(usdtToken),
            address(mockPyth),
            USDT_USD_PRICE_ID,
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

        // Set initial JPY/USD external price for local testing
        uint jpyUsdPrice = 0.0067e18; // 1 JPY = 0.0067 USD

        // Validate price values
        require(jpyUsdPrice > 0, "JPY/USD price must be greater than zero");

        // Set external JPY/USD price data (8 decimals format)
        exchange.updateJPYUSDRoundData(
            1, // roundId
            int(jpyUsdPrice / 10 ** 10), // answer: convert to 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );

        console.log("Test JPY/USD price data set for local testing");

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
        console.log("Mock Pyth:", address(mockPyth));
        console.log("Admin/Owner:", deployer);
        console.log("========================================");
        console.log("Pyth Configuration:");
        console.log("KAIA/USD Price ID:", vm.toString(KAIA_USD_PRICE_ID));
        console.log("USDC/USD Price ID:", vm.toString(USDC_USD_PRICE_ID));
        console.log("USDT/USD Price ID:", vm.toString(USDT_USD_PRICE_ID));
        console.log("========================================");
        console.log("Access Control Settings:");
        console.log("- Exchange Mode: PUBLIC");
        console.log("========================================");
        console.log("Test Exchange Examples:");
        console.log("1. Exchange NLP for KAIA: exchange.exchangeNLP(0, amount)");
        console.log("2. Exchange NLP for USDC: exchange.exchangeNLP(1, amount)");
        console.log("3. Exchange NLP for USDT: exchange.exchangeNLP(2, amount)");
        console.log("========================================");
        console.log("Test Oracle Updates (individual oracles):");
        console.log("1. Update KAIA oracle: exchange.updateKAIAUSDOracle(newPyth, newPriceId)");
        console.log("2. Update USDC oracle: exchange.updateUSDCUSDOracle(newPyth, newPriceId)");
        console.log("3. Update USDT oracle: exchange.updateUSDTUSDOracle(newPyth, newPriceId)");
        console.log("========================================");
        console.log("Test Pyth Price Updates:");
        console.log("1. Update KAIA price: mockPyth.updatePrice(kaiaId, newPrice, 0, -8)");
        console.log("2. Update USDC price: mockPyth.updatePrice(usdcId, newPrice, 0, -8)");
        console.log("3. Update USDT price: mockPyth.updatePrice(usdtId, newPrice, 0, -8)");
        console.log("========================================");
        console.log("To test different modes:");
        console.log("1. WHITELIST mode: exchange.setExchangeMode(1)");
        console.log("2. Configure additional tokens via: exchange.configureToken(...)");
        console.log("========================================");
        console.log("Price Testing Commands:");
        console.log("1. Get latest KAIA price: exchange.getLatestETHPrice()");
        console.log("2. Get latest JPY price: exchange.getLatestJPYPrice()");
    }
}
