// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Script } from "forge-std/Script.sol";
import { console } from "forge-std/console.sol";
import { MultiTokenDistribution } from "../src/MultiTokenDistribution.sol";

/**
 * @title DeployMultiTokenDistribution
 * @author NewLo Team
 * @notice Deployment script for MultiTokenDistribution contract
 * @dev This script deploys the MultiTokenDistribution contract and optionally sets up
 *      the initial token configuration for Soneium network
 */
contract DeployMultiTokenDistribution is Script {
    /* ═══════════════════════════════════════════════════════════════════════
                            SONEIUM MAINNET ADDRESSES
    ═══════════════════════════════════════════════════════════════════════ */

    address public constant SONEIUM_WETH = 0x4200000000000000000000000000000000000006;
    address public constant SONEIUM_USDT = 0x3A337a6adA9d885b6Ad95ec48F9b75f197b5AE35;
    address public constant SONEIUM_USDC = 0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369;
    address public constant SONEIUM_WSTETH = 0xaA9BD8c957D803466FA92504BDd728cC140f8941;
    address public constant SONEIUM_STETH = 0x0Ce031AEd457C870D74914eCAA7971dd3176cDAF;
    address public constant SONEIUM_ASTR = 0x2CAE934a1e84F693fbb78CA5ED3B0A6893259441;

    /* ═══════════════════════════════════════════════════════════════════════
                            SONEIUM MINATO ADDRESSES
    ═══════════════════════════════════════════════════════════════════════ */

    address public constant MINATO_WETH = 0x4200000000000000000000000000000000000006;
    address public constant MINATO_USDC = 0xE9A198d38483aD727ABC8b0B1e16B2d338CF0391;
    address public constant MINATO_WSTETH = 0x5717D6A621aA104b0b4cAd32BFe6AD3b659f269E;

    /* ═══════════════════════════════════════════════════════════════════════
                              DEPLOYMENT LOGIC
    ═══════════════════════════════════════════════════════════════════════ */

    function run() external {
        // Get deployer information
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        // Start broadcasting transactions
        vm.startBroadcast(deployerPrivateKey);

        // Deploy MultiTokenDistribution
        MultiTokenDistribution distribution = new MultiTokenDistribution(deployer);

        console.log("MultiTokenDistribution deployed at:", address(distribution));

        // Setup initial tokens based on chain ID
        uint chainId = block.chainid;
        console.log("Chain ID:", chainId);

        if (chainId == 1868) {
            // Soneium Mainnet
            console.log("Setting up tokens for Soneium Mainnet...");
            _setupSoneiumMainnetTokens(distribution);
        } else if (chainId == 1946) {
            // Soneium Minato (Testnet)
            console.log("Setting up tokens for Soneium Minato (Testnet)...");
            _setupSoneiumMinatoTokens(distribution);
        } else {
            console.log("Unknown chain ID, skipping token setup");
        }

        vm.stopBroadcast();

        // Log deployment summary
        _logDeploymentSummary(distribution);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              SETUP FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    function _setupSoneiumMainnetTokens(MultiTokenDistribution distribution) internal {
        // Add WETH
        distribution.addToken("WETH", SONEIUM_WETH, 18);
        console.log("Added WETH:", SONEIUM_WETH);

        // Add USDT
        distribution.addToken("USDT", SONEIUM_USDT, 6);
        console.log("Added USDT:", SONEIUM_USDT);

        // Add Bridged USDC
        distribution.addToken("USDC", SONEIUM_USDC, 6);
        console.log("Added USDC:", SONEIUM_USDC);

        // Add wstETH
        distribution.addToken("wstETH", SONEIUM_WSTETH, 18);
        console.log("Added wstETH:", SONEIUM_WSTETH);

        // Add stETH
        distribution.addToken("stETH", SONEIUM_STETH, 18);
        console.log("Added stETH:", SONEIUM_STETH);

        // Add ASTR
        distribution.addToken("ASTR", SONEIUM_ASTR, 18);
        console.log("Added ASTR:", SONEIUM_ASTR);
    }

    function _setupSoneiumMinatoTokens(MultiTokenDistribution distribution) internal {
        // Add WETH
        distribution.addToken("WETH", MINATO_WETH, 18);
        console.log("Added WETH:", MINATO_WETH);

        // Add Bridged USDC
        distribution.addToken("USDC", MINATO_USDC, 6);
        console.log("Added USDC:", MINATO_USDC);

        // Add wstETH
        distribution.addToken("wstETH", MINATO_WSTETH, 18);
        console.log("Added wstETH:", MINATO_WSTETH);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              UTILITY FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    function _logDeploymentSummary(MultiTokenDistribution distribution) internal view {
        console.log("\n=== DEPLOYMENT SUMMARY ===");
        console.log("Contract Address:", address(distribution));
        console.log("Owner:", distribution.owner());
        console.log("Token Count:", distribution.getTokenCount());
        console.log("Total Distributions:", distribution.totalDistributions());
        console.log("Total Users:", distribution.totalUsers());
        console.log("Paused:", distribution.paused());

        // Log supported tokens
        string[] memory symbols = distribution.getAllTokenSymbols();
        console.log("\nSupported Tokens:");
        for (uint i = 0; i < symbols.length; i++) {
            (
                address tokenAddress,
                uint8 decimals,
                bool isActive,
                uint totalDistributed,
                uint totalUsers
            ) = distribution.supportedTokens(symbols[i]);

            console.log(
                string(
                    abi.encodePacked(
                        "  ",
                        symbols[i],
                        " (",
                        _addressToString(tokenAddress),
                        ")",
                        " - Decimals: ",
                        _uint8ToString(decimals),
                        " - Active: ",
                        isActive ? "true" : "false"
                    )
                )
            );
        }
        console.log("========================\n");
    }

    function _addressToString(address addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint(uint160(addr)));
        bytes memory alphabet = "0123456789abcdef";
        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";
        for (uint i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }
        return string(str);
    }

    function _uint8ToString(uint8 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint8 temp = value;
        uint8 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint8(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}

/* ═══════════════════════════════════════════════════════════════════════
                            SEPARATE DEPLOYMENT SCRIPTS
═══════════════════════════════════════════════════════════════════════ */

/**
 * @title DeployMultiTokenDistributionOnly
 * @notice Deploy only the contract without setting up tokens
 */
contract DeployMultiTokenDistributionOnly is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        MultiTokenDistribution distribution = new MultiTokenDistribution(deployer);

        console.log("MultiTokenDistribution deployed at:", address(distribution));

        vm.stopBroadcast();
    }
}

/**
 * @title SetupTokensScript
 * @notice Setup tokens for an already deployed contract
 */
contract SetupTokensScript is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address distributionAddress = vm.envAddress("DISTRIBUTION_ADDRESS");

        MultiTokenDistribution distribution = MultiTokenDistribution(distributionAddress);

        console.log("Setting up tokens for contract at:", distributionAddress);
        console.log("Chain ID:", block.chainid);

        vm.startBroadcast(deployerPrivateKey);

        if (block.chainid == 1868) {
            _setupSoneiumMainnetTokens(distribution);
        } else if (block.chainid == 1946) {
            _setupSoneiumMinatoTokens(distribution);
        } else {
            console.log("Unknown chain ID, please setup tokens manually");
        }

        vm.stopBroadcast();
    }

    function _setupSoneiumMainnetTokens(MultiTokenDistribution distribution) internal {
        distribution.addToken("WETH", 0x4200000000000000000000000000000000000006, 18);
        distribution.addToken("USDT", 0x3A337a6adA9d885b6Ad95ec48F9b75f197b5AE35, 6);
        distribution.addToken("USDC", 0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369, 6);
        distribution.addToken("wstETH", 0xaA9BD8c957D803466FA92504BDd728cC140f8941, 18);
        distribution.addToken("stETH", 0x0Ce031AEd457C870D74914eCAA7971dd3176cDAF, 18);
        distribution.addToken("ASTR", 0x2CAE934a1e84F693fbb78CA5ED3B0A6893259441, 18);
    }

    function _setupSoneiumMinatoTokens(MultiTokenDistribution distribution) internal {
        distribution.addToken("WETH", 0x4200000000000000000000000000000000000006, 18);
        distribution.addToken("USDC", 0xE9A198d38483aD727ABC8b0B1e16B2d338CF0391, 6);
        distribution.addToken("wstETH", 0x5717D6A621aA104b0b4cAd32BFe6AD3b659f269E, 18);
    }
}
