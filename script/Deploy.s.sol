// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/**
 * @title Deploy
 * @author NewLo Team
 * @notice Deployment script for NewLoPoint token using OpenZeppelin's upgradeable proxy pattern
 * @dev This script:
 *      - Deploys the NewLoPoint implementation contract
 *      - Deploys a ProxyAdmin for upgrade management
 *      - Deploys a TransparentUpgradeableProxy pointing to the implementation
 *      - Initializes the proxy with the specified role addresses
 *
 * @dev Environment Variables Required:
 *      - PRIVATE_KEY: Deployer's private key
 *      - DEFAULT_ADMIN: Address to receive admin and whitelist manager roles
 *      - PAUSER: Address to receive pause/unpause role
 *      - MINTER: Address to receive token minting role
 *
 * @dev Security Considerations:
 *      - The deployer becomes the owner of the ProxyAdmin contract
 *      - Role addresses should be carefully chosen and secured
 *      - Implementation contract cannot be initialized directly (disabled in constructor)
 *      - Proxy is immediately initialized to prevent takeover attacks
 *
 * @dev Deployment Order:
 *      1. NewLoPoint implementation (logic contract)
 *      2. ProxyAdmin (upgrade management)
 *      3. TransparentUpgradeableProxy (user-facing contract)
 *      4. Initialize proxy with role assignments
 */
contract Deploy is Script {
    /**
     * @notice Main deployment function
     * @dev Reads environment variables and deploys the complete token system
     * @dev Uses Foundry's vm.envUint and vm.envAddress for secure environment variable access
     *
     * @dev Deployment Process:
     *      1. Read deployment parameters from environment
     *      2. Start broadcast (prepare for on-chain deployment)
     *      3. Deploy implementation contract
     *      4. Deploy ProxyAdmin with deployer as owner
     *      5. Encode initialization data for the proxy
     *      6. Deploy TransparentUpgradeableProxy with initialization
     *      7. Stop broadcast (finalize deployment)
     *
     * @dev Gas Estimates:
     *      - Implementation: ~2.5M gas
     *      - ProxyAdmin: ~300K gas
     *      - Proxy: ~400K gas
     *      - Total: ~3.2M gas
     */
    function run() external {
        // Read deployment parameters from environment
        uint pk = vm.envUint("PRIVATE_KEY");
        address admin = vm.envAddress("DEFAULT_ADMIN");
        address pauser = vm.envAddress("PAUSER");
        address minter = vm.envAddress("MINTER");

        // Start broadcasting transactions to the network
        vm.startBroadcast(pk);

        // Deploy the implementation contract (logic)
        NewLoPoint impl = new NewLoPoint();
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

        // Encode initialization data for the proxy
        bytes memory data = abi.encodeWithSelector(impl.initialize.selector, admin, pauser, minter);

        // Deploy the proxy and initialize it in one transaction
        TransparentUpgradeableProxy proxy =
            new TransparentUpgradeableProxy(address(impl), address(proxyAdmin), data);

        vm.stopBroadcast();

        // Log deployed addresses for verification and future reference
        // These addresses should be saved for contract interactions and upgrades
        console2.log("Implementation:", address(impl));
        console2.log("Proxy:", address(proxy));
        console2.log("ProxyAdmin:", address(proxyAdmin));
    }
}
