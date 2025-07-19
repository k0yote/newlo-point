// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { TokenDistributionV2 } from "../src/TokenDistributionV2.sol";
import { MultiTokenDistribution } from "../src/MultiTokenDistribution.sol";
import { NLPToMultiTokenExchange } from "../src/NLPToMultiTokenExchange.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";
import { MockV3Aggregator } from "../src/mocks/MockV3Aggregator.sol";

/**
 * @title DeployLocalScenario
 * @author NewLo Team
 * @notice ローカルAnvilでのフルシナリオデプロイスクリプト
 * @dev このスクリプトは以下を実行します：
 *      1. NewLoPointFactoryをデプロイ
 *      2. NewLoPointをデプロイ
 *      3. TokenDistributionV2をデプロイ
 *      4. MultiTokenDistributionをデプロイ
 *      5. NLPToMultiTokenExchangeをデプロイ
 *      6. Mock tokens（USDC、USDT、WETH）をデプロイ
 *      7. NewLoPointの設定（whitelist、transfer control）
 *      8. NLPToMultiTokenExchangeの設定（トークン設定、価格設定）
 *      9. トークンの付与とロール設定
 *
 * @dev 使用方法:
 *      forge script script/DeployLocalScenario.s.sol:DeployLocalScenario --fork-url http://localhost:8545 --broadcast
 */
contract DeployLocalScenario is Script {
    // デプロイ用のアドレス設定
    address constant DEPLOYER = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266; // Anvil default account[0]
    address constant ADMIN = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8; // Anvil default account[1]
    address constant PAUSER = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC; // Anvil default account[2]
    address constant MINTER = 0x90F79bf6EB2c4f870365E785982E1f101E93b906; // Anvil default account[3]

    // デプロイされたコントラクトのアドレス
    NewLoPointFactory public factory;
    NewLoPoint public nlpToken;
    TokenDistributionV2 public tokenDistV2;
    MultiTokenDistribution public multiTokenDist;
    NLPToMultiTokenExchange public nlpExchange;

    // Mock tokens
    ERC20DecimalsWithMint public usdcToken;
    ERC20DecimalsWithMint public usdtToken;
    ERC20DecimalsWithMint public wethToken;

    // Mock price feed aggregators
    MockV3Aggregator public ethUsdPriceFeed;
    MockV3Aggregator public jpyUsdPriceFeed;

    function run() external {
        console.log("=== LOCAL SCENARIO DEPLOYMENT ===");
        console.log("Deployer:", DEPLOYER);
        console.log("Admin:", ADMIN);
        console.log("Pauser:", PAUSER);
        console.log("Minter:", MINTER);
        console.log("Chain ID:", block.chainid);
        console.log("Block Number:", block.number);

        // プライベートキーを設定（Anvilのデフォルトアカウント）
        uint deployerPrivateKey = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;

        vm.startBroadcast(deployerPrivateKey);

        // 1. NewLoPointFactoryをデプロイ
        _deployFactory();

        // 2. NewLoPointをデプロイ
        _deployNewLoPoint();

        // 3. TokenDistributionV2をデプロイ
        _deployTokenDistributionV2();

        // 4. MultiTokenDistributionをデプロイ
        _deployMultiTokenDistribution();

        // 4.5. Mock price feedsをデプロイ
        _deployMockPriceFeeds();

        // 5. NLPToMultiTokenExchangeをデプロイ
        _deployNLPToMultiTokenExchange();

        // 6. Mock tokensをデプロイ
        _deployMockTokens();

        // 7. NewLoPointの設定
        _configureNewLoPoint();

        // 8. NLPToMultiTokenExchangeの設定
        _configureNLPToMultiTokenExchange();

        // 9. トークンの付与とロール設定
        _setupTokensAndRoles();

        vm.stopBroadcast();

        // デプロイサマリーを表示
        _logDeploymentSummary();
    }

    function _deployFactory() internal {
        console.log("\n=== DEPLOYING FACTORY ===");

        factory = new NewLoPointFactory();

        console.log("Factory deployed at:", address(factory));
        console.log("Implementation:", factory.implementation());
        console.log("ProxyAdmin:", address(factory.proxyAdmin()));
    }

    function _deployNewLoPoint() internal {
        console.log("\n=== DEPLOYING NEWLOPOINT ===");

        // CREATE2でNewLoPointをデプロイ
        bytes32 salt = keccak256("NewLoPoint-Local-Scenario");
        address predictedAddress = factory.predictAddress(salt, ADMIN, PAUSER, MINTER);

        console.log("Predicted address:", predictedAddress);

        address deployedAddress = factory.deployToken(salt, ADMIN, PAUSER, MINTER);
        nlpToken = NewLoPoint(deployedAddress);

        console.log("NewLoPoint deployed at:", address(nlpToken));
        console.log("Token name:", nlpToken.name());
        console.log("Token symbol:", nlpToken.symbol());
        console.log("Prediction correct:", predictedAddress == address(nlpToken));
    }

    function _deployTokenDistributionV2() internal {
        console.log("\n=== DEPLOYING TOKEN DISTRIBUTION V2 ===");

        tokenDistV2 = new TokenDistributionV2(address(nlpToken), ADMIN);

        console.log("TokenDistributionV2 deployed at:", address(tokenDistV2));
        console.log("NLP Token address:", address(tokenDistV2.nlpToken()));
    }

    function _deployMultiTokenDistribution() internal {
        console.log("\n=== DEPLOYING MULTI TOKEN DISTRIBUTION ===");

        multiTokenDist = new MultiTokenDistribution(ADMIN);

        console.log("MultiTokenDistribution deployed at:", address(multiTokenDist));
        console.log(
            "Admin has ADMIN_ROLE:", multiTokenDist.hasRole(multiTokenDist.ADMIN_ROLE(), ADMIN)
        );
    }

    function _deployNLPToMultiTokenExchange() internal {
        console.log("\n=== DEPLOYING NLP TO MULTI TOKEN EXCHANGE ===");

        // ローカル環境ではChainlinkのprice feedはないので、mock aggregatorsを使用
        nlpExchange = new NLPToMultiTokenExchange(
            address(nlpToken),
            address(ethUsdPriceFeed), // Use mock ETH/USD price feed
            address(0), // No JPY/USD price feed in local environment
            address(0), // No USDC/USD price feed in local environment (could add mock if needed)
            address(0), // No USDT/USD price feed in local environment (could add mock if needed)
            ADMIN
        );

        console.log("NLPToMultiTokenExchange deployed at:", address(nlpExchange));
        console.log("NLP Token address:", address(nlpExchange.nlpToken()));
        console.log("Has JPY Oracle:", address(nlpExchange.jpyUsdPriceFeed()) != address(0));
    }

    function _deployMockTokens() internal {
        console.log("\n=== DEPLOYING MOCK TOKENS ===");

        // Deploy USDC mock token
        usdcToken = new ERC20DecimalsWithMint("USD Coin", "USDC", 6);
        console.log("USDC deployed at:", address(usdcToken));
        console.log("USDC name:", usdcToken.name());
        console.log("USDC symbol:", usdcToken.symbol());
        console.log("USDC decimals:", usdcToken.decimals());

        // Deploy USDT mock token
        usdtToken = new ERC20DecimalsWithMint("Tether USD", "USDT", 6);
        console.log("USDT deployed at:", address(usdtToken));
        console.log("USDT name:", usdtToken.name());
        console.log("USDT symbol:", usdtToken.symbol());
        console.log("USDT decimals:", usdtToken.decimals());

        // Deploy WETH mock token
        wethToken = new ERC20DecimalsWithMint("Wrapped Ether", "WETH", 18);
        console.log("WETH deployed at:", address(wethToken));
        console.log("WETH name:", wethToken.name());
        console.log("WETH symbol:", wethToken.symbol());
        console.log("WETH decimals:", wethToken.decimals());
    }

    function _deployMockPriceFeeds() internal {
        console.log("\n=== DEPLOYING MOCK PRICE FEEDS ===");

        // Deploy ETH/USD mock price feed (8 decimals)
        ethUsdPriceFeed = new MockV3Aggregator(8, 200000000000); // 2000 USD (8 decimals: 2000.00000000)
        console.log("ETH/USD Price Feed deployed at:", address(ethUsdPriceFeed));
        console.log("ETH/USD Price:", ethUsdPriceFeed.latestAnswer());

        // Deploy JPY/USD mock price feed (8 decimals)
        jpyUsdPriceFeed = new MockV3Aggregator(8, 677093); // 0.00677093 USD (8 decimals: 0.00677093)
        console.log("JPY/USD Price Feed deployed at:", address(jpyUsdPriceFeed));
        console.log("JPY/USD Price:", jpyUsdPriceFeed.latestAnswer());
    }

    function _configureNewLoPoint() internal {
        console.log("\n=== CONFIGURING NEWLOPOINT ===");

        // ADMINとしてwhitelistに追加
        vm.stopBroadcast();
        uint adminPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // account[1]
        vm.startBroadcast(adminPrivateKey);

        // TokenDistributionV2をwhitelistに追加
        nlpToken.setWhitelistedAddress(address(tokenDistV2), true);
        console.log("Added TokenDistributionV2 to whitelist");

        // MultiTokenDistributionをwhitelistに追加
        nlpToken.setWhitelistedAddress(address(multiTokenDist), true);
        console.log("Added MultiTokenDistribution to whitelist");

        // NLPToMultiTokenExchangeをwhitelistに追加
        nlpToken.setWhitelistedAddress(address(nlpExchange), true);
        console.log("Added NLPToMultiTokenExchange to whitelist");

        // Whitelist機能をオン
        nlpToken.setWhitelistModeEnabled(true);
        console.log("Enabled whitelist mode");

        // Transfer機能をオン（後で必要に応じてオフにできる）
        nlpToken.setTransfersEnabled(true);
        console.log("Enabled transfers");

        vm.stopBroadcast();
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
    }

    function _configureNLPToMultiTokenExchange() internal {
        console.log("\n=== CONFIGURING NLP TO MULTI TOKEN EXCHANGE ===");

        vm.stopBroadcast();
        uint adminPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // account[1]
        vm.startBroadcast(adminPrivateKey);

        // ETHトークンの設定
        nlpExchange.configureToken(
            NLPToMultiTokenExchange.TokenType.ETH,
            address(0), // ETH
            address(0), // No oracle in local environment
            18, // ETH decimals
            100, // 1% exchange fee
            "ETH"
        );
        console.log("Configured ETH token");

        // USDCトークンの設定
        nlpExchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDC,
            address(usdcToken),
            address(0), // No oracle in local environment
            6, // USDC decimals
            100, // 1% exchange fee
            "USDC"
        );
        console.log("Configured USDC token");

        // USDTトークンの設定
        nlpExchange.configureToken(
            NLPToMultiTokenExchange.TokenType.USDT,
            address(usdtToken),
            address(0), // No oracle in local environment
            6, // USDT decimals
            100, // 1% exchange fee
            "USDT"
        );
        console.log("Configured USDT token");

        // 運営手数料の設定（各トークンに対して0.5%）
        nlpExchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.ETH,
            50, // 0.5% operational fee
            ADMIN, // Fee recipient
            true // Enabled
        );

        nlpExchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDC,
            50, // 0.5% operational fee
            ADMIN, // Fee recipient
            true // Enabled
        );

        nlpExchange.configureOperationalFee(
            NLPToMultiTokenExchange.TokenType.USDT,
            50, // 0.5% operational fee
            ADMIN, // Fee recipient
            true // Enabled
        );
        console.log("Configured operational fees");

        // 外部価格データの設定（テスト用の価格）
        // JPY/USD価格を設定（例：1 USD = 150 JPY → 1 JPY = 0.006667 USD）
        // Using Chainlink format: 8 decimals = 66670000 (0.6667 cents per JPY)
        nlpExchange.updateJPYUSDRoundData(
            1, // roundId
            66670000, // answer: 0.006667 USD in 8 decimals
            block.timestamp, // startedAt
            block.timestamp, // updatedAt
            1 // answeredInRound
        );
        console.log("Updated JPY/USD external price");

        // Note: ETH/USDC/USDT prices are now fetched from Chainlink oracles only
        // No external price setting required for these tokens
        console.log("ETH/USDC/USDT prices will be fetched from Chainlink oracles");

        // treasuryアドレスを設定
        nlpExchange.setTreasury(ADMIN);
        console.log("Set treasury address");

        vm.stopBroadcast();
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
    }

    function _setupTokensAndRoles() internal {
        console.log("\n=== SETTING UP TOKENS AND ROLES ===");

        // MINTERロールをDeployerに一時的に付与
        vm.stopBroadcast();
        uint adminPrivateKey = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d; // account[1]
        vm.startBroadcast(adminPrivateKey);

        nlpToken.grantRole(nlpToken.MINTER_ROLE(), DEPLOYER);
        console.log("Granted MINTER_ROLE to deployer");

        // NLPToMultiTokenExchangeは burnFrom を使用するため、特別なロールは不要

        vm.stopBroadcast();
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        // TokenDistributionV2に10000 NLPを付与
        uint amount = 10000 * 10 ** 18;
        nlpToken.mint(address(tokenDistV2), amount);
        console.log("Minted 10000 NLP to TokenDistributionV2");

        // MultiTokenDistributionに10000 NLPを付与
        nlpToken.mint(address(multiTokenDist), amount);
        console.log("Minted 10000 NLP to MultiTokenDistribution");

        // NLPToMultiTokenExchangeに供給用のトークンを付与
        // ETHをコントラクトに送金（10 ETH）
        (bool sent,) = address(nlpExchange).call{ value: 10 ether }("");
        require(sent, "ETH transfer failed");
        console.log("Sent 10 ETH to NLPToMultiTokenExchange");

        // USDCトークンを作成してNLPToMultiTokenExchangeに送金（100,000 USDC）
        usdcToken.mint(address(nlpExchange), 100000 * 10 ** 6);
        console.log("Minted 100,000 USDC to NLPToMultiTokenExchange");

        // USDTトークンを作成してNLPToMultiTokenExchangeに送金（100,000 USDT）
        usdtToken.mint(address(nlpExchange), 100000 * 10 ** 6);
        console.log("Minted 100,000 USDT to NLPToMultiTokenExchange");

        // テスト用ユーザーにNLPを付与
        nlpToken.mint(ADMIN, 1000 * 10 ** 18);
        nlpToken.mint(PAUSER, 1000 * 10 ** 18);
        nlpToken.mint(MINTER, 1000 * 10 ** 18);
        console.log("Minted 1000 NLP to test users");

        // TokenDistributionV2にMINTER_ROLEを付与
        vm.stopBroadcast();
        vm.startBroadcast(adminPrivateKey);

        nlpToken.grantRole(nlpToken.MINTER_ROLE(), address(tokenDistV2));
        console.log("Granted MINTER_ROLE to TokenDistributionV2");

        // TokenDistributionV2に必要なロールを付与
        tokenDistV2.grantRole(tokenDistV2.DISTRIBUTOR_ROLE(), ADMIN);
        tokenDistV2.grantRole(tokenDistV2.DEPOSIT_MANAGER_ROLE(), ADMIN);
        tokenDistV2.grantRole(tokenDistV2.PAUSER_ROLE(), PAUSER);
        console.log("Granted roles to TokenDistributionV2");

        vm.stopBroadcast();
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);
    }

    function _logDeploymentSummary() internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("NewLoPointFactory:", address(factory));
        console.log("NewLoPoint:", address(nlpToken));
        console.log("TokenDistributionV2:", address(tokenDistV2));
        console.log("MultiTokenDistribution:", address(multiTokenDist));
        console.log("NLPToMultiTokenExchange:", address(nlpExchange));
        console.log("USDC Mock Token:", address(usdcToken));
        console.log("USDT Mock Token:", address(usdtToken));
        console.log("WETH Mock Token:", address(wethToken));

        console.log("\n=== NEWLOPOINT STATUS ===");
        console.log("Name:", nlpToken.name());
        console.log("Symbol:", nlpToken.symbol());
        console.log("Transfers Enabled:", nlpToken.transfersEnabled());
        console.log("Whitelist Mode:", nlpToken.whitelistModeEnabled());
        console.log("TokenDistV2 Whitelisted:", nlpToken.whitelistedAddresses(address(tokenDistV2)));
        console.log(
            "MultiTokenDist Whitelisted:", nlpToken.whitelistedAddresses(address(multiTokenDist))
        );
        console.log("NLPExchange Whitelisted:", nlpToken.whitelistedAddresses(address(nlpExchange)));
        console.log("TokenDistV2 Balance:", nlpToken.balanceOf(address(tokenDistV2)) / 10 ** 18);
        console.log(
            "MultiTokenDist Balance:", nlpToken.balanceOf(address(multiTokenDist)) / 10 ** 18
        );

        console.log("\n=== NLP TO MULTI TOKEN EXCHANGE STATUS ===");
        console.log("Contract Address:", address(nlpExchange));
        console.log("ETH Balance:", address(nlpExchange).balance / 10 ** 18);
        console.log("USDC Balance:", usdcToken.balanceOf(address(nlpExchange)) / 10 ** 6);
        console.log("USDT Balance:", usdtToken.balanceOf(address(nlpExchange)) / 10 ** 6);
        console.log("Has JPY Oracle:", address(nlpExchange.jpyUsdPriceFeed()) != address(0));
        console.log("Treasury Address:", nlpExchange.treasury());

        console.log("\n=== ROLES ===");
        console.log(
            "NLP MINTER_ROLE for TokenDistV2:",
            nlpToken.hasRole(nlpToken.MINTER_ROLE(), address(tokenDistV2))
        );
        // NLPToMultiTokenExchangeは burnFrom を使用（役割ベース確認なし）
        console.log(
            "TokenDistV2 DISTRIBUTOR_ROLE for Admin:",
            tokenDistV2.hasRole(tokenDistV2.DISTRIBUTOR_ROLE(), ADMIN)
        );

        console.log("\n=== MOCK TOKENS INFO ===");
        console.log("USDC:", address(usdcToken));
        console.log("USDT:", address(usdtToken));
        console.log("WETH:", address(wethToken));
        console.log("USDC Supply:", usdcToken.totalSupply());
        console.log("USDT Supply:", usdtToken.totalSupply());
        console.log("WETH Supply:", wethToken.totalSupply());

        console.log("\n=== TEST USER BALANCES ===");
        console.log("Admin NLP Balance:", nlpToken.balanceOf(ADMIN) / 10 ** 18);
        console.log("Pauser NLP Balance:", nlpToken.balanceOf(PAUSER) / 10 ** 18);
        console.log("Minter NLP Balance:", nlpToken.balanceOf(MINTER) / 10 ** 18);

        console.log("\n=== USEFUL CAST COMMANDS ===");
        console.log("Grant MINTER_ROLE to address:");
        console.log(
            "cast send [NLP_TOKEN] \"grantRole(bytes32,address)\" 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6 [ADDRESS] --private-key [ADMIN_KEY]"
        );

        console.log("\nMint tokens to address:");
        console.log(
            "cast send [NLP_TOKEN] \"mint(address,uint256)\" [ADDRESS] \"1000000000000000000000\" --private-key [ADMIN_KEY]"
        );

        console.log("\nAdd address to whitelist:");
        console.log(
            "cast send [NLP_TOKEN] \"setWhitelistedAddress(address,bool)\" [ADDRESS] true --private-key [ADMIN_KEY]"
        );

        console.log("\nExchange NLP for ETH:");
        console.log(
            "cast send [NLP_EXCHANGE] \"exchangeNLP(uint8,uint256)\" 0 \"100000000000000000000\" --private-key [USER_KEY]"
        );
        console.log("# TokenType: ETH=0, USDC=1, USDT=2");

        console.log("\nGet exchange quote:");
        console.log(
            "cast call [NLP_EXCHANGE] \"getExchangeQuote(uint8,uint256)\" 0 \"100000000000000000000\""
        );

        console.log("\nUpdate external price:");
        console.log(
            "cast send [NLP_EXCHANGE] \"updateExternalPrice(uint8,uint256)\" 0 \"2000000000000000000000\" --private-key [ADMIN_KEY]"
        );

        console.log("\nMint mock tokens (USDC/USDT/WETH):");
        console.log(
            "cast send [TOKEN_ADDRESS] \"mint(address,uint256)\" [ADDRESS] [AMOUNT] --private-key [PRIVATE_KEY]"
        );
        console.log(
            "Example USDC mint: cast send",
            address(usdcToken),
            "\"mint(address,uint256)\" [ADDRESS] \"1000000000\" --private-key [PRIVATE_KEY]"
        );
        console.log("# The above command mints 1000 USDC (6 decimals)");

        console.log("\n=== ANVIL ACCOUNTS ===");
        console.log("Account[0] (Deployer):", DEPLOYER);
        console.log("Account[1] (Admin):", ADMIN);
        console.log("Account[2] (Pauser):", PAUSER);
        console.log("Account[3] (Minter):", MINTER);

        console.log("\n=== QUICK TEST COMMANDS ===");
        console.log("Check NLP balance:");
        console.log("cast call", address(nlpToken), '"balanceOf(address)"', "<ADDRESS>");

        console.log("Check whitelist status:");
        console.log("cast call", address(nlpToken), '"whitelistedAddresses(address)"', "<ADDRESS>");

        console.log("Check NLP Exchange ETH balance:");
        console.log("cast balance [NLP_EXCHANGE_ADDRESS]");
        console.log("NLP_EXCHANGE_ADDRESS:", address(nlpExchange));

        console.log("Check exchange quote for 100 NLP to ETH:");
        console.log(
            "cast call [NLP_EXCHANGE_ADDRESS] \"getExchangeQuote(uint8,uint256)\" 0 \"100000000000000000000\""
        );
        console.log("NLP_EXCHANGE_ADDRESS:", address(nlpExchange));

        console.log("========================");
    }
}
