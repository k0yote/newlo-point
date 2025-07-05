// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import "../src/SoneiumETHDistribution.sol";

contract DeploySoneiumETHDistribution is Script {
    function run() external {
        uint deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployer = vm.addr(deployerPrivateKey);

        console.log("Deploying SoneiumETHDistribution...");
        console.log("Deployer address:", deployer);
        console.log("Deployer balance:", deployer.balance);

        vm.startBroadcast(deployerPrivateKey);

        // Deploy the contract with deployer as initial admin
        SoneiumETHDistribution distribution = new SoneiumETHDistribution(deployer);

        console.log("SoneiumETHDistribution deployed at:", address(distribution));
        console.log("Admin address:", deployer);

        // Grant additional roles to deployer for initial setup
        distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), deployer);
        distribution.grantRole(distribution.DEPOSIT_MANAGER_ROLE(), deployer);
        distribution.grantRole(distribution.PAUSER_ROLE(), deployer);

        console.log("All roles granted to deployer");

        // Optional: Set up anti-duplicate mode
        distribution.setAntiDuplicateMode(true);
        console.log("Anti-duplicate mode enabled");

        vm.stopBroadcast();

        console.log("Deployment completed successfully!");
        console.log("Contract address:", address(distribution));
        console.log("Remember to:");
        console.log("1. Fund the contract with ETH for distribution");
        console.log("2. Grant roles to appropriate addresses");
        console.log("3. Revoke unnecessary roles from deployer if needed");
    }
}
