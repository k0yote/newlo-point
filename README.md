# 🏦 NewLo Point (NLP) Contract System

**⚠️ Disclaimer**: This smart contract is experimental software. Please conduct thorough testing and auditing before using in production environments.

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Solidity](https://img.shields.io/badge/Solidity-^0.8.27-blue.svg)](https://soliditylang.org/)


## 🔍 概要 (Overview)

NewLo Point is an ERC20 point token with gradual transfer control functionality. During the initial service phase, user-to-user transfers are restricted, allowing only minting from the service operator. As the service evolves and exchanges are prepared, transfers can be gradually enabled.

NewLo Point (NLP) Contract System は、包括的なDeFiプロトコルスイートです。NLPトークンの発行・管理から、マルチトークン交換システムまでを提供します。

## 📦 コントラクト一覧 (Contract List)

### 1. 💎 NewLoPoint.sol
- **機能**: ERC20準拠のNLPトークンの発行・管理
- **特徴**: 
  - Upgradeableプロキシパターン
  - 管理者権限による供給量調整
  - 標準的なERC20機能

### 2. 🏭 NewLoPointFactory.sol
- **機能**: NewLoPointトークンの工場コントラクト
- **特徴**: 
  - 複数のNLPトークンインスタンスの作成
  - 統一された管理インターフェース

### 3. 🔄 NLPToMultiTokenExchange.sol ⭐ **最新版**
- **機能**: NLPを複数トークン（ETH、USDC、USDT）に交換
- **特徴**: 
  - **🛡️ Role-based Access Control**: 細かい権限管理
  - **💰 運営手数料システム**: 独立した運営手数料の設定・管理
  - **🔗 柔軟な価格管理**: Chainlink Oracle + 外部価格データ
  - **⚡ ガスレス交換**: permit署名による無料取引
  - **🎯 Soneium対応**: オラクル限定環境への最適化

### 4. 📊 MultiTokenDistribution.sol
- **機能**: 複数トークンの一括配布システム
- **特徴**: 
  - 効率的なバッチ処理
  - 複数トークンタイプの同時配布
  - ガス効率の最適化

## 🎭 Role-Based Access Control

### 🔑 アクセス制御の役割

| 役割 | 権限 | 用途 |
|------|------|------|
| **DEFAULT_ADMIN_ROLE** | 全権限 | スーパーアドミン |
| **CONFIG_MANAGER_ROLE** | 設定管理 | トークン設定、手数料設定 |
| **PRICE_UPDATER_ROLE** | 価格更新 | 外部価格データ更新 |
| **EMERGENCY_MANAGER_ROLE** | 緊急管理 | 緊急停止、資金引き出し |
| **FEE_MANAGER_ROLE** | 手数料管理 | 運営手数料の設定・引き出し |

## 💰 運営手数料システム

### 📊 手数料の種類

1. **交換手数料 (Exchange Fee)**: 基本的な交換手数料
2. **運営手数料 (Operational Fee)**: 運営収益のための追加手数料

### 🎯 手数料制限

- **最大交換手数料**: 5% (500 basis points)
- **最大運営手数料**: 2% (200 basis points)

## 🚀 主な機能

### 💱 マルチトークン交換

```solidity
// 通常の交換
exchange.exchangeNLP(TokenType.ETH, nlpAmount);

// ガスレス交換
exchange.exchangeNLPWithPermit(TokenType.ETH, nlpAmount, deadline, v, r, s, user);
```

### 🔧 管理機能

```solidity
// 役割の付与
exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), updaterAddress);

// 運営手数料の設定
exchange.configureOperationalFee(TokenType.ETH, 50, feeRecipient, true);

// 価格データの更新
exchange.updateExternalPrice(TokenType.ETH, 2500e18);
```

## 🛡️ セキュリティ機能

### 🔒 主要セキュリティ対策

- **リエントランシー保護**: ReentrancyGuard使用
- **アクセス制御**: OpenZeppelin AccessControl使用
- **価格データ検証**: 鮮度チェック・妥当性確認
- **緊急停止機能**: Pausable機能による即座停止
- **監査済み**: 包括的なセキュリティ監査完了

### 📋 セキュリティスコア

- **総合評価**: A級（優秀）
- **テスト成功率**: 100%（34/34テスト成功）
- **Slither分析**: 深刻な脆弱性なし

## 🔧 技術仕様

### 📊 対応ブロックチェーン

- **Soneium**: オラクル限定環境向け最適化
- **Ethereum**: 完全なChainlink Oracle対応
- **その他EVM互換チェーン**: 柔軟な設定対応

### 🎯 価格管理

- **Chainlink Oracle**: 自動価格取得
- **外部価格データ**: 手動・自動更新対応
- **バッチ更新**: 効率的な価格一括更新

## 📁 ディレクトリ構造

```
newlo-point-contract/
├── src/
│   ├── NewLoPoint.sol                    # NLPトークン
│   ├── NewLoPointFactory.sol            # ファクトリー
│   ├── NLPToMultiTokenExchange.sol      # マルチトークン交換（最新版）
│   ├── MultiTokenDistribution.sol       # 配布システム
│   ├── interfaces/                      # インターフェース
│   ├── tokens/                          # トークン実装
│   └── mocks/                           # テスト用モック
├── test/                                # テストファイル
├── script/                              # デプロイスクリプト
├── docs/                                # ドキュメント
│   ├── MULTI_TOKEN_EXCHANGE_GUIDE.md    # 完全操作ガイド
│   ├── SECURITY_AUDIT_REPORT.md         # セキュリティ監査レポート
│   └── ...
└── README.md                            # このファイル
```

## 🚀 クイックスタート

### 1. 環境設定

```bash
# リポジトリのクローン
git clone <repository-url>
cd newlo-point-contract

# 依存関係のインストール
forge install

# テストの実行
forge test
```

### 2. ローカル開発環境のデプロイ

```bash
# 環境変数の設定
export PRIVATE_KEY="your-private-key"

# ローカル環境でのデプロイ
forge script script/DeployMultiTokenExchange.s.sol:DeployMultiTokenExchangeLocal \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 3. Soneium本番環境へのデプロイ

```bash
# Soneium環境でのデプロイ
forge script script/DeployMultiTokenExchange.s.sol:DeployMultiTokenExchange \
  --rpc-url https://rpc.soneium.org \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 📚 ドキュメント


### 📖 詳細ガイド

- **📜[コントラクトアドレス](docs/CONTRACT_ADDRESS.md)**: デプロイ済み
- **[マルチトークン交換システム完全ガイド](docs/MULTI_TOKEN_EXCHANGE_GUIDE.md)**: 包括的な操作手順
- **[セキュリティ監査レポート](docs/SECURITY_AUDIT_REPORT.md)**: 詳細な監査結果
- **[本番運用ガイド](docs/PRODUCTION_OPERATIONS_GUIDE.md)**: 運用時の注意事項

### 🔍 機能別ガイド

- **[ガスレス交換ガイド](docs/GASLESS_EXCHANGE_GUIDE.md)**: permit署名の使用方法
- **[配布システムガイド](docs/MULTI_TOKEN_DISTRIBUTION_GUIDE.md)**: 効率的な配布方法
- **[ローカル開発ガイド](LOCAL_DEVELOPMENT_GUIDE.md)**: 開発環境の構築

## 🧪 テスト

### 🔬 テスト実行

```bash
# 全テストの実行
forge test

# 詳細出力でのテスト
forge test -vv

# 特定のテストの実行
forge test --match-contract NLPToMultiTokenExchangeTest

# カバレッジの確認
forge coverage
```

### 📊 テスト結果

- **テスト成功率**: 100%（34/34テスト成功）
- **カバレッジ**: 高水準のコード網羅率
- **テストカテゴリ**: 
  - 基本機能テスト
  - セキュリティテスト
  - エラーハンドリングテスト
  - インテグレーションテスト
  - Fuzzテスト

## 🔄 更新履歴

### v0.4.0 (最新版)
- ✅ Role-based Access Control導入
- ✅ 運営手数料システム追加
- ✅ セキュリティ強化
- ✅ 34項目のテスト完了
- ✅ 包括的なセキュリティ監査完了

### v0.3.0
- ✅ 基本的なマルチトークン交換機能
- ✅ Chainlink Oracle対応
- ✅ ガスレス交換機能

### v0.1.0
- ✅ NewLo Pointトークン
- ✅ NLP配布機能

## 🤝 貢献

### 📝 コントリビューション

1. フォークしてプルリクエストを作成
2. テストの追加・更新
3. セキュリティ脆弱性の報告
4. ドキュメントの改善

### 🐛 バグレポート

- GitHub Issuesでバグを報告
- セキュリティ関連は直接連絡

## 📄 ライセンス

MIT License - 詳細は [LICENSE](LICENSE) を参照

## 🔗 リンク

- **公式サイト**: [NewLo Official](https://newlo.jp)
- **公式クエストサイト**: [NewLo Quest](https://app.quest.newlo.jp)
- **ドキュメント**: [Docs](docs/)
- **GitHub**: [Repository](https://github.com/k0yote/newlo-point)

---

**NewLo Point Contract System** - 次世代DeFiプロトコルスイート 🚀
