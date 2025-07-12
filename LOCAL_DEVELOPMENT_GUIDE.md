# NewLo Point Contract ローカル開発ガイド

このガイドでは、ローカルAnvil環境でのNewLo Pointスマートコントラクトのデプロイと管理方法について説明します。

## 📋 前提条件

以下のツールがインストールされている必要があります：

- **Foundry** (forge, anvil, cast): https://getfoundry.sh/
- **Node.js** (jq, curl用): https://nodejs.org/
- **Make** (Makefileサポート用)
- **bc** (数値計算用)

```bash
# Foundryインストール
curl -L https://foundry.paradigm.xyz | bash
foundryup

# jqインストール (macOS)
brew install jq

# bcインストール (macOS)
brew install bc
```

## 🚀 クイックスタート

### 1. 環境セットアップ

```bash
# プロジェクトディレクトリに移動
cd newlo-point-contract

# 環境設定情報(それぞれの環境に合わせてください)
cp .env.sample .env

# スクリプトに実行権限を付与
chmod +x scripts/local-dev.sh

# Anvilを起動
./scripts/local-dev.sh start
```

### 2. コントラクトのデプロイ

```bash
# 全コントラクトをデプロイ
./scripts/local-dev.sh deploy
```

### 3. 環境変数の設定

デプロイ完了後、出力されたコントラクトアドレスを環境変数に設定します：

```bash
# 例（実際のアドレスに置き換えてください）
export NLP_TOKEN=0x5FbDB2315678afecb367f032d93F642f64180aa3
export TOKEN_DIST_V2=0xe7f1725E7734CE288F8367e1Bb143E90bb3F0512
export MULTI_TOKEN_DIST=0x9fE46736679d2D9a65F0992F2272dE9f3c7fa6e0
```

### 4. 基本的な操作

```bash
# コントラクト情報を確認
./scripts/local-dev.sh contract-info

# 残高を確認
./scripts/local-dev.sh check-balance 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266

# トークンをミント
./scripts/local-dev.sh mint-tokens 0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266 1000
```

## 🔧 使用方法

### Shell Script (`./scripts/local-dev.sh`)

#### Anvil管理
```bash
./scripts/local-dev.sh start           # Anvil開始
./scripts/local-dev.sh stop            # Anvil停止
./scripts/local-dev.sh status          # Anvil状態確認
```

#### デプロイメント
```bash
./scripts/local-dev.sh deploy          # 全コントラクトデプロイ
./scripts/local-dev.sh deploy-dry-run  # デプロイのシミュレーション
```

#### コントラクト操作
```bash
./scripts/local-dev.sh grant-minter-role <address>  # MINTER_ROLE付与
./scripts/local-dev.sh mint-tokens <address> <amount>  # トークンミント
./scripts/local-dev.sh add-to-whitelist <address>  # whitelist追加
```

#### 情報確認
```bash
./scripts/local-dev.sh check-balance <address>     # 残高確認
./scripts/local-dev.sh check-whitelist <address>   # whitelist状態確認
./scripts/local-dev.sh contract-info               # コントラクト情報表示
./scripts/local-dev.sh accounts                    # アカウント情報表示
```

### Makefile

```bash
# ヘルプを表示
make help

# 環境セットアップ（Anvil起動 + デプロイ）
make setup

# 個別コマンド
make anvil-start                # Anvil起動
make deploy                     # デプロイ
make anvil-stop                 # Anvil停止

# コントラクト操作（環境変数が必要）
make grant-minter-role ADDRESS=0x...
make mint-tokens ADDRESS=0x... AMOUNT=1000
make add-to-whitelist ADDRESS=0x...
make check-balance ADDRESS=0x...
```

## 🏗️ デプロイされるコントラクト

### 1. NewLoPointFactory
- **役割**: NewLoPointトークンのファクトリーコントラクト
- **CREATE2**: 決定的なアドレス生成
- **含まれるもの**: Implementation, ProxyAdmin, Factory

### 2. NewLoPoint
- **役割**: メインのERC20トークン
- **機能**: Transfer制御、Whitelist、Role管理
- **初期設定**:
  - Transfers: 有効
  - Whitelist Mode: 有効
  - Distribution契約をwhitelistに追加

### 3. TokenDistributionV2
- **役割**: 効率的なトークン配布（transfer-based）
- **機能**: バッチ配布、Role管理
- **初期残高**: 10,000 NLP

### 4. MultiTokenDistribution
- **役割**: 複数トークンの配布管理
- **機能**: ERC20トークン配布、統計管理
- **初期残高**: 10,000 NLP

## 👥 デフォルトアカウント（Anvil）

| 役割 | アドレス | 秘密鍵 |
|------|----------|---------|
| Deployer | `0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266` | `0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80` |
| Admin | `0x70997970C51812dc3A010C7d01b50e0d17dc79C8` | `0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d` |
| Pauser | `0x3C44CdDdB6a900fa2b585dd299e03d12FA4293BC` | `0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a` |
| Minter | `0x90F79bf6EB2c4f870365E785982E1f101E93b906` | `0x7c852118294e51e653712a81e05800f419141751be58f605c371e15141b007a6` |

## 🔑 主要なロール

### NewLoPoint
- **DEFAULT_ADMIN_ROLE**: `0x0000000000000000000000000000000000000000000000000000000000000000`
- **MINTER_ROLE**: `0x9f2df0fed2c77648de5860a4cc508cd0818c85b8b8a1ab4ceeef8d981c8956a6`
- **PAUSER_ROLE**: `0x65d7a28e3265b37a6474929f336521b332c1681b933f6cb9f3376673440d862a`
- **WHITELIST_MANAGER_ROLE**: `0x...`

### TokenDistributionV2
- **DEFAULT_ADMIN_ROLE**: 全体管理
- **DISTRIBUTOR_ROLE**: 配布実行
- **DEPOSIT_MANAGER_ROLE**: 資金管理
- **PAUSER_ROLE**: 緊急停止

## 🛠️ 便利なcastコマンド

### 残高確認
```bash
cast call $NLP_TOKEN "balanceOf(address)" <ADDRESS> --rpc-url http://localhost:8545
```

### ロール確認
```bash
cast call $NLP_TOKEN "hasRole(bytes32,address)" $MINTER_ROLE <ADDRESS> --rpc-url http://localhost:8545
```

### トークンミント
```bash
cast send $NLP_TOKEN "mint(address,uint256)" <ADDRESS> "1000000000000000000000" --private-key $ADMIN_KEY --rpc-url http://localhost:8545
```

### Whitelist追加
```bash
cast send $NLP_TOKEN "setWhitelistedAddress(address,bool)" <ADDRESS> true --private-key $ADMIN_KEY --rpc-url http://localhost:8545
```

## 📊 テストシナリオ

### 基本的なフロー
1. Anvilを起動
2. 全コントラクトをデプロイ
3. 設定を確認
4. トークンの配布をテスト
5. 権限管理をテスト

### ユースケーステスト

#### 1. 一般ユーザーへのトークン配布
```bash
# ユーザーアドレス（Account[4]）
USER_ADDR="0x15d34AAf54267DB7D7c367839AAf71A00a2C6A65"

# トークンをミント
./scripts/local-dev.sh mint-tokens $USER_ADDR 100

# 残高確認
./scripts/local-dev.sh check-balance $USER_ADDR
```

#### 2. 制限付きトークン配布
```bash
# Transfer無効化
cast send $NLP_TOKEN "setTransfersEnabled(bool)" false --private-key $ADMIN_KEY --rpc-url http://localhost:8545

# Whitelist追加
./scripts/local-dev.sh add-to-whitelist $USER_ADDR

# 配布テスト（Distribution契約経由）
cast send $TOKEN_DIST_V2 "distributeBatch(address[],uint256[])" "[$USER_ADDR]" "[100000000000000000000]" --private-key $ADMIN_KEY --rpc-url http://localhost:8545
```

#### 3. 権限管理テスト
```bash
# 新しいアドレスにMINTER_ROLEを付与
NEW_MINTER="0x8ba1f109551bD432803012645Hac136c1ce_Example"
./scripts/local-dev.sh grant-minter-role $NEW_MINTER

# 権限確認
make check-role ADDRESS=$NEW_MINTER ROLE=MINTER_ROLE
```

## 🐛 トラブルシューティング

### よくある問題

#### 1. Anvilが起動しない
```bash
# プロセス確認
ps aux | grep anvil

# ポート確認
lsof -i :8545

# 強制停止
pkill -f anvil
```

#### 2. デプロイに失敗する
```bash
# Anvilの状態確認
./scripts/local-dev.sh status

# ログ確認
tail -f anvil.log

# 再デプロイ
./scripts/local-dev.sh stop
./scripts/local-dev.sh start
./scripts/local-dev.sh deploy
```

#### 3. 環境変数が設定されていない
```bash
# 現在の環境変数を確認
echo $NLP_TOKEN
echo $TOKEN_DIST_V2
echo $MULTI_TOKEN_DIST

# 環境変数の例を表示
make env-example
```

### ログとデバッグ

```bash
# Anvilログを確認
tail -f anvil.log

# 詳細なデプロイログ
./scripts/local-dev.sh deploy-dry-run

# Forge テスト
make test-verbose
```

## 📚 参考資料

- [Foundry Book](https://book.getfoundry.sh/)
- [Anvil Documentation](https://book.getfoundry.sh/anvil/)
- [OpenZeppelin Contracts](https://docs.openzeppelin.com/contracts/)
- [NewLo Point Documentation](./docs/)

## 🚨 注意事項

- **本番環境では絶対に使用しないでください**: これらのキーと設定はローカル開発専用です
- **セキュリティ**: 実際の資金を扱う場合は、適切なキー管理を行ってください
- **ガス制限**: Anvilのガス制限は本番環境と異なる場合があります
- **状態管理**: Anvilを再起動すると全ての状態がリセットされます

---

**Happy Coding! 🎉**

このガイドでローカル開発環境でのNewLo Pointスマートコントラクトの開発・テストが効率的に行えるようになります。