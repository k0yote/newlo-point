# NLPToMultiTokenExchange コントラクト 交換ロジック説明書

## 概要

`NLPToMultiTokenExchange` は NewLo Point (NLP) トークンを複数のトークン（ETH、USDC、USDT）に交換するためのスマートコントラクトです。本ドキュメントはディレクターやユーザー向けに交換ロジックの仕組みを説明します。

## 基本的な交換フロー

### 1. 交換式の構造

```
NLP → JPY → USD → Target Token
```

交換は以下の3段階で計算されます：

1. **NLP → JPY**: 設定可能なレートで変換
2. **JPY → USD**: オラクルまたは外部価格データを使用
3. **USD → Target Token**: Chainlinkオラクルを使用

### 2. 詳細な計算式

```
最終トークン量 = (NLP量 × NLP-JPYレート ÷ 分母 × JPY-USDレート) ÷ トークン-USDレート - 交換手数料 - 運営手数料
```

## 対応トークン

| トークン | タイプ | 説明 |
|----------|--------|------|
| ETH | `TokenType.ETH` | イーサリアム（ネイティブ通貨） |
| USDC | `TokenType.USDC` | USD Coin |
| USDT | `TokenType.USDT` | Tether USD |

## 価格データソース

### 1. Chainlinkオラクル
- ETH/USD: 常に必須
- USDC/USD: 利用可能な場合
- USDT/USD: 利用可能な場合
- JPY/USD: 利用可能な場合（Soneium環境では通常不可）

### 2. 外部価格データ
- JPY/USD: Chainlink形式の外部データ（Soneium環境用）
- リアルタイム更新可能

## 手数料システム

### 1. 交換手数料（Exchange Fee）
- トークンごとに設定可能
- ベーシスポイント単位（100 = 1%）
- 最大手数料率制限あり（初期値: 5%）

### 2. 運営手数料（Operational Fee）
- トークンごとに個別設定
- 手数料受取人指定可能
- 有効/無効切り替え可能

## 主要な機能

### 1. 標準的な交換
```solidity
function exchangeNLP(TokenType tokenType, uint nlpAmount)
```
- 基本的なNLP交換機能
- スリッページ保護なし

### 2. スリッページ保護付き交換
```solidity
function exchangeNLPWithSlippage(TokenType tokenType, uint nlpAmount, uint minAmountOut)
```
- 最小受取量を指定
- 価格変動による損失を防止

### 3. ガスレス交換（Permit使用）
```solidity
function exchangeNLPWithPermit(/* パラメータ */)
function exchangeNLPWithPermitAndSlippage(/* パラメータ */)
```
- EIP-2612 Permit機能を使用
- リレーヤーによるガス代負担
- スリッページ保護版も提供

## セキュリティ機能

### 1. アクセス制御
- **DEFAULT_ADMIN_ROLE**: 最高管理権限
- **CONFIG_MANAGER_ROLE**: トークン・手数料設定
- **PRICE_UPDATER_ROLE**: 価格データ更新
- **EMERGENCY_MANAGER_ROLE**: 緊急停止・資金回収
- **FEE_MANAGER_ROLE**: 運営手数料管理

### 2. セキュリティ保護
- リエントランシー攻撃防止
- 緊急停止機能（Pausable）
- 価格データ検証
- CEI（Checks-Effects-Interactions）パターン

## 見積もり・計算機能

### 1. 交換見積もり
```solidity
function getExchangeQuote(TokenType tokenType, uint nlpAmount)
```
返り値：
- 受取トークン量
- 使用されるトークン/USDレート
- 使用されるJPY/USDレート
- 交換手数料
- 運営手数料

### 2. スリッページ計算
```solidity
function getExchangeQuoteWithSlippage(/* パラメータ */)
```
返り値：
- 基本見積もり情報
- 最小受取量
- 最大スリッページ量

### 3. 最小受取量計算
```solidity
function calculateMinAmountOut(TokenType tokenType, uint nlpAmount, uint slippageToleranceBps)
```

## 設定項目

### 1. NLP-JPYレート
- **現在値**: 100 (1 NLP = 1 JPY)
- **分母**: 100（固定）
- **実際のレート**: 100/100 = 1.0
- 管理者による変更可能

### 2. 最大手数料率
- **初期値**: 500 (5%)
- **絶対最大**: 10000 (100%)
- 管理者による調整可能

## 統計・履歴機能

### 1. トークン別統計
- 総交換NLP量
- 総送付トークン量
- 総交換手数料
- 総運営手数料
- 交換回数

### 2. ユーザー履歴
- ユーザー別交換履歴
- トークン別受取履歴

## 管理機能

### 1. トークン設定
- トークンの有効/無効切り替え
- 交換手数料設定
- オラクルアドレス更新

### 2. 価格データ管理
- 外部JPY/USD価格更新
- オラクルアドレス更新
- 価格データ検証

### 3. 緊急時対応
- コントラクト一時停止
- 緊急資金回収
- 財務管理アドレス設定

## 使用例

### 1. 基本的な交換
```solidity
// 100 NLP を ETH に交換
exchangeNLP(TokenType.ETH, 100 * 1e18);
```

### 2. スリッページ保護付き交換
```solidity
// 100 NLP を USDC に交換、最低 95 USDC を保証
exchangeNLPWithSlippage(TokenType.USDC, 100 * 1e18, 95 * 1e6);
```

### 3. 事前見積もり
```solidity
// 交換前に見積もりを取得
(uint tokenAmount, uint tokenRate, uint jpyRate, uint exchangeFee, uint opFee) = 
    getExchangeQuote(TokenType.USDT, 100 * 1e18);
```

## 交換計算例

### 例: 100 NLP → ETH 交換

**前提条件:**
- NLP-JPYレート: 100 (1 NLP = 1 JPY)
- JPY-USDレート: 0.0067 (1 JPY = 0.0067 USD、約150円/ドル)
- ETH-USDレート: 3,650.98398856 USD (Chainlink価格: 365098398856 / 10^8)
- 交換手数料: 100 bps (1%)
- 運営手数料: 50 bps (0.5%)

**計算手順:**
1. **NLP → JPY**: 100 NLP × (100/100) = 100 JPY
2. **JPY → USD**: 100 JPY × 0.0067 = 0.67 USD
3. **USD → ETH**: 0.67 USD ÷ 3,650.98398856 = 0.0001835557 ETH
4. **交換手数料**: 0.0001835557 × 1% = 0.000001835557 ETH
5. **運営手数料**: 0.0001835557 × 0.5% = 0.0000009177785 ETH
6. **最終受取額**: 0.0001835557 - 0.000001835557 - 0.0000009177785 = 0.0001808024 ETH

**結果:**
100 NLP で約 **0.0001808024 ETH**（手数料込み）を受け取れます。

*注: 実際の受取額は市場価格の変動により異なります。事前に `getExchangeQuote` 関数で正確な見積もりを確認することを推奨します。*

## 注意事項

1. **価格変動リスク**: 外部オラクルに依存するため価格変動の影響を受けます
2. **手数料**: 交換時に交換手数料と運営手数料が差し引かれます
3. **コントラクト残高**: 十分なトークン残高が必要です
4. **ガス代**: 交換処理にはガス代が必要です（Permit使用時を除く）

---

*本ドキュメントは技術的な実装詳細を含みます。実際の使用前には最新のコントラクト状態を確認してください。*