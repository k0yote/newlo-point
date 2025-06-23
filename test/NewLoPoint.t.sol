// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import {NewLoPoint} from "../src/NewLoPoint.sol";
import {ProxyAdmin} from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import {TransparentUpgradeableProxy} from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract NewLoPointTest is Test {
    NewLoPoint impl;
    NewLoPoint token;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    address constant DEFAULT_ADMIN = address(0x1);
    address constant PAUSER        = address(0x2);
    address constant MINTER        = address(0x3);
    address constant USER_A        = address(0x4);
    address constant USER_B        = address(0x5);

    function setUp() public {
        impl  = new NewLoPoint();
        admin = new ProxyAdmin();

        bytes memory data = abi.encodeWithSelector(
            impl.initialize.selector,
            DEFAULT_ADMIN,
            PAUSER,
            MINTER
        );
        proxy = new TransparentUpgradeableProxy(address(impl), address(admin), data);
        token = NewLoPoint(address(proxy));
    }

    function testInitialTransferLock() public {
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);
        vm.prank(USER_A);
        vm.expectRevert(NewLoPoint.TransfersDisabled.selector);
        token.transfer(USER_B, 1 ether);
    }

    function testEnableTransfers() public {
        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);
        vm.prank(USER_A);
        token.transfer(USER_B, 1 ether);

        assertEq(token.balanceOf(USER_B), 1 ether);
    }

    function testPause() public {
        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        vm.prank(PAUSER);
        token.pause();

        vm.prank(USER_A);
        vm.expectRevert();
        token.transfer(USER_B, 1 ether);
    }
}
