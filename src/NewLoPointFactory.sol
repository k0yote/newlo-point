// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { Create2 } from "@openzeppelin/contracts/utils/Create2.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { NewLoPoint } from "./NewLoPoint.sol";

/**
 * @title NewLoPointFactory
 * @author NewLo Team
 * @notice Factory contract for deploying NewLoPoint token instances using CREATE2 for deterministic addresses
 * @dev This contract:
 *      - Deploys NewLoPoint tokens behind TransparentUpgradeableProxy
 *      - Uses CREATE2 for deterministic deployment addresses
 *      - Manages a single ProxyAdmin for all deployed tokens
 *      - Provides address prediction functionality
 *
 * @dev Security Considerations:
 *      - Uses CREATE2 for deterministic addresses, but salt collision attacks are mitigated by proper salt management
 *      - All deployed tokens share the same implementation contract (gas efficient)
 *      - ProxyAdmin is created once and reused for all deployments
 *      - Factory deployer becomes the owner of the ProxyAdmin
 *
 * @dev Deployment Pattern:
 *      Implementation → ProxyAdmin → Factory → [Token Proxies...]
 *      - Implementation: The logic contract (NewLoPoint)
 *      - ProxyAdmin: Manages proxy upgrades
 *      - Factory: Deploys individual token instances
 *      - Token Proxies: Individual token instances with their own state
 */
contract NewLoPointFactory {
    /* ═══════════════════════════════════════════════════════════════════════
                              IMMUTABLE STATE
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice The implementation contract address used for all deployed tokens
    /// @dev This is set once during construction and cannot be changed
    /// @dev All proxy contracts will delegate calls to this implementation
    address public immutable implementation;

    /// @notice The ProxyAdmin contract used to manage all deployed token proxies
    /// @dev This is set once during construction and cannot be changed
    /// @dev The factory deployer becomes the owner of this ProxyAdmin
    ProxyAdmin public immutable proxyAdmin;

    /* ═══════════════════════════════════════════════════════════════════════
                                   EVENTS
    ═══════════════════════════════════════════════════════════════════════ */

    /// @notice Emitted when a new token is deployed
    /// @param proxy The address of the deployed proxy contract
    /// @param salt The salt used for CREATE2 deployment
    event TokenDeployed(address indexed proxy, bytes32 salt);

    /* ═══════════════════════════════════════════════════════════════════════
                                CONSTRUCTOR
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Deploy the factory with a new implementation and ProxyAdmin
     * @dev Creates a new NewLoPoint implementation and ProxyAdmin during construction
     * @dev The deployer of this factory becomes the owner of the ProxyAdmin
     *
     * @dev Gas Cost: High (deploys two contracts)
     * @dev Security: Implementation contract is deployed in constructor, making it immutable
     */
    constructor() {
        implementation = address(new NewLoPoint());
        proxyAdmin = new ProxyAdmin(msg.sender);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                            DEPLOYMENT FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Deploy a new NewLoPoint token using CREATE2
     * @dev Creates a TransparentUpgradeableProxy pointing to the shared implementation
     * @dev The proxy is immediately initialized with the provided parameters
     *
     * @param salt Unique salt for CREATE2 deployment (affects final address)
     * @param admin Address that will receive DEFAULT_ADMIN_ROLE and WHITELIST_MANAGER_ROLE
     * @param pauser Address that will receive PAUSER_ROLE
     * @param minter Address that will receive MINTER_ROLE
     * @return proxy The address of the deployed proxy contract
     *
     * Requirements:
     * - Salt must result in a unique address (function will revert on collision)
     * - All role addresses should be non-zero (though not enforced here)
     *
     * @dev Security Notes:
     *      - Uses deterministic CREATE2 deployment
     *      - Proxy is immediately initialized to prevent takeover
     *      - All deployed tokens use the same implementation (upgrade consistency)
     *
     * Emits:
     * - TokenDeployed event with the new proxy address and salt
     */
    function deployToken(bytes32 salt, address admin, address pauser, address minter)
        external
        returns (address proxy)
    {
        bytes memory initData =
            abi.encodeWithSelector(NewLoPoint.initialize.selector, admin, pauser, minter);

        bytes memory proxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(implementation, address(proxyAdmin), initData)
        );

        proxy = Create2.deploy(0, salt, proxyBytecode);
        emit TokenDeployed(proxy, salt);
    }

    /* ═══════════════════════════════════════════════════════════════════════
                              UTILITY FUNCTIONS
    ═══════════════════════════════════════════════════════════════════════ */

    /**
     * @notice Predict the address of a token deployment without actually deploying
     * @dev Useful for off-chain address calculation and verification
     * @dev The predicted address will be accurate if the same parameters are used for deployment
     *
     * @param salt Unique salt for CREATE2 deployment
     * @param admin Address that will receive DEFAULT_ADMIN_ROLE and WHITELIST_MANAGER_ROLE
     * @param pauser Address that will receive PAUSER_ROLE
     * @param minter Address that will receive MINTER_ROLE
     * @return predicted The address where the token would be deployed
     *
     * @dev Use Cases:
     *      - Frontend address calculation before deployment
     *      - Verification of deployment parameters
     *      - Integration with other contracts that need to know the address in advance
     *
     * @dev Gas Cost: Low (view function, no state changes)
     */
    function predictAddress(bytes32 salt, address admin, address pauser, address minter)
        external
        view
        returns (address predicted)
    {
        bytes memory initData =
            abi.encodeWithSelector(NewLoPoint.initialize.selector, admin, pauser, minter);

        bytes memory proxyBytecode = abi.encodePacked(
            type(TransparentUpgradeableProxy).creationCode,
            abi.encode(implementation, address(proxyAdmin), initData)
        );

        predicted = Create2.computeAddress(salt, keccak256(proxyBytecode));
    }
}
