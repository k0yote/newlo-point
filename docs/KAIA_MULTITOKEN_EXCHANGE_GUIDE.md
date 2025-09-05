# 🌟 NewLo Point (NLP) Kaia マルチトークン交換システム - 完全ガイド

## 🔍 概要

NewLo Point (NLP) Kaia マルチトークン交換システムは、Kaiaブロックチェーン上でユーザーがNLPトークンを複数の暗号通貨（KAIA、USDC、USDT）に交換できる高度なDeFiプロトコルです。Chainlinkオラクルが利用できない環境に特化して設計されています。

### 🎯 主な特徴

- **💱 1:1 NLP-JPY交換率**: 1 NLP = 1 JPY の固定レート
- **🌊 Kaia対応**: Kaiaネイティブトークン（KAIA）への交換をサポート
- **🏦 マルチトークン対応**: KAIA、USDC、USDT への交換をサポート
- **📊 外部価格更新システム**: 全ての価格データを外部から更新（Pyth Network等）
- **🛡️ Role-based Access Control**: 6つの役割による細かい権限管理
- **💰 運営手数料システム**: 独立した運営手数料の設定と管理
- **⚡ ガスレス交換**: permit署名を使用したガスレス取引
- **🛡️ セキュリティ機能**: 緊急停止、アクセス制御、価格データの鮮度チェック
- **🔄 スリッページ保護**: 価格変動に対する保護機能

## 🎭 役割管理システム (Role-Based Access Control)

### 🔑 アクセス制御の役割

| 役割 | 権限 | 説明 |
|------|------|------|
| **DEFAULT_ADMIN_ROLE** | 全権限 | スーパーアドミン、他の役割の付与・剥奪 |
| **CONFIG_MANAGER_ROLE** | 設定管理 | トークン設定、交換手数料の設定 |
| **PRICE_UPDATER_ROLE** | 価格更新 | 外部価格データの更新、バッチ価格更新 |
| **EMERGENCY_MANAGER_ROLE** | 緊急管理 | 緊急停止、緊急資金引き出し |
| **FEE_MANAGER_ROLE** | 手数料管理 | 運営手数料の設定と引き出し |
| **WHITELIST_MANAGER_ROLE** | ホワイトリスト管理 | 交換許可アドレスの管理 |

### 🛡️ 役割の管理

#### 役割の付与
```solidity
// CONFIG_MANAGER_ROLE の付与
exchange.grantRole(exchange.CONFIG_MANAGER_ROLE(), newConfigManager);

// PRICE_UPDATER_ROLE の付与
exchange.grantRole(exchange.PRICE_UPDATER_ROLE(), newPriceUpdater);

// WHITELIST_MANAGER_ROLE の付与
exchange.grantRole(exchange.WHITELIST_MANAGER_ROLE(), newWhitelistManager);
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

## 💹 価格管理システム

### 📊 外部価格フィードアーキテクチャ

Kaiaブロックチェーンでは、すべての価格データが外部から更新される仕組みを採用しています：

- **KAIA/USD**: 外部価格フィード（Pyth Network等）
- **USDC/USD**: 外部価格フィード
- **USDT/USD**: 外部価格フィード  
- **JPY/USD**: 外部価格フィード

### 🔧 価格データの更新

#### 個別価格の更新
```solidity
// KAIA/USD価格の更新（PRICE_UPDATER_ROLE が必要）
exchange.updateKaiaUsdPrice(
    250 * 10 ** 18  // 1 KAIA = $0.25
);

// USDC/USD価格の更新
exchange.updateUsdcUsdPrice(
    1 * 10 ** 18  // 1 USDC = $1.00
);

// USDT/USD価格の更新
exchange.updateUsdtUsdPrice(
    1 * 10 ** 18  // 1 USDT = $1.00
);

// JPY/USD価格の更新
exchange.updateJpyUsdPrice(
    0.0067 * 10 ** 18  // 1 JPY = $0.0067
);
```

#### バッチ価格更新
```solidity
// 全ての価格を一度に更新
exchange.batchUpdatePrices(
    250 * 10 ** 18,   // KAIA/USD価格
    1 * 10 ** 18,     // USDC/USD価格  
    1 * 10 ** 18,     // USDT/USD価格
    0.0067 * 10 ** 18 // JPY/USD価格
);
```

#### 価格データの確認
```solidity
// 現在の価格データの取得
(uint256 price, uint256 timestamp) = exchange.getKaiaUsdPrice();
(uint256 price, uint256 timestamp) = exchange.getUsdcUsdPrice();
(uint256 price, uint256 timestamp) = exchange.getUsdtUsdPrice();
(uint256 price, uint256 timestamp) = exchange.getJpyUsdPrice();
```

## 💰 運営手数料システム

### 📊 手数料の種類

1. **交換手数料 (Exchange Fee)**: 各トークンごとの交換手数料
2. **運営手数料 (Operational Fee)**: 運営収益のための追加手数料

### 🔧 運営手数料の設定

#### 運営手数料の設定
```solidity
// KAIA用の運営手数料設定 (0.5%)
exchange.configureOperationalFee(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
    50,                    // 0.5% (50 basis points)
    feeRecipientAddress,   // 手数料受取人
    true                   // 有効化
);

// USDC用の運営手数料設定 (0.25%)
exchange.configureOperationalFee(
    NLPToMultiTokenKaiaExchange.TokenType.USDC,
    25,                    // 0.25% (25 basis points)
    feeRecipientAddress,   // 手数料受取人
    true                   // 有効化
);
```

#### 運営手数料の引き出し
```solidity
// 収集された運営手数料の引き出し
exchange.withdrawOperationalFee(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
    0  // 0 = 利用可能な全額を引き出し
);

// 特定の金額の引き出し
exchange.withdrawOperationalFee(
    NLPToMultiTokenKaiaExchange.TokenType.USDC,
    1000 * 10 ** 6  // 1000 USDC
);
```

## 🔧 システム設定

### 🏦 トークン設定

#### トークンの設定
```solidity
// KAIA設定（CONFIG_MANAGER_ROLE が必要）
exchange.configureToken(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
    address(0),              // KAIA (native token)
    18,                     // decimals
    100,                    // 1% 交換手数料
    "KAIA"                  // シンボル
);

// USDC設定
exchange.configureToken(
    NLPToMultiTokenKaiaExchange.TokenType.USDC,
    usdcTokenAddress,       // USDCトークンアドレス
    6,                      // decimals
    50,                     // 0.5% 交換手数料
    "USDC"                  // シンボル
);

// USDT設定
exchange.configureToken(
    NLPToMultiTokenKaiaExchange.TokenType.USDT,
    usdtTokenAddress,       // USDTトークンアドレス
    6,                      // decimals
    50,                     // 0.5% 交換手数料
    "USDT"                  // シンボル
);
```

#### トークンの有効化/無効化
```solidity
// トークンの無効化
exchange.setTokenEnabled(NLPToMultiTokenKaiaExchange.TokenType.KAIA, false);

// トークンの有効化
exchange.setTokenEnabled(NLPToMultiTokenKaiaExchange.TokenType.KAIA, true);
```

## 💱 交換機能

### 🎯 基本的な交換

#### 通常の交換
```solidity
// 1. NLPトークンの承認
nlpToken.approve(exchangeAddress, nlpAmount);

// 2. KAIA交換の実行
exchange.exchangeNLP(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
    nlpAmount
);

// 3. USDC交換の実行
exchange.exchangeNLP(
    NLPToMultiTokenKaiaExchange.TokenType.USDC,
    nlpAmount
);
```

#### スリッページ保護付き交換
```solidity
// 最小受取量を指定した交換
uint256 minReceiveAmount = expectedAmount * 95 / 100; // 5%のスリッページ許容

exchange.exchangeNLPWithSlippage(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
    nlpAmount,
    minReceiveAmount
);
```

#### ガスレス交換
```solidity
// permit署名を使用したガスレス交換
exchange.exchangeNLPWithPermit(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
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
    uint256 operationalFee    // 運営手数料
) = exchange.getExchangeQuote(
    NLPToMultiTokenKaiaExchange.TokenType.KAIA,
    nlpAmount
);
```

#### 計算式
```
最終受取量 = (NLP量 × JPY/USD価格) / トークン/USD価格 - 交換手数料 - 運営手数料
```

### 🎯 ホワイトリスト機能

#### ホワイトリストの管理
```solidity
// ホワイトリスト有効化（WHITELIST_MANAGER_ROLE が必要）
exchange.setWhitelistEnabled(true);

// アドレスをホワイトリストに追加
address[] memory addressesToAdd = new address[](2);
addressesToAdd[0] = user1Address;
addressesToAdd[1] = user2Address;
exchange.addToWhitelist(addressesToAdd);

// アドレスをホワイトリストから削除
address[] memory addressesToRemove = new address[](1);
addressesToRemove[0] = user1Address;
exchange.removeFromWhitelist(addressesToRemove);
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
// KAIAの緊急引き出し
exchange.emergencyWithdrawKaia(
    payable(emergencyAddress),
    0  // 0 = 全額引き出し
);

// トークンの緊急引き出し
exchange.emergencyWithdrawToken(
    NLPToMultiTokenKaiaExchange.TokenType.USDC,
    emergencyAddress,
    0  // 0 = 全額引き出し
);
```

### 🔍 監視とモニタリング

#### 統計情報の取得
```solidity
// トークン統計の取得
NLPToMultiTokenKaiaExchange.TokenStats memory stats = 
    exchange.getTokenStats(NLPToMultiTokenKaiaExchange.TokenType.KAIA);

// コントラクトの状態確認
(
    uint256 kaiaBalance,
    bool isPaused,
    uint256 jpyUsdPrice,
    uint256 priceTimestamp
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

### 🏗️ Kaiaメインネット デプロイ

#### 1. 環境変数の設定
```bash
export PRIVATE_KEY="your-private-key"
export KAIA_RPC_URL="https://public-en-cypress.klaytn.net"
```

#### 2. アドレスの設定
デプロイスクリプトの以下のアドレスを実際の値に更新：
- `KAIA_ADMIN`: スーパーアドミンアドレス
- `KAIA_PRICE_UPDATER`: 価格更新者アドレス
- `KAIA_FEE_MANAGER`: 手数料管理者アドレス
- `KAIA_EMERGENCY_MANAGER`: 緊急管理者アドレス
- `KAIA_CONFIG_MANAGER`: 設定管理者アドレス
- `KAIA_WHITELIST_MANAGER`: ホワイトリスト管理者アドレス
- `KAIA_FEE_RECIPIENT`: 手数料受取人アドレス

#### 3. コントラクトのデプロイ
```bash
forge script script/DeployKaiaExchange.s.sol:DeployKaiaExchange \
  --rpc-url $KAIA_RPC_URL \
  --private-key $PRIVATE_KEY \
  --broadcast
```

### 🧪 ローカルテスト環境

```bash
# ローカルテスト環境のデプロイ
forge script script/DeployKaiaExchange.s.sol:DeployKaiaExchangeLocal \
  --rpc-url http://localhost:8545 \
  --private-key $PRIVATE_KEY \
  --broadcast
```

## 📋 運用ガイド

### 🔄 定期的なタスク

#### 1. 価格データの更新
```bash
# 価格データの定期更新（推奨：5分間隔）
# Pyth Network等のAPIから価格データを取得し、batchUpdatePricesを実行
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
exchange.emergencyWithdrawKaia(safeAddress, 0);
```

#### 3. 価格データの確認
```solidity
// 価格データの異常値を確認し、必要に応じて更新
```

## 🔧 技術仕様

### 📊 手数料制限

- **最大交換手数料**: 5% (500 basis points)
- **最大運営手数料**: 2% (200 basis points)
- **価格データ有効期限**: 1時間 (3600秒)

### 🔗 対応ブロックチェーン

- **Kaia (Klaytn)**: メインネット/テストネット
- **完全外部価格依存**: Chainlinkオラクルに依存しない設計

### 🛡️ セキュリティ対策

- **リエントランシー保護**: ReentrancyGuard使用
- **アクセス制御**: OpenZeppelin AccessControl使用
- **価格データ検証**: 価格の鮮度とデータの妥当性をチェック
- **緊急停止機能**: Pausable機能による緊急停止
- **スリッページ保護**: 最小受取量の指定が可能
- **ホワイトリスト制御**: 許可されたアドレスのみ交換可能（オプション）

## 🌐 Pyth Network統合例

### 価格データの取得と更新
```javascript
// Pyth Network APIからの価格取得例
async function updatePricesFromPyth() {
    const pythEndpoint = "https://hermes.pyth.network/api/latest_price_feeds";
    
    // KAIA/USD価格ID (例)
    const kaiaUsdPriceId = "0x...";
    const usdcUsdPriceId = "0x...";
    const usdtUsdPriceId = "0x...";
    
    const response = await fetch(`${pythEndpoint}?ids[]=${kaiaUsdPriceId}&ids[]=${usdcUsdPriceId}&ids[]=${usdtUsdPriceId}`);
    const data = await response.json();
    
    // 価格データの解析と更新
    for (const priceData of data) {
        const price = priceData.price.price * Math.pow(10, 18 + priceData.price.expo);
        
        // コントラクトの価格更新関数を呼び出し
        // await exchange.updateKaiaUsdPrice(price);
    }
}
```

## 📝 注意事項

### ⚠️ 重要な注意点

1. **価格データの更新**: Pythネットワーク等からの定期的な価格データ更新が必須
2. **流動性の管理**: 各トークン（KAIA、USDC、USDT）の十分な流動性を維持
3. **セキュリティ**: 管理者アドレスのセキュリティを確保
4. **監視**: システムの定期的な監視と異常の早期発見
5. **ホワイトリスト**: 必要に応じてホワイトリスト機能を有効化

### 🔒 セキュリティ推奨事項

1. **マルチシグウォレット**: 管理者アドレスにマルチシグを使用
2. **定期的な監査**: セキュリティ監査の定期実施
3. **モニタリング**: 異常な取引活動の監視
4. **バックアップ**: 緊急時の対応プランの準備
5. **価格フィード監視**: 外部価格データの信頼性を定期的に確認

### 🎯 Kaia特有の考慮事項

1. **ネットワーク手数料**: KAIAトークンでの手数料支払い
2. **ブロック時間**: Kaiaの約1秒のブロック時間を活用
3. **外部価格依存**: Chainlinkの代替としてPyth Networkの活用
4. **ガス最適化**: Kaiaネットワークの効率的なガス利用

---

このガイドは、NLP Kaiaマルチトークン交換システムの包括的な操作手順を提供します。Kaiaブロックチェーンの特性に最適化された設計により、効率的で安全なトークン交換サービスを実現しています。