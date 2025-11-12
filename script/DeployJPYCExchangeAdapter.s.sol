// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { NLPToJPYCExchangeAdapter } from "../src/NLPToJPYCExchangeAdapter.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {
    TransparentUpgradeableProxy
} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title DeployJPYCExchangeAdapter
 * @dev Deployment script for NLPToJPYCExchangeAdapter contract on Soneium mainnet
 * @notice This adapter facilitates cross-chain NLP (Soneium) to JPYC (Polygon) exchanges via escrow system
 */
contract DeployJPYCExchangeAdapter is Script {
    // Soneium mainnet addresses (Update these with actual addresses)
    address SONEIUM_ADMIN = vm.envAddress("SONEIUM_ADMIN");
    address SONEIUM_OPERATOR = vm.envAddress("SONEIUM_OPERATOR");

    // Token addresses (only NLP needed - JPYC is on Polygon)
    address SONEIUM_NLP_TOKEN = vm.envAddress("SONEIUM_NLP_TOKEN");

    // Configuration parameters
    uint INITIAL_NLP_TO_JPYC_RATE = vm.envOr("INITIAL_NLP_TO_JPYC_RATE", uint(100)); // 1:1 default (reference only)
    uint MIN_DEPOSIT_AMOUNT = vm.envOr("MIN_DEPOSIT_AMOUNT", uint(1e18)); // 1 NLP default

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToJPYCExchangeAdapter on Soneium...");
        console.log("Deployer:", deployer);

        // Validate addresses before deployment
        require(SONEIUM_ADMIN != address(0), "Admin address cannot be zero");
        require(SONEIUM_OPERATOR != address(0), "Operator address cannot be zero");
        require(SONEIUM_NLP_TOKEN != address(0), "NLP token address cannot be zero");
        require(INITIAL_NLP_TO_JPYC_RATE > 0, "Rate must be greater than zero");
        require(MIN_DEPOSIT_AMOUNT > 0, "Min deposit must be greater than zero");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the adapter contract (no JPYC token - it's on Polygon)
        // Default fee rates: 0% exchange fee, 0% operational fee
        NLPToJPYCExchangeAdapter adapter =
            new NLPToJPYCExchangeAdapter(SONEIUM_NLP_TOKEN, SONEIUM_ADMIN, 0, 0);

        console.log("NLPToJPYCExchangeAdapter deployed at:", address(adapter));

        // Grant roles to designated addresses
        adapter.grantRole(adapter.OPERATOR_ROLE(), SONEIUM_OPERATOR);
        adapter.grantRole(adapter.CONFIG_ROLE(), SONEIUM_ADMIN);
        adapter.grantRole(adapter.PAUSER_ROLE(), SONEIUM_ADMIN);

        console.log("Roles granted successfully");

        // Configure exchange rate if different from default
        if (INITIAL_NLP_TO_JPYC_RATE != 100) {
            adapter.updateNLPToJPYCRate(INITIAL_NLP_TO_JPYC_RATE);
            console.log("NLP to JPYC rate set to:", INITIAL_NLP_TO_JPYC_RATE);
        }

        // Configure minimum deposit amount if different from default
        if (MIN_DEPOSIT_AMOUNT != 1e18) {
            adapter.updateMinDepositAmount(MIN_DEPOSIT_AMOUNT);
            console.log("Minimum deposit amount set to:", MIN_DEPOSIT_AMOUNT / 1e18, "NLP");
        }

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("========================================");
        console.log("Contract Address:", address(adapter));
        console.log("Admin:", SONEIUM_ADMIN);
        console.log("Operator:", SONEIUM_OPERATOR);
        console.log("========================================");
        console.log("Token Configuration:");
        console.log("NLP Token (Soneium):", SONEIUM_NLP_TOKEN);
        console.log("NOTE: JPYC is on Polygon network, not on Soneium");
        console.log("========================================");
        console.log("Exchange Configuration:");
        console.log("NLP to JPYC Rate:", INITIAL_NLP_TO_JPYC_RATE, "/ 100");
        console.log("Min Deposit Amount:", MIN_DEPOSIT_AMOUNT / 1e18, "NLP");
        console.log("========================================");
        console.log("Next steps:");
        console.log("1. Verify contract on Soneium block explorer");
        console.log("2. Set up operational wallet with JPYC on Polygon network");
        console.log("3. Set up off-chain cross-chain bridge system");
        console.log("4. Configure monitoring and alerts");
        console.log("5. Test with small amounts first");
        console.log("6. Document operator procedures for cross-chain operations");
    }
}

/**
 * @title DeployJPYCExchangeAdapterLocal
 * @dev Local deployment script for testing
 */
contract DeployJPYCExchangeAdapterLocal is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToJPYCExchangeAdapter locally...");
        console.log("Deployer:", deployer);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy mock NLP token with proxy
        NewLoPoint nlpImpl = new NewLoPoint();
        ProxyAdmin nlpAdmin = new ProxyAdmin(deployer);
        bytes memory nlpData =
            abi.encodeWithSelector(nlpImpl.initialize.selector, deployer, deployer, deployer);
        TransparentUpgradeableProxy nlpProxy =
            new TransparentUpgradeableProxy(address(nlpImpl), address(nlpAdmin), nlpData);
        NewLoPoint nlpToken = NewLoPoint(address(nlpProxy));

        console.log("NLP Token deployed (Soneium):", address(nlpToken));
        console.log("NOTE: JPYC is on Polygon network, not deployed here");

        // Deploy the adapter contract (no JPYC token needed)
        // Default fee rates: 0% exchange fee, 0% operational fee
        NLPToJPYCExchangeAdapter adapter =
            new NLPToJPYCExchangeAdapter(address(nlpToken), deployer, 0, 0);

        console.log("NLPToJPYCExchangeAdapter deployed at:", address(adapter));

        // Grant additional roles for testing
        adapter.grantRole(adapter.OPERATOR_ROLE(), deployer);
        adapter.grantRole(adapter.CONFIG_ROLE(), deployer);
        adapter.grantRole(adapter.PAUSER_ROLE(), deployer);

        console.log("Roles granted to deployer for testing");

        // Enable global transfers for NLP
        nlpToken.setTransfersEnabled(true);
        console.log("Global transfers enabled for NLP");

        // Mint test NLP tokens to deployer
        uint testAmount = 10000e18;
        nlpToken.mint(deployer, testAmount);
        console.log("Minted", testAmount / 1e18, "NLP to deployer");

        // Test deposit with permit (depositNLP function was removed, only permit version available)
        // console.log("Testing deposit functionality...");
        // uint depositAmount = 100e18;
        // Note: Use depositNLPWithPermit instead of depositNLP
        // console.log("Use depositNLPWithPermit for gasless deposits");

        // Get escrow info (will be 0 until deposit is made)
        NLPToJPYCExchangeAdapter.UserEscrow memory escrow = adapter.getUserEscrow(deployer);
        console.log("Escrow balance:", escrow.currentBalance / 1e18, "NLP");

        vm.stopBroadcast();

        console.log("Local deployment completed successfully!");
        console.log("========================================");
        console.log("Contract Addresses:");
        console.log("Adapter:", address(adapter));
        console.log("NLP Token (Soneium):", address(nlpToken));
        console.log("NOTE: JPYC is on Polygon network");
        console.log("Admin/Operator:", deployer);
        console.log("========================================");
        console.log("Configuration:");
        console.log("NLP to JPYC Rate:", adapter.nlpToJpycRate(), "/ 100");
        console.log("Min Deposit:", adapter.minDepositAmount() / 1e18, "NLP");
        console.log("========================================");
        console.log("Backend Operations (OPERATOR_ROLE required):");
        console.log("Deposit (permit): adapter.depositNLPWithPermit(...)");
        console.log("Burn Escrow: adapter.burnEscrowedNLP(user, amount, reason)");
        console.log("Transfer/Refund: adapter.transferEscrowedNLP(from, to, amount, reason)");
        console.log("========================================");
    }
}

/**
 * @title DeployJPYCExchangeAdapterSoneium
 * @dev Deployment script specifically for Soneium Minato testnet
 * @notice JPYC is on Polygon network, not on Soneium
 */
contract DeployJPYCExchangeAdapterSoneium is Script {
    // Soneium Minato testnet addresses
    address constant SONEIUM_MINATO_ADMIN = address(0); // TODO: Set actual admin
    address constant SONEIUM_MINATO_OPERATOR = address(0); // TODO: Set actual operator
    address constant SONEIUM_MINATO_NLP_TOKEN = address(0); // TODO: Set actual NLP token on Soneium

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying NLPToJPYCExchangeAdapter on Soneium Minato...");
        console.log("Deployer:", deployer);

        // Validate addresses
        require(SONEIUM_MINATO_ADMIN != address(0), "Set ADMIN address");
        require(SONEIUM_MINATO_OPERATOR != address(0), "Set OPERATOR address");
        require(SONEIUM_MINATO_NLP_TOKEN != address(0), "Set NLP token address on Soneium");

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the adapter (JPYC is on Polygon, not Soneium)
        // Default fee rates: 0% exchange fee, 0% operational fee
        NLPToJPYCExchangeAdapter adapter =
            new NLPToJPYCExchangeAdapter(SONEIUM_MINATO_NLP_TOKEN, SONEIUM_MINATO_ADMIN, 0, 0);

        console.log("Deployed at:", address(adapter));

        // Grant roles
        adapter.grantRole(adapter.OPERATOR_ROLE(), SONEIUM_MINATO_OPERATOR);

        vm.stopBroadcast();

        console.log("Soneium Minato deployment completed!");
        console.log("Contract:", address(adapter));
    }
}
