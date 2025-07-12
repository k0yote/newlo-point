#!/bin/bash

# NewLo Point Contract Local Development Script
# このスクリプトはローカルAnvilでのスマートコントラクトデプロイと管理を簡素化します

set -e

# ==================== CONFIGURATION ====================
ANVIL_PORT=8545
ANVIL_HOST=localhost
ANVIL_URL="http://${ANVIL_HOST}:${ANVIL_PORT}"
DEPLOYER_KEY="0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80"
ADMIN_KEY="0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d"
PAUSER_KEY="0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a"
MINTER_KEY="0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6"

# Default addresses (Anvil accounts)
DEPLOYER_ADDR="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
ADMIN_ADDR="0x70997970C51812dc3A010C7d01b50e0d17dc79C8"
PAUSER_ADDR="0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC"
MINTER_ADDR="0x90F79bf6EB2c4f870365E785982E1f101E93b906"

# Role hashes
MINTER_ROLE="0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6"
PAUSER_ROLE="0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a"
DEFAULT_ADMIN_ROLE="0x0000000000000000000000000000000000000000000000000000000000000000"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ==================== HELPER FUNCTIONS ====================
print_header() {
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_info() {
    echo -e "${BLUE}ℹ $1${NC}"
}

check_anvil_running() {
    if ! curl -s "$ANVIL_URL" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
        print_error "Anvil is not running on $ANVIL_URL"
        print_info "Please run: ./scripts/local-dev.sh start"
        exit 1
    fi
}

check_requirements() {
    local missing_tools=()

    if ! command -v anvil &> /dev/null; then
        missing_tools+=("anvil")
    fi

    if ! command -v forge &> /dev/null; then
        missing_tools+=("forge")
    fi

    if ! command -v cast &> /dev/null; then
        missing_tools+=("cast")
    fi

    if [ ${#missing_tools[@]} -ne 0 ]; then
        print_error "Missing required tools: ${missing_tools[*]}"
        print_info "Please install Foundry: https://getfoundry.sh/"
        exit 1
    fi
}

# ==================== ANVIL MANAGEMENT ====================
start_anvil() {
    print_header "Starting Anvil Local Network"

    if pgrep -f "anvil" > /dev/null; then
        print_warning "Anvil is already running"
        return
    fi

    print_info "Starting Anvil on $ANVIL_HOST:$ANVIL_PORT"
    nohup anvil --host "$ANVIL_HOST" --port "$ANVIL_PORT" --accounts 10 --balance 1000 --gas-limit 30000000 --gas-price 1000000000 > anvil.log 2>&1 &

    # Wait for Anvil to start
    sleep 3

    if check_anvil_running; then
        print_success "Anvil started successfully"
        print_info "Logs are available in anvil.log"
    else
        print_error "Failed to start Anvil"
        exit 1
    fi
}

stop_anvil() {
    print_header "Stopping Anvil"

    if pgrep -f "anvil" > /dev/null; then
        pkill -f "anvil"
        print_success "Anvil stopped"
    else
        print_warning "Anvil is not running"
    fi
}

status_anvil() {
    print_header "Anvil Status"

    if pgrep -f "anvil" > /dev/null; then
        print_success "Anvil is running"
        if curl -s "$ANVIL_URL" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' > /dev/null 2>&1; then
            local block_number=$(curl -s "$ANVIL_URL" -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result')
            print_info "Current block number: $block_number"
        fi
    else
        print_error "Anvil is not running"
    fi
}

# ==================== DEPLOYMENT ====================
deploy_contracts() {
    print_header "Deploying Contracts"

    check_anvil_running

    print_info "Deploying all contracts to local Anvil..."
    forge script script/DeployLocalScenario.s.sol:DeployLocalScenario --fork-url "$ANVIL_URL" --broadcast --private-key "$DEPLOYER_KEY" -vvv

    print_success "Deployment completed!"
    print_info "Check the output above for contract addresses"
}

deploy_dry_run() {
    print_header "Deployment Dry Run"

    check_anvil_running

    print_info "Running deployment dry run..."
    forge script script/DeployLocalScenario.s.sol:DeployLocalScenario --fork-url "$ANVIL_URL" --private-key "$DEPLOYER_KEY" -vvv

    print_success "Dry run completed!"
}

# ==================== CONTRACT INTERACTIONS ====================
grant_minter_role() {
    local address="$1"
    if [ -z "$address" ]; then
        print_error "Address is required"
        print_info "Usage: $0 grant-minter-role <address>"
        exit 1
    fi

    if [ -z "$NLP_TOKEN" ]; then
        print_error "NLP_TOKEN environment variable is not set"
        print_info "Please set it after deployment or check the deployment output"
        exit 1
    fi

    print_header "Granting MINTER_ROLE"

    check_anvil_running

    print_info "Granting MINTER_ROLE to $address..."
    cast send "$NLP_TOKEN" "grantRole(bytes32,address)" "$MINTER_ROLE" "$address" --private-key "$ADMIN_KEY" --rpc-url "$ANVIL_URL"

    print_success "MINTER_ROLE granted to $address"
}

mint_tokens() {
    local address="$1"
    local amount="$2"

    if [ -z "$address" ] || [ -z "$amount" ]; then
        print_error "Address and amount are required"
        print_info "Usage: $0 mint-tokens <address> <amount>"
        exit 1
    fi

    if [ -z "$NLP_TOKEN" ]; then
        print_error "NLP_TOKEN environment variable is not set"
        print_info "Please set it after deployment or check the deployment output"
        exit 1
    fi

    print_header "Minting Tokens"

    check_anvil_running

    local amount_wei="${amount}000000000000000000"  # Convert to wei
    print_info "Minting $amount tokens to $address..."
    cast send "$NLP_TOKEN" "mint(address,uint256)" "$address" "$amount_wei" --private-key "$ADMIN_KEY" --rpc-url "$ANVIL_URL"

    print_success "$amount tokens minted to $address"
}

add_to_whitelist() {
    local address="$1"

    if [ -z "$address" ]; then
        print_error "Address is required"
        print_info "Usage: $0 add-to-whitelist <address>"
        exit 1
    fi

    if [ -z "$NLP_TOKEN" ]; then
        print_error "NLP_TOKEN environment variable is not set"
        print_info "Please set it after deployment or check the deployment output"
        exit 1
    fi

    print_header "Adding to Whitelist"

    check_anvil_running

    print_info "Adding $address to whitelist..."
    cast send "$NLP_TOKEN" "setWhitelistedAddress(address,bool)" "$address" true --private-key "$ADMIN_KEY" --rpc-url "$ANVIL_URL"

    print_success "$address added to whitelist"
}

# ==================== QUERY FUNCTIONS ====================
check_balance() {
    local address="$1"

    if [ -z "$address" ]; then
        print_error "Address is required"
        print_info "Usage: $0 check-balance <address>"
        exit 1
    fi

    if [ -z "$NLP_TOKEN" ]; then
        print_error "NLP_TOKEN environment variable is not set"
        print_info "Please set it after deployment or check the deployment output"
        exit 1
    fi

    print_header "Checking Balance"

    check_anvil_running

    local balance=$(cast call "$NLP_TOKEN" "balanceOf(address)" "$address" --rpc-url "$ANVIL_URL" | cast to-dec)
    local balance_formatted=$(echo "scale=18; $balance / 1000000000000000000" | bc -l)

    print_info "Balance for $address: $balance_formatted NLP"
}

check_whitelist_status() {
    local address="$1"

    if [ -z "$address" ]; then
        print_error "Address is required"
        print_info "Usage: $0 check-whitelist-status <address>"
        exit 1
    fi

    if [ -z "$NLP_TOKEN" ]; then
        print_error "NLP_TOKEN environment variable is not set"
        print_info "Please set it after deployment or check the deployment output"
        exit 1
    fi

    print_header "Checking Whitelist Status"

    check_anvil_running

    local status=$(cast call "$NLP_TOKEN" "whitelistedAddresses(address)" "$address" --rpc-url "$ANVIL_URL")

    if [ "$status" = "true" ]; then
        print_success "$address is whitelisted"
    else
        print_info "$address is not whitelisted"
    fi
}

contract_info() {
    print_header "Contract Information"

    if [ -z "$NLP_TOKEN" ]; then
        print_error "NLP_TOKEN environment variable is not set"
        print_info "Please set it after deployment or check the deployment output"
        return
    fi

    check_anvil_running

    local name=$(cast call "$NLP_TOKEN" "name()" --rpc-url "$ANVIL_URL" | cast to-ascii)
    local symbol=$(cast call "$NLP_TOKEN" "symbol()" --rpc-url "$ANVIL_URL" | cast to-ascii)
    local transfers_enabled=$(cast call "$NLP_TOKEN" "transfersEnabled()" --rpc-url "$ANVIL_URL")
    local whitelist_mode=$(cast call "$NLP_TOKEN" "whitelistModeEnabled()" --rpc-url "$ANVIL_URL")

    print_info "Token Name: $name"
    print_info "Token Symbol: $symbol"
    print_info "Transfers Enabled: $transfers_enabled"
    print_info "Whitelist Mode: $whitelist_mode"
    print_info "Contract Address: $NLP_TOKEN"
}

# ==================== UTILITY FUNCTIONS ====================
show_accounts() {
    print_header "Anvil Default Accounts"

    echo "Account[0] (Deployer): $DEPLOYER_ADDR"
    echo "Account[1] (Admin):    $ADMIN_ADDR"
    echo "Account[2] (Pauser):   $PAUSER_ADDR"
    echo "Account[3] (Minter):   $MINTER_ADDR"
    echo ""
    echo "Private Keys:"
    echo "============="
    echo "Deployer: $DEPLOYER_KEY"
    echo "Admin:    $ADMIN_KEY"
    echo "Pauser:   $PAUSER_KEY"
    echo "Minter:   $MINTER_KEY"
}

show_help() {
    print_header "NewLo Point Contract Local Development"

    echo "Usage: $0 <command> [arguments]"
    echo ""
    echo "Anvil Management:"
    echo "  start                    - Start Anvil local network"
    echo "  stop                     - Stop Anvil local network"
    echo "  status                   - Check Anvil status"
    echo ""
    echo "Deployment:"
    echo "  deploy                   - Deploy all contracts"
    echo "  deploy-dry-run           - Run deployment simulation"
    echo ""
    echo "Contract Interactions:"
    echo "  grant-minter-role <addr> - Grant MINTER_ROLE to address"
    echo "  mint-tokens <addr> <amt> - Mint tokens to address"
    echo "  add-to-whitelist <addr>  - Add address to whitelist"
    echo ""
    echo "Query Functions:"
    echo "  check-balance <addr>     - Check token balance"
    echo "  check-whitelist <addr>   - Check whitelist status"
    echo "  contract-info            - Show contract information"
    echo ""
    echo "Utility:"
    echo "  accounts                 - Show Anvil accounts"
    echo "  help                     - Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  NLP_TOKEN               - NewLoPoint token address"
    echo "  TOKEN_DIST_V2           - TokenDistributionV2 address"
    echo "  MULTI_TOKEN_DIST        - MultiTokenDistribution address"
    echo ""
    echo "Quick Start:"
    echo "  $0 start"
    echo "  $0 deploy"
    echo "  export NLP_TOKEN=<address_from_deployment>"
    echo "  $0 contract-info"
}

# ==================== MAIN SCRIPT ====================
main() {
    check_requirements

    case "${1:-help}" in
        start)
            start_anvil
            ;;
        stop)
            stop_anvil
            ;;
        status)
            status_anvil
            ;;
        deploy)
            deploy_contracts
            ;;
        deploy-dry-run)
            deploy_dry_run
            ;;
        grant-minter-role)
            grant_minter_role "$2"
            ;;
        mint-tokens)
            mint_tokens "$2" "$3"
            ;;
        add-to-whitelist)
            add_to_whitelist "$2"
            ;;
        check-balance)
            check_balance "$2"
            ;;
        check-whitelist)
            check_whitelist_status "$2"
            ;;
        contract-info)
            contract_info
            ;;
        accounts)
            show_accounts
            ;;
        help|*)
            show_help
            ;;
    esac
}

# Run main function with all arguments
main "$@"