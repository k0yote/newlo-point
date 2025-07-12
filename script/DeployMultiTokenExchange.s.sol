// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { MultiTokenExchange } from "../src/MultiTokenExchange.sol";

/**
 * @title DeployMultiTokenExchange
 * @author NewLo Team
 * @notice Deployment script for MultiTokenExchange contract
 * @dev This script supports deployment with:
 *      - Environment variables: NLP_TOKEN_ADDRESS, USDC_TOKEN_ADDRESS, USDT_TOKEN_ADDRESS
 *      - Chain-specific fallback addresses for known networks
 *      - Validation that addresses are properly set before deployment
 */
contract DeployMultiTokenExchange is Script {
    
    /* ═══════════════════════════════════════════════════════════════════════
                              CHAIN-SPECIFIC TOKEN ADDRESSES
    ═══════════════════════════════════════════════════════════════════════ */

    // Soneium Mainnet Token Addresses (Chain ID: 1946)
    address constant SONEIUM_USDC_TOKEN = 0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369;
    address constant SONEIUM_USDT_TOKEN = 0x3A337a6adA9d885b6Ad95ec48F9b75f197b5AE35;

    // Soneium Minato (Testnet) Token Addresses (Chain ID: 1945)
    address constant MINATO_USDC_TOKEN = 0xE9A198d38483aD727ABC8b0B1e16B2d338CF0391;
    address constant MINATO_USDT_TOKEN = address(0); // Not available on testnet

    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("=== DEPLOY MULTI TOKEN EXCHANGE ===");
        console.log("Deployer:", deployer);
        console.log("Chain ID:", block.chainid);

        // Get token addresses from environment variables or chain-specific defaults
        address nlpTokenAddress = _getNLPTokenAddress();
        address usdcTokenAddress = _getUSDCTokenAddress();
        address usdtTokenAddress = _getUSDTTokenAddress();

        // Validate that all required addresses are set
        require(nlpTokenAddress != address(0), "NLP token address cannot be zero");
        require(usdcTokenAddress != address(0), "USDC token address cannot be zero");
        require(usdtTokenAddress != address(0), "USDT token address cannot be zero");

        console.log("NLP Token:", nlpTokenAddress);
        console.log("USDC Token:", usdcTokenAddress);
        console.log("USDT Token:", usdtTokenAddress);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy MultiTokenExchange contract
        MultiTokenExchange multiTokenExchange = new MultiTokenExchange(
            nlpTokenAddress,
            usdcTokenAddress,
            usdtTokenAddress
        );

        console.log("MultiTokenExchange deployed at:", address(multiTokenExchange));

        vm.stopBroadcast();
    }

    /**
     * @dev Get NLP token address from environment variable
     * @return The NLP token address
     */
    function _getNLPTokenAddress() internal view returns (address) {
        // Try to get from environment variable first
        try vm.envAddress("NLP_TOKEN_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        // Try legacy environment variable name
        try vm.envAddress("NLP_TOKEN") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        // No chain-specific fallback for NLP token - must be provided via environment
        return address(0);
    }

    /**
     * @dev Get USDC token address from environment variable or chain-specific default
     * @return The USDC token address
     */
    function _getUSDCTokenAddress() internal view returns (address) {
        // Try to get from environment variable first
        try vm.envAddress("USDC_TOKEN_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        // Fall back to chain-specific addresses
        if (block.chainid == 1946) {
            return SONEIUM_USDC_TOKEN;
        } else if (block.chainid == 1945) {
            return MINATO_USDC_TOKEN;
        }

        return address(0);
    }

    /**
     * @dev Get USDT token address from environment variable or chain-specific default
     * @return The USDT token address
     */
    function _getUSDTTokenAddress() internal view returns (address) {
        // Try to get from environment variable first
        try vm.envAddress("USDT_TOKEN_ADDRESS") returns (address addr) {
            if (addr != address(0)) {
                return addr;
            }
        } catch {}

        // Fall back to chain-specific addresses
        if (block.chainid == 1946) {
            return SONEIUM_USDT_TOKEN;
        } else if (block.chainid == 1945) {
            return MINATO_USDT_TOKEN;
        }

        return address(0);
    }
}