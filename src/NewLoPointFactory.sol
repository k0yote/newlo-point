// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import {Create2}                         from "@openzeppelin/contracts/utils/Create2.sol";
import {TransparentUpgradeableProxy}    from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import {ProxyAdmin}                     from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {NewLoPoint}                     from "./NewLoPoint.sol";

contract NewLoPointFactory {
    address public immutable implementation;
    ProxyAdmin public immutable proxyAdmin;

    event TokenDeployed(address indexed proxy, bytes32 salt);

    constructor() {
        implementation = address(new NewLoPoint());
        proxyAdmin = new ProxyAdmin();
    }

    function deployToken(
        bytes32 salt,
        address admin,
        address pauser,
        address minter
    ) external returns (address proxy) {
        bytes memory initData = abi.encodeWithSelector(
            NewLoPoint.initialize.selector,
            admin,
            pauser,
            minter
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(implementation, address(proxyAdmin), initData)
        );

        proxy = Create2.deploy(0, salt, proxyBytecode);
        emit TokenDeployed(proxy, salt);
    }

    function predictAddress(
        bytes32 salt,
        address admin,
        address pauser,
        address minter
    ) external view returns (address predicted) {
        bytes memory initData = abi.encodeWithSelector(
            NewLoPoint.initialize.selector,
            admin,
            pauser,
            minter
        );

        bytes memory proxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(implementation, address(proxyAdmin), initData)
        );

        predicted = Create2.computeAddress(salt, keccak256(proxyBytecode));
    }
}
