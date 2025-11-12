// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { NLPBurnWithPermit } from "../src/NLPBurnWithPermit.sol";

/**
 * @title DeployNLPBurnWithPermit
 * @author NewLo Team
 * @notice Deployment script for NLPBurnWithPermit contract
 * @dev This script deploys the NLPBurnWithPermit contract with specified NLP token address
 *
 * @dev Environment Variables Required:
 *      - PRIVATE_KEY: Deployer's private key
 *      - NLP_TOKEN_ADDRESS: Address of the deployed NLP token
 *      - BURN_ADMIN: Address to receive all initial admin roles
 *
 * @dev Security Considerations:
 *      - The BURN_ADMIN receives DEFAULT_ADMIN_ROLE, OPERATOR_ROLE, PAUSER_ROLE, and WHITELIST_MANAGER_ROLE
 *      - Roles can be delegated to different addresses after deployment
 *      - Contract defaults to PUBLIC burn mode (anyone can burn)
 *
 * @dev Deployment Process:
 *      1. Read deployment parameters from environment
 *      2. Deploy NLPBurnWithPermit contract
 *      3. Contract is immediately ready to use
 *
 * @dev Usage Example:
 *      forge script script/DeployNLPBurnWithPermit.s.sol:DeployNLPBurnWithPermit \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify
 */
contract DeployNLPBurnWithPermit is Script {
    /**
     * @notice Main deployment function
     * @dev Reads environment variables and deploys the burn contract
     */
    function run() external {
        // Read deployment parameters from environment
        uint pk = vm.envUint("PRIVATE_KEY");
        address nlpTokenAddress = vm.envAddress("NLP_TOKEN_ADDRESS");
        address burnAdmin = vm.envAddress("BURN_ADMIN");

        // Validate addresses
        require(nlpTokenAddress != address(0), "Invalid NLP token address");
        require(burnAdmin != address(0), "Invalid burn admin address");

        console.log("Deploying NLPBurnWithPermit...");
        console.log("NLP Token Address:", nlpTokenAddress);
        console.log("Burn Admin:", burnAdmin);

        // Start broadcasting transactions
        vm.startBroadcast(pk);

        // Deploy the burn contract
        NLPBurnWithPermit burnContract = new NLPBurnWithPermit(nlpTokenAddress, burnAdmin);

        // Stop broadcasting
        vm.stopBroadcast();

        // Log deployment information
        console.log("========================================");
        console.log("NLPBurnWithPermit deployed at:", address(burnContract));
        console.log("========================================");
        console.log("Initial Configuration:");
        console.log("- Burn Mode: PUBLIC");
        console.log("- Admin:", burnAdmin);
        console.log("- NLP Token:", nlpTokenAddress);
        console.log("========================================");
        console.log("Next Steps:");
        console.log("1. Grant OPERATOR_ROLE to relayer addresses if needed");
        console.log("2. Set burn mode to WHITELIST if access control is required");
        console.log("3. Add addresses to whitelist if using WHITELIST mode");
        console.log("========================================");
    }
}
