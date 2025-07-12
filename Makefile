# Makefile for NewLo Point Contract Local Development

# ==================== VARIABLES ====================
ANVIL_PORT = 8545
ANVIL_HOST = localhost
ANVIL_URL = http://$(ANVIL_HOST):$(ANVIL_PORT)
DEPLOYER_KEY = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80
ADMIN_KEY = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d
PAUSER_KEY = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a
MINTER_KEY = 0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6

# デフォルトアドレス
DEPLOYER_ADDR = 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266
ADMIN_ADDR = 0x70997970C51812dc3A010C7d01b50e0d17dc79C8
PAUSER_ADDR = 0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC
MINTER_ADDR = 0x90F79bf6EB2c4f870365E785982E1f101E93b906

# コントラクトファイル
DEPLOY_SCRIPT = script/DeployLocalScenario.s.sol:DeployLocalScenario

# ==================== HELP ====================
.PHONY: help
help: ## 使用可能なコマンドを表示
	@echo "NewLo Point Contract Local Development"
	@echo "======================================"
	@echo ""
	@echo "Available commands:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2}'

# ==================== ANVIL MANAGEMENT ====================
.PHONY: anvil-start
anvil-start: ## Anvilローカルネットワークを起動
	@echo "Starting Anvil local network..."
	@anvil --host $(ANVIL_HOST) --port $(ANVIL_PORT) --accounts 10 --balance 1000 --gas-limit 30000000 --gas-price 1000000000

.PHONY: anvil-stop
anvil-stop: ## Anvilプロセスを停止
	@echo "Stopping Anvil..."
	@pkill -f "anvil" || echo "Anvil process not found"

.PHONY: anvil-status
anvil-status: ## Anvilの状態を確認
	@echo "Checking Anvil status..."
	@curl -s $(ANVIL_URL) -X POST -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq . || echo "Anvil is not running"

# ==================== DEPLOYMENT ====================
.PHONY: deploy
deploy: ## ローカルAnvilにスマートコントラクトをデプロイ
	@echo "Deploying contracts to local Anvil..."
	@forge script $(DEPLOY_SCRIPT) --fork-url $(ANVIL_URL) --broadcast --private-key $(DEPLOYER_KEY) -vvv

.PHONY: deploy-dry-run
deploy-dry-run: ## デプロイのドライラン（実際にはデプロイしない）
	@echo "Dry run deployment..."
	@forge script $(DEPLOY_SCRIPT) --fork-url $(ANVIL_URL) --private-key $(DEPLOYER_KEY) -vvv

# ==================== CONTRACT INTERACTIONS ====================
.PHONY: grant-minter-role
grant-minter-role: ## 指定されたアドレスにMINTER_ROLEを付与 (usage: make grant-minter-role ADDRESS=0x...)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make grant-minter-role ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "Granting MINTER_ROLE to $(ADDRESS)..."
	@cast send $(NLP_TOKEN) "grantRole(bytes32,address)" 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6 $(ADDRESS) --private-key $(ADMIN_KEY) --rpc-url $(ANVIL_URL)

.PHONY: mint-tokens
mint-tokens: ## 指定されたアドレスにトークンをミント (usage: make mint-tokens ADDRESS=0x... AMOUNT=1000)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make mint-tokens ADDRESS=0x... AMOUNT=1000"; \
		exit 1; \
	fi
	@if [ -z "$(AMOUNT)" ]; then \
		echo "Error: AMOUNT is required. Usage: make mint-tokens ADDRESS=0x... AMOUNT=1000"; \
		exit 1; \
	fi
	@echo "Minting $(AMOUNT) tokens to $(ADDRESS)..."
	@cast send $(NLP_TOKEN) "mint(address,uint256)" $(ADDRESS) "$$(echo "scale=0; $(AMOUNT) * 1000000000000000000" | bc -l)" --private-key $(ADMIN_KEY) --rpc-url $(ANVIL_URL)

.PHONY: add-to-whitelist
add-to-whitelist: ## 指定されたアドレスをwhitelistに追加 (usage: make add-to-whitelist ADDRESS=0x...)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make add-to-whitelist ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "Adding $(ADDRESS) to whitelist..."
	@cast send $(NLP_TOKEN) "setWhitelistedAddress(address,bool)" $(ADDRESS) true --private-key $(ADMIN_KEY) --rpc-url $(ANVIL_URL)

.PHONY: remove-from-whitelist
remove-from-whitelist: ## 指定されたアドレスをwhitelistから削除 (usage: make remove-from-whitelist ADDRESS=0x...)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make remove-from-whitelist ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "Removing $(ADDRESS) from whitelist..."
	@cast send $(NLP_TOKEN) "setWhitelistedAddress(address,bool)" $(ADDRESS) false --private-key $(ADMIN_KEY) --rpc-url $(ANVIL_URL)

# ==================== QUERY FUNCTIONS ====================
.PHONY: check-balance
check-balance: ## 指定されたアドレスの残高を確認 (usage: make check-balance ADDRESS=0x...)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make check-balance ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "Checking balance for $(ADDRESS)..."
	@cast call $(NLP_TOKEN) "balanceOf(address)" $(ADDRESS) --rpc-url $(ANVIL_URL) | cast to-dec

.PHONY: check-whitelist-status
check-whitelist-status: ## 指定されたアドレスのwhitelist状態を確認 (usage: make check-whitelist-status ADDRESS=0x...)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make check-whitelist-status ADDRESS=0x..."; \
		exit 1; \
	fi
	@echo "Checking whitelist status for $(ADDRESS)..."
	@cast call $(NLP_TOKEN) "whitelistedAddresses(address)" $(ADDRESS) --rpc-url $(ANVIL_URL)

.PHONY: check-role
check-role: ## 指定されたアドレスのロールを確認 (usage: make check-role ADDRESS=0x... ROLE=MINTER_ROLE)
	@if [ -z "$(ADDRESS)" ]; then \
		echo "Error: ADDRESS is required. Usage: make check-role ADDRESS=0x... ROLE=MINTER_ROLE"; \
		exit 1; \
	fi
	@if [ -z "$(ROLE)" ]; then \
		echo "Error: ROLE is required. Usage: make check-role ADDRESS=0x... ROLE=MINTER_ROLE"; \
		exit 1; \
	fi
	@echo "Checking $(ROLE) for $(ADDRESS)..."
	@if [ "$(ROLE)" = "MINTER_ROLE" ]; then \
		cast call $(NLP_TOKEN) "hasRole(bytes32,address)" 0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6 $(ADDRESS) --rpc-url $(ANVIL_URL); \
	elif [ "$(ROLE)" = "PAUSER_ROLE" ]; then \
		cast call $(NLP_TOKEN) "hasRole(bytes32,address)" 0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a $(ADDRESS) --rpc-url $(ANVIL_URL); \
	elif [ "$(ROLE)" = "DEFAULT_ADMIN_ROLE" ]; then \
		cast call $(NLP_TOKEN) "hasRole(bytes32,address)" 0x0000000000000000000000000000000000000000000000000000000000000000 $(ADDRESS) --rpc-url $(ANVIL_URL); \
	else \
		echo "Unknown role: $(ROLE)"; \
		exit 1; \
	fi

.PHONY: contract-info
contract-info: ## デプロイされたコントラクトの情報を表示
	@echo "Contract Information:"
	@echo "====================="
	@if [ -n "$(NLP_TOKEN)" ]; then \
		echo "NewLoPoint Token: $(NLP_TOKEN)"; \
		echo "Token Name: $$(cast call $(NLP_TOKEN) 'name()' --rpc-url $(ANVIL_URL) | cast to-ascii)"; \
		echo "Token Symbol: $$(cast call $(NLP_TOKEN) 'symbol()' --rpc-url $(ANVIL_URL) | cast to-ascii)"; \
		echo "Transfers Enabled: $$(cast call $(NLP_TOKEN) 'transfersEnabled()' --rpc-url $(ANVIL_URL))"; \
		echo "Whitelist Mode: $$(cast call $(NLP_TOKEN) 'whitelistModeEnabled()' --rpc-url $(ANVIL_URL))"; \
	else \
		echo "NLP_TOKEN not set. Please run 'make deploy' first or set NLP_TOKEN environment variable."; \
	fi

# ==================== TESTING ====================
.PHONY: test
test: ## Forgeテストを実行
	@echo "Running Forge tests..."
	@forge test

.PHONY: test-verbose
test-verbose: ## 詳細なForgeテストを実行
	@echo "Running Forge tests with verbose output..."
	@forge test -vvv

.PHONY: test-fork
test-fork: ## フォークテストを実行
	@echo "Running fork tests..."
	@forge test --fork-url $(ANVIL_URL) -vvv

# ==================== UTILITY COMMANDS ====================
.PHONY: accounts
accounts: ## Anvilアカウントリストを表示
	@echo "Anvil Default Accounts:"
	@echo "======================="
	@echo "Account[0] (Deployer): $(DEPLOYER_ADDR)"
	@echo "Account[1] (Admin):    $(ADMIN_ADDR)"
	@echo "Account[2] (Pauser):   $(PAUSER_ADDR)"
	@echo "Account[3] (Minter):   $(MINTER_ADDR)"
	@echo ""
	@echo "Private Keys:"
	@echo "============="
	@echo "Deployer: $(DEPLOYER_KEY)"
	@echo "Admin:    $(ADMIN_KEY)"
	@echo "Pauser:   $(PAUSER_KEY)"
	@echo "Minter:   $(MINTER_KEY)"

.PHONY: clean
clean: ## ビルドアーティファクトをクリーンアップ
	@echo "Cleaning build artifacts..."
	@forge clean

.PHONY: build
build: ## コントラクトをビルド
	@echo "Building contracts..."
	@forge build

.PHONY: format
format: ## コードをフォーマット
	@echo "Formatting code..."
	@forge fmt

# ==================== FULL WORKFLOW ====================
.PHONY: setup
setup: anvil-start deploy ## Anvilを起動してコントラクトをデプロイ
	@echo "Setup complete!"
	@echo "Run 'make contract-info' to see deployed contract information."

.PHONY: teardown
teardown: anvil-stop ## Anvilを停止
	@echo "Teardown complete!"

# ==================== ENVIRONMENT VARIABLES ====================
# 実際のコントラクトアドレスを設定（deploy後に手動で設定）
# 例: export NLP_TOKEN=0x...
# 例: export TOKEN_DIST_V2=0x...
# 例: export MULTI_TOKEN_DIST=0x...

.PHONY: env-example
env-example: ## 環境変数の例を表示
	@echo "Environment Variables Example:"
	@echo "=============================="
	@echo "export NLP_TOKEN=0x5FbDB2315678afecb367f032d93F642f64180aa3"
	@echo "export TOKEN_DIST_V2=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512"
	@echo "export MULTI_TOKEN_DIST=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0"
	@echo ""
	@echo "These addresses will be displayed after running 'make deploy'"

# Default target
.DEFAULT_GOAL := help