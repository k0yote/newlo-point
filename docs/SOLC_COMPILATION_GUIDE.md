# Solidity Compilation Guide

## Direct solc Compilation with Cancun EVM Version

This guide documents the successful compilation command for Solidity contracts using the `solc` compiler directly with the Cancun EVM version.

## Prerequisites

- solc version 0.8.27 or higher (required for Cancun EVM support)
- OpenZeppelin contracts libraries installed in the `lib/` directory

## Compilation Command

```bash
### TokenDistributionV2
solc --optimize-runs 200 --evm-version cancun --abi --bin --base-path . --include-path lib/openzeppelin-contracts/contracts @openzeppelin/contracts=lib/openzeppelin-contracts/contracts --include-path lib/openzeppelin-contracts-upgradeable/contracts @openzeppelin/contracts-upgradeable=lib/openzeppelin-contracts-upgradeable/contracts src/TokenDistributionV2.sol -o solc-build
```

```bash
### NewLoPoint
solc --optimize-runs 200 --evm-version cancun --abi --bin --base-path . --include-path lib/openzeppelin-contracts/contracts @openzeppelin/contracts=lib/openzeppelin-contracts/contracts --include-path lib/openzeppelin-contracts-upgradeable/contracts @openzeppelin/contracts-upgradeable=lib/openzeppelin-contracts-upgradeable/contracts src/NewLoPoint.sol -o solc-build
```

```bash
### MultiTokenDistribution
solc --optimize --optimize-runs 200 --evm-version cancun --abi --bin --base-path . --include-path lib/openzeppelin-contracts/contracts @openzeppelin/contracts=lib/openzeppelin-contracts/contracts src/MultiTokenDistribution.sol -o solc-build
```

```bash
### NLPToETHExchange
solc --optimize --optimize-runs 200 --evm-version cancun --abi --bin --base-path . --include-path lib/openzeppelin-contracts/contracts @openzeppelin/contracts=lib/openzeppelin-contracts/contracts --include-path lib/chainlink-evm/contracts/ @chainlink/contracts/=lib/chainlink-evm/contracts/ src/NLPToETHExchange.sol -o solc-build
```

```bash
### NLPToMultiTokenExchange
solc --optimize --optimize-runs 200 --evm-version cancun --abi --bin --base-path . --include-path lib/openzeppelin-contracts/contracts @openzeppelin/contracts=lib/openzeppelin-contracts/contracts --include-path lib/chainlink-evm/contracts/ @chainlink/contracts/=lib/chainlink-evm/contracts/ src/NLPToMultiTokenExchange.sol -o solc-build
```

## Command Parameters Breakdown

### Optimization Settings
- `--optimize-runs 200`: Enables optimization with 200 runs, balancing deployment cost and execution cost
- `--evm-version cancun`: Targets the Cancun EVM version (latest as of solc 0.8.27)

### Output Options
- `--abi`: Generates ABI (Application Binary Interface) files
- `--bin`: Generates binary bytecode files
- `-o build`: Specifies output directory as `build/`

### Path Configuration
- `--base-path .`: Sets the base path to current directory
- `--include-path lib/openzeppelin-contracts/contracts`: Includes OpenZeppelin contracts library
- `--include-path lib/openzeppelin-contracts-upgradeable/contracts`: Includes OpenZeppelin upgradeable contracts library

### Library Remappings
- `@openzeppelin/contracts=lib/openzeppelin-contracts/contracts`: Maps OpenZeppelin imports to local library path
- `@openzeppelin/contracts-upgradeable=lib/openzeppelin-contracts-upgradeable/contracts`: Maps OpenZeppelin upgradeable imports to local library path

### Source File
- `src/TokenDistributionV2.sol`: The main contract file to compile

## EVM Version Support

The Cancun EVM version includes the following features:
- EIP-4844 (Proto-Danksharding)
- EIP-1153 (Transient storage opcodes)
- EIP-5656 (MCOPY opcode)
- EIP-6780 (SELFDESTRUCT changes)

## Alternative: Using Foundry

For projects using Foundry, the equivalent compilation can be achieved with:

```bash
forge build
```

The `foundry.toml` configuration file automatically handles all the path mappings and optimization settings.

## Troubleshooting

### Common Issues
1. **"Invalid option for --evm-version: cancun"**: Upgrade solc to version 0.8.27 or higher
2. **"Source not found" errors**: Ensure all `--include-path` and remapping parameters are correctly specified
3. **Library dependency issues**: Verify that OpenZeppelin libraries are properly installed in the `lib/` directory

### Version Check
```bash
solc --version
```

### Available EVM Versions
```bash
solc --help | grep -A 10 "evm-version"
```

## Notes

- This command compiles all dependencies recursively
- Generated files will be placed in the `build/` directory
- Both ABI and bytecode files are generated for deployment and interaction purposes
- The optimization settings match the Foundry configuration for consistency 