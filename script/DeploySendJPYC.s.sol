// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import { SendJPYC } from "../src/SendJPYC.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/**
 * @title DeploySendJPYC
 * @author NewLo Team
 * @notice Deployment script for SendJPYC contract with UUPS proxy
 * @dev This script deploys the SendJPYC contract behind an ERC1967 proxy for upgradeability
 *
 * @dev Environment Variables Required:
 *      - PRIVATE_KEY: Deployer's private key
 *      - JPYC_TOKEN_ADDRESS: Address of the JPYC token contract
 *      - SEND_JPYC_ADMIN: Address to receive all initial admin roles
 *
 * @dev Security Considerations:
 *      - The SEND_JPYC_ADMIN receives DEFAULT_ADMIN_ROLE, OPERATOR_ROLE, and PAUSER_ROLE
 *      - Roles can be delegated to different addresses after deployment
 *      - Only DEFAULT_ADMIN_ROLE can upgrade the contract
 *
 * @dev Deployment Process:
 *      1. Read deployment parameters from environment
 *      2. Deploy SendJPYC implementation contract
 *      3. Deploy ERC1967Proxy pointing to implementation
 *      4. Contract is immediately ready to use
 *
 * @dev Usage Example:
 *      forge script script/DeploySendJPYC.s.sol:DeploySendJPYC \
 *          --rpc-url $RPC_URL \
 *          --broadcast \
 *          --verify
 *
 * @dev Post-Deployment Configuration:
 *      1. Grant OPERATOR_ROLE to relayer/backend addresses
 *      2. Grant PAUSER_ROLE to security monitoring addresses
 *      3. Consider revoking OPERATOR_ROLE from admin if not needed
 */
contract DeploySendJPYC is Script {
    /**
     * @notice Main deployment function
     * @dev Reads environment variables and deploys the SendJPYC contract with proxy
     */
    function run() external {
        // Read deployment parameters from environment
        uint pk = vm.envUint("PRIVATE_KEY");
        address jpycTokenAddress = vm.envAddress("JPYC_TOKEN_ADDRESS");
        address admin = vm.envAddress("SEND_JPYC_ADMIN");

        // Validate addresses
        require(jpycTokenAddress != address(0), "Invalid JPYC token address");
        require(admin != address(0), "Invalid admin address");

        console.log("========================================");
        console.log("Deploying SendJPYC with UUPS Proxy...");
        console.log("========================================");
        console.log("JPYC Token Address:", jpycTokenAddress);
        console.log("Admin:", admin);
        console.log("========================================");

        // Start broadcasting transactions
        vm.startBroadcast(pk);

        // Deploy implementation contract
        SendJPYC implementation = new SendJPYC();
        console.log("Implementation deployed at:", address(implementation));

        // Prepare initialization data
        bytes memory initData =
            abi.encodeWithSelector(SendJPYC.initialize.selector, jpycTokenAddress, admin);

        // Deploy proxy contract
        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), initData);
        console.log("Proxy deployed at:", address(proxy));

        // Stop broadcasting
        vm.stopBroadcast();

        // Log deployment information
        console.log("========================================");
        console.log("DEPLOYMENT SUCCESSFUL");
        console.log("========================================");
        console.log("SendJPYC Proxy Address:", address(proxy));
        console.log("SendJPYC Implementation:", address(implementation));
        console.log("========================================");
        console.log("Initial Configuration:");
        console.log("- Admin:", admin);
        console.log("- JPYC Token:", jpycTokenAddress);
        console.log("- Roles granted to admin:");
        console.log("  * DEFAULT_ADMIN_ROLE");
        console.log("  * OPERATOR_ROLE");
        console.log("  * PAUSER_ROLE");
        console.log("========================================");
        console.log("Next Steps:");
        console.log("1. Grant OPERATOR_ROLE to relayer/backend addresses");
        console.log("2. Grant PAUSER_ROLE to security monitoring addresses");
        console.log("3. Verify contract on block explorer");
        console.log("4. Test sendWithPermit and sendWithAuthorization");
        console.log("========================================");
        console.log("Contract Verification Command:");
        console.log("forge verify-contract <PROXY_ADDRESS> SendJPYC --watch");
        console.log("========================================");
    }

    /**
     * @notice Deploy to a specific network with custom parameters
     * @param jpycToken The JPYC token address
     * @param admin The admin address
     * @return proxy The deployed proxy address
     * @return implementation The deployed implementation address
     */
    function deploy(address jpycToken, address admin)
        external
        returns (address proxy, address implementation)
    {
        require(jpycToken != address(0), "Invalid JPYC token address");
        require(admin != address(0), "Invalid admin address");

        // Deploy implementation
        SendJPYC impl = new SendJPYC();
        implementation = address(impl);

        // Prepare initialization data
        bytes memory initData =
            abi.encodeWithSelector(SendJPYC.initialize.selector, jpycToken, admin);

        // Deploy proxy
        ERC1967Proxy proxyContract = new ERC1967Proxy(implementation, initData);
        proxy = address(proxyContract);
    }
}
