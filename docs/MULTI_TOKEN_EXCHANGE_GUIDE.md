# 📊 NewLo Point (NLP) マルチトークン交換システム - 完全ガイド

## 🔍 概要

NewLo Point (NLP) マルチトークン交換システムは、ユーザーがNLPトークンを複数の暗号通貨（ETH、USDC、USDT）に交換できる高度なDeFiプロトコルです。

### 🎯 主な特徴

- **💱 1:1 NLP-JPY交換率**: 1 NLP = 1 JPY の固定レート
- **🏦 マルチトークン対応**: ETH、USDC、USDT への交換をサポート
- **🔗 柔軟な価格管理**: Chainlink Oracle + 外部価格データによるハイブリッド価格システム
- **🛡️ Role-based Access Control**: 細かい権限管理による安全性の向上
- **💰 運営手数料システム**: 独立した運営手数料の設定と管理
- **⚡ ガスレス交換**: permit署名を使用したガスレス取引
- **🛡️ セキュリティ機能**: 緊急停止、アクセス制御、価格データの鮮度チェック
- **🎯 Soneium対応**: オラクルが限定的なブロックチェーンへの最適化

## 🎭 役割管理システム (Role-Based Access Control)

### 🔑 アクセス制御の役割

| 役割 | 権限 | 説明 |
|------|------|------|
| **DEFAULT_ADMIN_ROLE** | 全権限 | スーパーアドミン、他の役割の付与・剥奪 |
| **CONFIG_MANAGER_ROLE** | 設定管理 | トークン設定、交換手数料の設定 |
| **PRICE_UPDATER_ROLE** | 価格更新 | 外部価格データの更新、バッチ価格更新 |
| **EMERGENCY_MANAGER_ROLE** | 緊急管理 | 緊急停止、緊急資金引き出し |
| **FEE_MANAGER_ROLE** | 手数料管理 | 運営手数料の設定と引き出し |

### 🛡️ 役割の管理

#### 役割の付与
```solidity
// CONFIG_MANAGER_ROLE の付与
exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), newConfigManager);

// PRICE_UPDATER_ROLE の付与
exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), newPriceUpdater);

// FEE_MANAGER_ROLE の付与
exchange.grantRole(exchange.FEE_MANAGER_ROLE(), newFeeManager);
```

#### 役割の剥奪
```solidity
// 役割の剥奪
exchange.revokeRole(exchange.CONFIG_MANAGER_ROLE(), oldConfigManager);
```

#### 役割の確認
```solidity
// 役割の確認
bool hasRole = exchange.hasRole(exchange.CONFIG_MANAGER_ROLE(), userAddress);
```

## 💰 運営手数料システム

### 📊 手数料の種類

1. **交換手数料 (Exchange Fee)**: 各トークンごとの交換手数料
2. **運営手数料 (Operational Fee)**: 運営収益のための追加手数料

### 🔧 運営手数料の設定

#### 運営手数料の設定
```solidity
// ETH用の運営手数料設定 (0.5%)
exchange.configureOperationalFee(
    NLPToMultiTokenExchange.TokenType.ETH,
    50,                    // 0.5% (50 basis points)
    feeRecipientAddress,   // 手数料受取人
    true                   // 有効化
);

// USDC用の運営手数料設定 (0.25%)
exchange.configureOperationalFee(
    NLPToMultiTokenExchange.TokenType.USDC,
    25,                    // 0.25% (25 basis points)
    feeRecipientAddress,   // 手数料受取人
    true                   // 有効化
);
```

#### 運営手数料の引き出し
```solidity
// 収集された運営手数料の引き出し
exchange.withdrawOperationalFee(
    NLPToMultiTokenExchange.TokenType.ETH,
    0  // 0 = 利用可能な全額を引き出し
);

// 特定の金額の引き出し
exchange.withdrawOperationalFee(
    NLPToMultiTokenExchange.TokenType.USDC,
    1000 * 10 ** 6  // 1000 USDC
);
```

#### 運営手数料の確認
```solidity
// 収集された運営手数料の確認
uint256 collectedFee = exchange.getCollectedOperationalFee(
    NLPToMultiTokenExchange.TokenType.ETH
);

// 運営手数料設定の確認
NLPToMultiTokenExchange.OperationalFeeConfig memory config = 
    exchange.getOperationalFeeConfig(NLPToMultiTokenExchange.TokenType.ETH);
```

## 🔧 システム設定

### 🏦 トークン設定

#### トークンの設定
```solidity
// ETH設定（CONFIG_MANAGER_ROLE が必要）
exchange.configureToken(
    NLPToMultiTokenExchange.TokenType.ETH,
    address(0),              // ETH
    ethUsdOracle,           // Chainlink Oracle アドレス
    18,                     // decimals
    100,                    // 1% 交換手数料
    "ETH"                   // シンボル
);

// USDC設定
exchange.configureToken(
    NLPToMultiTokenExchange.TokenType.USDC,
    usdcTokenAddress,       // USDCトークンアドレス
    usdcUsdOracle,          // Chainlink Oracle アドレス
    6,                      // decimals
    50,                     // 0.5% 交換手数料
    "USDC"                  // シンボル
);
```

#### トークンの有効化/無効化
```solidity
// トークンの無効化
exchange.setTokenEnabled(NLPToMultiTokenExchange.TokenType.ETH, false);

// トークンの有効化
exchange.setTokenEnabled(NLPToMultiTokenExchange.TokenType.ETH, true);
```

### 💹 価格管理

#### 外部価格データの更新
```solidity
// 個別価格の更新（PRICE_UPDATER_ROLE が必要）
exchange.updateExternalPrice(
    NLPToMultiTokenExchange.TokenType.ETH,
    2500 * 10 ** 18  // 1 ETH = 2500 USD
);

// JPY/USD価格の更新
exchange.updateJPYUSDExternalPrice(
    0.0067 * 10 ** 18  // 1 JPY = 0.0067 USD
);
```

#### バッチ価格更新
```solidity
// 複数トークンの価格を一度に更新
NLPToMultiTokenExchange.TokenType[] memory tokenTypes = 
    new NLPToMultiTokenExchange.TokenType[](3);
tokenTypes[0] = NLPToMultiTokenExchange.TokenType.ETH;
tokenTypes[1] = NLPToMultiTokenExchange.TokenType.USDC;
tokenTypes[2] = NLPToMultiTokenExchange.TokenType.USDT;

uint256[] memory prices = new uint256[](3);
prices[0] = 2500 * 10 ** 18;  // ETH価格
prices[1] = 1 * 10 ** 18;     // USDC価格
prices[2] = 1 * 10 ** 18;     // USDT価格

exchange.batchUpdatePrices(
    tokenTypes,
    prices,
    0.0067 * 10 ** 18  // JPY/USD価格
);
```

## 💱 交換機能

### 🎯 基本的な交換

#### 通常の交換
```solidity
// 1. NLPトークンの承認
nlpToken.approve(exchangeAddress, nlpAmount);

// 2. 交換の実行
exchange.exchangeNLP(
    NLPToMultiTokenExchange.TokenType.ETH,
    nlpAmount
);
```

#### ガスレス交換
```solidity
// permit署名を使用したガスレス交換
exchange.exchangeNLPWithPermit(
    NLPToMultiTokenExchange.TokenType.ETH,
    nlpAmount,
    deadline,
    v, r, s,     // 署名パラメータ
    userAddress  // トークン所有者
);
```

### 📊 交換レート計算

#### 交換見積もりの取得
```solidity
// 交換見積もりの取得
(
    uint256 tokenAmount,      // 受け取るトークン量
    uint256 tokenUsdRate,     // トークン/USD レート
    uint256 jpyUsdRate,       // JPY/USD レート
    uint256 exchangeFee,      // 交換手数料
    uint256 operationalFee,   // 運営手数料
    PriceSource priceSource   // 価格データソース
) = exchange.getExchangeQuote(
    NLPToMultiTokenExchange.TokenType.ETH,
    nlpAmount
);
```

#### 計算式
```
最終受取量 = (NLP量 × JPY/USD価格) / トークン/USD価格 - 交換手数料 - 運営手数料
```

## 🛡️ セキュリティ機能

### 🚨 緊急停止機能

#### 緊急停止
```solidity
// 緊急停止（EMERGENCY_MANAGER_ROLE が必要）
exchange.pause();

// 緊急停止の解除
exchange.unpause();
```

#### 緊急資金引き出し
```solidity
// ETHの緊急引き出し
exchange.emergencyWithdrawETH(
    payable(emergencyAddress),
    0  // 0 = 全額引き出し
);

// トークンの緊急引き出し
exchange.emergencyWithdrawToken(
    NLPToMultiTokenExchange.TokenType.USDC,
    emergencyAddress,
    0  // 0 = 全額引き出し
);
```

### 🔍 監視とモニタリング

#### 統計情報の取得
```solidity
// トークン統計の取得
NLPToMultiTokenExchange.TokenStats memory stats = 
    exchange.getTokenStats(NLPToMultiTokenExchange.TokenType.ETH);

// コントラクトの状態確認
(
    uint256 ethBalance,
    bool isPaused,
    uint256 jpyUsdPrice,
    PriceSource jpyPriceSource
) = exchange.getContractStatus();
```

#### ユーザー取引履歴
```solidity
// ユーザーの取引履歴
(
    uint256 exchangedNLP,
    uint256 receivedTokens
) = exchange.getUserExchangeHistory(userAddress, tokenType);
```

## 🚀 デプロイメント

### 🏗️ 本番環境デプロイ

#### 1. 環境変数の設定
```bash
export PRIVATE_KEY="your-private-key"
export SONEIUM_RPC_URL="https://rpc.soneium.org"
```

#### 2. アドレスの設定
デプロイスクリプトの以下のアドレスを実際の値に更新：
- `SONEIUM_ADMIN`: スーパーアドミンアドレス
- `SONEIUM_PRICE_UPDATER`: 価格更新者アドレス
- `SONEIUM_FEE_MANAGER`: 手数料管理者アドレス
- `SONEIUM_EMERGENCY_MANAGER`: 緊急管理者アドレス
- `SONEIUM_CONFIG_MANAGER`: 設定管理者アドレス
- `SONEIUM_FEE_RECIPIENT`: 手数料受取人アドレス

#### 3. コントラクトのデプロイ
```bash
forge script script/DeployMultiTokenExchange.s.sol:DeployMultiTokenExchange \
  --rpc-url $SONEIUM_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 🧪 ローカルテスト環境

```bash
# ローカルテスト環境のデプロイ
forge script script/DeployMultiTokenExchange.s.sol:DeployMultiTokenExchangeLocal \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 📋 運用ガイド

### 🔄 定期的なタスク

#### 1. 価格データの更新
```bash
# 価格データの定期更新（推奨：5分間隔）
# 以下のAPIから価格データを取得し、updateExternalPriceを実行
```

#### 2. 運営手数料の引き出し
```bash
# 定期的な運営手数料の引き出し（推奨：週1回）
# 収集された手数料を確認し、必要に応じて引き出し
```

#### 3. 流動性の監視
```bash
# 各トークンの流動性を定期的に監視
# 不足している場合は追加の資金投入を検討
```

### 🚨 緊急時の対応

#### 1. 緊急停止の実行
```solidity
// 異常な活動を検出した場合
exchange.pause();
```

#### 2. 緊急資金の引き出し
```solidity
// 必要に応じて緊急資金の引き出し
exchange.emergencyWithdrawETH(safeAddress, 0);
```

#### 3. 価格データの確認
```solidity
// 価格データの異常値を確認し、必要に応じて更新
```

## 🔧 技術仕様

### 📊 手数料制限

- **最大交換手数料**: 5% (500 basis points)
- **最大運営手数料**: 2% (200 basis points)
- **価格データ有効期限**: 1時間

### 🔗 対応ブロックチェーン

- **Soneium**: オラクルが限定的な環境に最適化
- **その他のEVM互換チェーン**: Chainlink Oracle対応

### 🛡️ セキュリティ対策

- **リエントランシー保護**: ReentrancyGuard使用
- **アクセス制御**: OpenZeppelin AccessControl使用
- **価格データ検証**: 価格の鮮度とデータの妥当性をチェック
- **緊急停止機能**: Pausable機能による緊急停止

## 📝 注意事項

### ⚠️ 重要な注意点

1. **価格データの更新**: 定期的な価格データの更新が必要
2. **流動性の管理**: 各トークンの十分な流動性を維持
3. **セキュリティ**: 管理者アドレスのセキュリティを確保
4. **監視**: システムの定期的な監視と異常の早期発見

### 🔒 セキュリティ推奨事項

1. **マルチシグウォレット**: 管理者アドレスにマルチシグを使用
2. **定期的な監査**: セキュリティ監査の定期実施
3. **モニタリング**: 異常な取引活動の監視
4. **バックアップ**: 緊急時の対応プランの準備

---

このガイドは、NLPマルチトークン交換システムの包括的な操作手順を提供します。詳細な技術仕様や最新の更新については、コントラクトのコードコメントを参照してください。 