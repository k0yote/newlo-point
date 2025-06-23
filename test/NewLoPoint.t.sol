// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import "forge-std/Test.sol";
import { NewLoPoint } from "../src/NewLoPoint.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from
    "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

contract NewLoPointTest is Test {
    NewLoPoint impl;
    NewLoPoint token;
    ProxyAdmin admin;
    TransparentUpgradeableProxy proxy;

    address constant DEFAULT_ADMIN = address(0x1);
    address constant PAUSER = address(0x2);
    address constant MINTER = address(0x3);
    address constant USER_A = address(0x4);
    address constant USER_B = address(0x5);
    address constant EXCHANGE = address(0x6);

    function setUp() public {
        impl = new NewLoPoint();
        admin = new ProxyAdmin(DEFAULT_ADMIN);

        bytes memory data =
            abi.encodeWithSelector(impl.initialize.selector, DEFAULT_ADMIN, PAUSER, MINTER);
        proxy = new TransparentUpgradeableProxy(address(impl), address(admin), data);
        token = NewLoPoint(address(proxy));
    }

    function testInitialState() public {
        assertFalse(token.transfersEnabled());
        assertFalse(token.whitelistModeEnabled());
        assertFalse(token.whitelistedAddresses(USER_A));
    }

    function testInitialTransferLock() public {
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);
        vm.prank(USER_A);
        vm.expectRevert(NewLoPoint.TransfersDisabled.selector);
        token.transfer(USER_B, 1 ether);
    }

    function testEnableTransfers() public {
        // イベントの確認
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.TransfersEnabledChanged(true);

        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        assertTrue(token.transfersEnabled());

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);
        vm.prank(USER_A);
        token.transfer(USER_B, 1 ether);

        assertEq(token.balanceOf(USER_B), 1 ether);
    }

    function testWhitelistMode() public {
        // ホワイトリストモードを有効化
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.WhitelistModeChanged(true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        assertTrue(token.whitelistModeEnabled());

        // 交換所をホワイトリストに追加
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.AddressWhitelisted(EXCHANGE, true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistedAddress(EXCHANGE, true);

        assertTrue(token.whitelistedAddresses(EXCHANGE));

        // ユーザーAにトークンをmint
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // 通常ユーザー間の転送は失敗
        vm.prank(USER_A);
        vm.expectRevert(NewLoPoint.NotWhitelisted.selector);
        token.transfer(USER_B, 1 ether);

        // ホワイトリストされた交換所への転送は成功
        vm.prank(USER_A);
        token.transfer(EXCHANGE, 1 ether);
        assertEq(token.balanceOf(EXCHANGE), 1 ether);

        // ホワイトリストされた交換所からの転送も成功
        vm.prank(EXCHANGE);
        token.transfer(USER_B, 0.5 ether);
        assertEq(token.balanceOf(USER_B), 0.5 ether);
    }

    function testBatchWhitelist() public {
        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        address[] memory addresses = new address[](2);
        addresses[0] = EXCHANGE;
        addresses[1] = USER_A;

        // バッチでホワイトリスト追加
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.AddressWhitelisted(EXCHANGE, true);
        vm.expectEmit(true, true, true, true);
        emit NewLoPoint.AddressWhitelisted(USER_A, true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistedAddresses(addresses, true);

        assertTrue(token.whitelistedAddresses(EXCHANGE));
        assertTrue(token.whitelistedAddresses(USER_A));
    }

    function testWhitelistOverridesTransferLock() public {
        // 転送無効、ホワイトリストモード有効
        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistedAddress(USER_A, true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // ホワイトリストされたユーザーは転送可能
        vm.prank(USER_A);
        token.transfer(USER_B, 1 ether);
        assertEq(token.balanceOf(USER_B), 1 ether);
    }

    function testFullTransferEnableOverridesWhitelist() public {
        // ホワイトリストモード有効、但し全転送も有効
        vm.prank(DEFAULT_ADMIN);
        token.setWhitelistModeEnabled(true);

        vm.prank(DEFAULT_ADMIN);
        token.setTransfersEnabled(true);

        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);

        // 全転送が有効なので、ホワイトリストされていなくても転送可能
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

    function testAccessControl() public {
        // 権限のないユーザーは転送設定を変更できない
        vm.prank(USER_A);
        vm.expectRevert();
        token.setTransfersEnabled(true);

        vm.prank(USER_A);
        vm.expectRevert();
        token.setWhitelistModeEnabled(true);

        vm.prank(USER_A);
        vm.expectRevert();
        token.setWhitelistedAddress(USER_B, true);

        // MINTERロールを持つアドレスのみMint可能
        vm.prank(USER_A);
        vm.expectRevert();
        token.mint(USER_B, 100 ether);
    }

    function testMintBurnAlwaysAllowed() public {
        // 転送が無効でもMint/Burnは常に可能
        vm.prank(MINTER);
        token.mint(USER_A, 100 ether);
        assertEq(token.balanceOf(USER_A), 100 ether);

        vm.prank(USER_A);
        token.burn(50 ether);
        assertEq(token.balanceOf(USER_A), 50 ether);
    }
}
