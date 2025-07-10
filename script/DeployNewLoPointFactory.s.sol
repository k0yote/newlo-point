// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { NewLoPointFactory } from "../src/NewLoPointFactory.sol";

/**
 * @title DeployNewLoPointFactory
 * @author NewLo Team
 * @notice Deployment script for NewLoPointFactory contract
 * @dev This script:
 *      - Deploys the NewLoPointFactory contract
 *      - The factory automatically creates a NewLoPoint implementation and ProxyAdmin during construction
 *      - Provides the foundation for deterministic token deployment using CREATE2
 *
 * @dev Environment Variables Required:
 *      - PRIVATE_KEY: Deployer's private key
 *
 * @dev Security Considerations:
 *      - The deployer becomes the owner of the ProxyAdmin created by the factory
 *      - The factory uses a shared implementation for all deployed tokens (gas efficient)
 *      - CREATE2 enables deterministic address calculation before deployment
 *
 * @dev Post-Deployment:
 *      - Factory can be used to deploy multiple NewLoPoint token instances
 *      - Each deployed token will use the same implementation but have independent state
 *      - Addresses can be predicted using the predictAddress function
 */
contract DeployNewLoPointFactory is Script {
    /**
     * @notice Main deployment function
     * @dev Deploys the NewLoPointFactory contract which includes:
     *      - NewLoPoint implementation contract (created in factory constructor)
     *      - ProxyAdmin contract (created in factory constructor)
     *      - Factory contract itself
     *
     * @dev Deployment Process:
     *      1. Read deployer private key from environment
     *      2. Start broadcast (prepare for on-chain deployment)
     *      3. Deploy NewLoPointFactory (which deploys implementation and ProxyAdmin internally)
     *      4. Stop broadcast (finalize deployment)
     *
     * @dev Gas Estimates:
     *      - NewLoPoint implementation: ~2.5M gas
     *      - ProxyAdmin: ~300K gas
     *      - Factory: ~500K gas
     *      - Total: ~3.3M gas
     */
    function run() external {
        // Read deployment parameters from environment
        uint pk = vm.envUint("PRIVATE_KEY");

        // Start broadcasting transactions to the network
        vm.startBroadcast(pk);

        // Deploy the factory (which automatically deploys implementation and ProxyAdmin)
        NewLoPointFactory factory = new NewLoPointFactory();

        vm.stopBroadcast();

        // Log deployed addresses for verification and future reference
        console2.log("Factory:", address(factory));
        console2.log("Implementation:", factory.implementation());
        console2.log("ProxyAdmin:", address(factory.proxyAdmin()));

        // Log example usage
        console2.log("\n=== Usage Example ===");
        console2.log("To deploy a new token:");
        console2.log("factory.deployToken(salt, admin, pauser, minter)");
        console2.log("\nTo predict deployment address:");
        console2.log("factory.predictAddress(salt, admin, pauser, minter)");
    }
}
