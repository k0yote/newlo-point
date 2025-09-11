#!/bin/bash

# Solidity Compilation Script
# Usage: ./compile.sh [contract_alias]
# Available aliases: token-distribution-v2, newlo-point, multi-token-distribution, nlp-to-eth-exchange, nlp-to-multi-token-exchange, soneium-eth-distribution, nlp-to-multi-token-kaia-exchange, pyth

set -e

# Base solc command parts
OPTIMIZE="--optimize --optimize-runs 200"
EVM_VERSION="--evm-version prague"
OUTPUT_FORMAT="--abi --bin"
BASE_PATH="--base-path ."
OPENZEPPELIN_INCLUDE="--include-path lib/openzeppelin-contracts/contracts @openzeppelin/contracts=lib/openzeppelin-contracts/contracts"
OPENZEPPELIN_UPGRADEABLE_INCLUDE="--include-path lib/openzeppelin-contracts-upgradeable/contracts @openzeppelin/contracts-upgradeable=lib/openzeppelin-contracts-upgradeable/contracts"
CHAINLINK_INCLUDE="--include-path lib/chainlink-evm/contracts/ @chainlink/contracts/=lib/chainlink-evm/contracts/"
OUTPUT_DIR="-o solc-build"

# Function to display usage
usage() {
    echo "Usage: $0 [contract_alias]"
    echo ""
    echo "Available contract aliases:"
    echo "  token-distribution-v2      - TokenDistributionV2"
    echo "  newlo-point               - NewLoPoint"
    echo "  multi-token-distribution  - MultiTokenDistribution"
    echo "  nlp-to-eth-exchange       - NLPToETHExchange"
    echo "  nlp-to-multi-token-exchange - NLPToMultiTokenExchange"
    echo "  soneium-eth-distribution  - SoneiumETHDistribution"
    echo "  nlp-to-multi-token-kaia-exchange - NLPToMultiTokenKaiaExchange"
    echo "  pyth                      - IPyth"
    echo ""
    echo "Examples:"
    echo "  $0 newlo-point"
    echo "  $0 nlp-to-multi-token-exchange"
    exit 1
}

# Clean and create output directory
rm -rf solc-build
mkdir -p solc-build

case "$1" in
    "token-distribution-v2")
        echo "Compiling TokenDistributionV2..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE $OPENZEPPELIN_UPGRADEABLE_INCLUDE src/TokenDistributionV2.sol $OUTPUT_DIR
        ;;
    "newlo-point")
        echo "Compiling NewLoPoint..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE $OPENZEPPELIN_UPGRADEABLE_INCLUDE src/NewLoPoint.sol $OUTPUT_DIR
        ;;
    "multi-token-distribution")
        echo "Compiling MultiTokenDistribution..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE src/MultiTokenDistribution.sol $OUTPUT_DIR
        ;;
    "nlp-to-eth-exchange")
        echo "Compiling NLPToETHExchange..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE $CHAINLINK_INCLUDE src/NLPToETHExchange.sol $OUTPUT_DIR
        ;;
    "nlp-to-multi-token-exchange")
        echo "Compiling NLPToMultiTokenExchange..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE $CHAINLINK_INCLUDE src/NLPToMultiTokenExchange.sol $OUTPUT_DIR
        ;;
    "soneium-eth-distribution")
        echo "Compiling SoneiumETHDistribution..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE src/SoneiumETHDistribution.sol $OUTPUT_DIR
        ;;
    "nlp-to-multi-token-kaia-exchange")
        echo "Compiling NLPToMultiTokenKaiaExchange..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH $OPENZEPPELIN_INCLUDE src/NLPToMultiTokenKaiaExchange.sol $OUTPUT_DIR
        ;;
    "pyth")
        echo "Compiling IPyth..."
        solc $OPTIMIZE $EVM_VERSION $OUTPUT_FORMAT $BASE_PATH src/pyth/IPyth.sol $OUTPUT_DIR
        ;;
    "")
        echo "Error: No contract alias specified."
        echo ""
        usage
        ;;
    *)
        echo "Error: Unknown contract alias '$1'"
        echo ""
        usage
        ;;
esac

echo "Compilation completed successfully!"
echo "Output files are in the solc-build directory."