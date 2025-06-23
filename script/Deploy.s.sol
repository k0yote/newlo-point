// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Script.sol";
import {NewLoPoint} from "../src/NewLoPoint.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract Deploy is Script {
    function run() external {
        uint256 pk     = vm.envUint("PRIVATE_KEY");
        address admin  = vm.envAddress("DEFAULT_ADMIN");
        address pauser = vm.envAddress("PAUSER");
        address minter = vm.envAddress("MINTER");

        vm.startBroadcast(pk);

        NewLoPoint impl = new NewLoPoint();
        ProxyAdmin proxyAdmin = new ProxyAdmin(admin);

        bytes memory data = abi.encodeWithSelector(
            impl.initialize.selector,
            admin,
            pauser,
            minter
        );

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            address(proxyAdmin),
            data
        );

        vm.stopBroadcast();

        console2.log("Implementation:", address(impl));
        console2.log("Proxy:", address(proxy));
        console2.log("ProxyAdmin:", address(proxyAdmin));
    }
}
