// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { TokenDistributionV2 } from "../src/TokenDistributionV2.sol";
import { MultiTokenDistribution } from "../src/MultiTokenDistribution.sol";
import { ERC20DecimalsWithMint } from "../src/tokens/ERC20DecimalsWithMint.sol";

/**
 * @title DeployLocalScenario
 * @author NewLo Team
 * @notice ローカルAnvilでのフルシナリオデプロイスクリプト
 * @dev このスクリプトは以下を実行します：
 *      1. NewLoPointFactoryをデプロイ
 *      2. NewLoPointをデプロイ
 *      3. TokenDistributionV2をデプロイ
 *      4. MultiTokenDistributionをデプロイ
 *      5. Mock tokens（USDC、USDT、WETH）をデプロイ
 *      6. NewLoPointの設定（whitelist、transfer control）
 *      7. トークンの付与とロール設定
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

    // Mock tokens
    ERC20DecimalsWithMint public usdcToken;
    ERC20DecimalsWithMint public usdtToken;
    ERC20DecimalsWithMint public wethToken;

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

        // 5. Mock tokensをデプロイ
        _deployMockTokens();

        // 6. NewLoPointの設定
        _configureNewLoPoint();

        // 7. トークンの付与とロール設定
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

        // Whitelist機能をオン
        nlpToken.setWhitelistModeEnabled(true);
        console.log("Enabled whitelist mode");

        // Transfer機能をオン（後で必要に応じてオフにできる）
        nlpToken.setTransfersEnabled(true);
        console.log("Enabled transfers");

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

        vm.stopBroadcast();
        vm.startBroadcast(0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80);

        // TokenDistributionV2に10000 NLPを付与
        uint amount = 10000 * 10 ** 18;
        nlpToken.mint(address(tokenDistV2), amount);
        console.log("Minted 10000 NLP to TokenDistributionV2");

        // MultiTokenDistributionに10000 NLPを付与
        nlpToken.mint(address(multiTokenDist), amount);
        console.log("Minted 10000 NLP to MultiTokenDistribution");

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
        console.log("TokenDistV2 Balance:", nlpToken.balanceOf(address(tokenDistV2)) / 10 ** 18);
        console.log(
            "MultiTokenDist Balance:", nlpToken.balanceOf(address(multiTokenDist)) / 10 ** 18
        );

        console.log("\n=== ROLES ===");
        console.log(
            "NLP MINTER_ROLE for TokenDistV2:",
            nlpToken.hasRole(nlpToken.MINTER_ROLE(), address(tokenDistV2))
        );
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

        console.log("========================");
    }
}
