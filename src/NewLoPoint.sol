// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

import { AccessControlUpgradeable } from
    "@openzeppelin/contracts-upgradeable/access/AccessControlUpgradeable.sol";
import { ERC20Upgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/ERC20Upgradeable.sol";
import { ERC20BurnableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20BurnableUpgradeable.sol";
import { ERC20PausableUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PausableUpgradeable.sol";
import { ERC20PermitUpgradeable } from
    "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/ERC20PermitUpgradeable.sol";
import { Initializable } from "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";

contract NewLoPoint is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    ERC20PausableUpgradeable,
    AccessControlUpgradeable,
    ERC20PermitUpgradeable
{
    /* ───────── Roles ───────── */
    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
    bytes32 public constant WHITELIST_MANAGER_ROLE = keccak256("WHITELIST_MANAGER_ROLE");

    /* ───────── Transfer Control ───────── */
    bool public transfersEnabled;
    bool public whitelistModeEnabled;

    // ホワイトリスト: 転送が制限されていても転送を許可されたアドレス
    mapping(address => bool) public whitelistedAddresses;

    /* ───────── Events ───────── */
    event TransfersEnabledChanged(bool enabled);
    event WhitelistModeChanged(bool enabled);
    event AddressWhitelisted(address indexed account, bool whitelisted);

    /* ───────── Errors ───────── */
    error TransfersDisabled();
    error NotWhitelisted();

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    function initialize(address defaultAdmin, address pauser, address minter) public initializer {
        __ERC20_init("NewLo Point", "NLP");
        __ERC20Burnable_init();
        __ERC20Pausable_init();
        __AccessControl_init();
        __ERC20Permit_init("NewLo Point");

        _grantRole(DEFAULT_ADMIN_ROLE, defaultAdmin);
        _grantRole(PAUSER_ROLE, pauser);
        _grantRole(MINTER_ROLE, minter);
        _grantRole(WHITELIST_MANAGER_ROLE, defaultAdmin);

        transfersEnabled = false;
        whitelistModeEnabled = false;
    }

    /* ───────── Transfer Control Functions ───────── */

    /// @notice 全体の転送を有効/無効化（管理者のみ）
    function setTransfersEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        transfersEnabled = enabled;
        emit TransfersEnabledChanged(enabled);
    }

    /// @notice ホワイトリストモードを有効/無効化（管理者のみ）
    function setWhitelistModeEnabled(bool enabled) external onlyRole(DEFAULT_ADMIN_ROLE) {
        whitelistModeEnabled = enabled;
        emit WhitelistModeChanged(enabled);
    }

    /// @notice アドレスをホワイトリストに追加/削除
    function setWhitelistedAddress(address account, bool whitelisted)
        external
        onlyRole(WHITELIST_MANAGER_ROLE)
    {
        whitelistedAddresses[account] = whitelisted;
        emit AddressWhitelisted(account, whitelisted);
    }

    /// @notice 複数のアドレスを一括でホワイトリストに追加/削除
    function setWhitelistedAddresses(address[] calldata accounts, bool whitelisted)
        external
        onlyRole(WHITELIST_MANAGER_ROLE)
    {
        for (uint i = 0; i < accounts.length; i++) {
            whitelistedAddresses[accounts[i]] = whitelisted;
            emit AddressWhitelisted(accounts[i], whitelisted);
        }
    }

    /* ───────── Public Control ───────── */
    function pause() external onlyRole(PAUSER_ROLE) {
        _pause();
    }

    function unpause() external onlyRole(PAUSER_ROLE) {
        _unpause();
    }

    function mint(address to, uint amount) external onlyRole(MINTER_ROLE) {
        _mint(to, amount);
    }

    /* ───────── Internal Functions ───────── */

    /// @notice 転送が許可されているかチェック
    function _isTransferAllowed(address from, address to) internal view returns (bool) {
        // Mint/Burnは常に許可
        if (from == address(0) || to == address(0)) {
            return true;
        }

        // 全転送が有効化されている場合は許可
        if (transfersEnabled) {
            return true;
        }

        // ホワイトリストモードが有効な場合、送信者または受信者がホワイトリストに含まれていれば許可
        if (whitelistModeEnabled && (whitelistedAddresses[from] || whitelistedAddresses[to])) {
            return true;
        }

        return false;
    }

    /* ───────── Core Hook (v5) ───────── */
    function _update(address from, address to, uint value)
        internal
        override(ERC20Upgradeable, ERC20PausableUpgradeable)
    {
        if (!_isTransferAllowed(from, to)) {
            if (whitelistModeEnabled) {
                revert NotWhitelisted();
            } else {
                revert TransfersDisabled();
            }
        }
        super._update(from, to, value);
    }
}
