# NewLo Point – Upgradeable ERC‑20 (Foundry)

Production‑ready ERC‑20 token with:

* **Upgradeable** (Transparent Proxy + `ProxyAdmin`)
* **Transfer‑lock** flag (initially disabled)
* **Role‑based control** (`DEFAULT_ADMIN`, `PAUSER`, `MINTER`)
* **Permit (EIP‑2612)**, **Burnable**, **Pausable**

---

## Requirements

| Tool | Version |
|------|---------|
| [Foundry](https://github.com/foundry-rs/foundry) | `>=v0.2.0` |
| Node.js / pnpm (optional for scripts) | – |

```bash
# Ubuntu example
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## Installation

```bash
git clone <repo>
cd newlo-point-foundry

# Install OZ libraries & test utils
forge install openzeppelin/openzeppelin-contracts-upgradeable@v5.0.1              openzeppelin/openzeppelin-contracts@v5.0.1              foundry-rs/forge-std
```

---

## Compile

```bash
forge build
```

---

## Tests

```bash
forge test -vv
```

---

## Deploy

1. Copy **`.env.example` → `.env`** and fill variables.  
2. Run script:

```bash
forge script script/Deploy.s.sol:Deploy \
  --rpc-url $RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast \
  --verify
```

The script emits:

```
Implementation: 0x...
Proxy:          0x...
ProxyAdmin:     0x...
```

---

## Upgrade

```bash
# 1. Deploy new implementation
forge create --rpc-url $RPC_URL --private-key $PRIVATE_KEY src/NewLoPoint.sol:NewLoPoint

# 2. Upgrade via ProxyAdmin
cast send --rpc-url $RPC_URL --from $DEFAULT_ADMIN \
  <ProxyAdmin> "upgrade(address,address)" <Proxy> <NewImpl>
```

---

## CREATE2 Factory

See **`src/NewLoPointFactory.sol`** for deterministic deployments:

```solidity
bytes32 salt = keccak256("2025-06-batch-1");
factory.deployToken(salt, admin, pauser, minter);
```

Address can be pre‑calculated with `predictAddress`.

---

## Security Notes

* **Always** protect `DEFAULT_ADMIN` / `ProxyAdmin` with a multisig + timelock.
* Review & audit before production; this repo is a reference implementation.
