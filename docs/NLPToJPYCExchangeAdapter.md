# NLPToJPYCExchangeAdapter

## 📋 概要

NLPToJPYCExchangeAdapterは、Soneium上のNewLo Point (NLP) トークンとPolygon上のJPYC (Japanese Yen Coin) の**クロスチェーン交換を可能にする、バックエンド制御型のエスクローコントラクト**です。

### 🎯 主要な特徴

- **クロスチェーン対応**: Soneium ↔ Polygon間のトークン交換
- **バックエンド制御**: すべての操作はOPERATOR_ROLEによって実行
- **ガスレストランザクション**: EIP-2612 permitによる署名ベースの承認
- **手数料システム**: 交換手数料とオペレーション手数料の柔軟な設定
- **セキュリティ重視**: ReentrancyGuard、Pausable、AccessControl実装
- **エスクロー追跡**: ユーザーごとのエスクロー残高管理

## 🏗️ アーキテクチャ

### クロスチェーンフロー

```
┌─────────────────────────────────────────────────────────────────┐
│                    1. User Signs Permit                         │
│                      (Frontend Only)                            │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│         2. Backend Executes depositNLPWithPermit                │
│              (Soneium - OPERATOR_ROLE)                          │
│                    Escrow NLP                                   │
└───────────────────────┬─────────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────────┐
│          3. Backend Sends JPYC to User                          │
│              (Polygon - Off-chain)                              │
└───────────────────────┬─────────────────────────────────────────┘
                        │
            ┌───────────┴───────────┐
            │                       │
            ▼                       ▼
┌───────────────────┐   ┌───────────────────────┐
│   4a. SUCCESS     │   │   4b. FAILURE         │
│                   │   │                       │
│ burnEscrowedNLP   │   │ transferEscrowedNLP   │
│ (Soneium - Burn)  │   │ (Soneium - Refund)    │
└───────────────────┘   └───────────────────────┘
```

### コントラクト構造

```
NLPToJPYCExchangeAdapter
├── AccessControl (ロールベースアクセス制御)
│   ├── OPERATOR_ROLE (バックエンド操作)
│   ├── CONFIG_ROLE (設定変更)
│   └── PAUSER_ROLE (緊急停止)
├── ReentrancyGuard (リエントランシー攻撃防止)
├── Pausable (緊急停止機能)
└── Core Functions
    ├── depositNLPWithPermit (エスクロー預け入れ)
    ├── burnEscrowedNLP (エスクロー焼却)
    ├── transferEscrowedNLP (エスクロー返金・転送)
    └── Configuration (設定変更)
```

## 💼 主要な機能

### 1. エスクロー預け入れ (OPERATOR_ROLE専用)

```solidity
function depositNLPWithPermit(
    uint nlpAmount,
    uint deadline,
    uint8 v,
    bytes32 r,
    bytes32 s,
    address user
) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE)
```

**用途**: ユーザーのpermit署名を使用してNLPをエスクロー

**フロー**:
1. フロントエンドでユーザーがpermit署名を生成
2. バックエンドがこの関数を呼び出し
3. NLPがコントラクトにエスクロー

### 2. エスクロー焼却 (OPERATOR_ROLE専用)

```solidity
function burnEscrowedNLP(
    address user,
    uint nlpAmount,
    string calldata reason
) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE)
```

**用途**: JPYC付与成功後、エスクローされたNLPを焼却

### 3. エスクロー返金・転送 (OPERATOR_ROLE専用)

```solidity
function transferEscrowedNLP(
    address from,
    address to,
    uint nlpAmount,
    string calldata reason
) external nonReentrant whenNotPaused onlyRole(OPERATOR_ROLE)
```

**用途**: JPYC付与失敗時の返金、または他のアドレスへの転送

### 4. 見積もり取得 (誰でも可能)

```solidity
function getExchangeQuote(TokenType tokenType, uint nlpAmount)
    external
    view
    returns (
        uint jpycAmount,
        uint rate,
        uint denominator,
        uint exchangeFee,
        uint operationalFee
    )
```

**用途**: フロントエンドで手数料込みの交換見積もりを表示

## ⚙️ 設定管理

### 手数料設定 (CONFIG_ROLE)

```solidity
// 交換手数料: 0-10000 (0%-100%)
function updateExchangeFeeRate(uint newFeeRate) external

// オペレーション手数料: 0-10000 (0%-100%)
function updateOperationalFeeRate(uint newFeeRate) external
```

### レート設定 (CONFIG_ROLE)

```solidity
// NLP to JPYC レート: 100 = 1:1
function updateNLPToJPYCRate(uint newRate) external

// 最小預け入れ額
function updateMinDepositAmount(uint newAmount) external
```

## 📊 ユーザーエスクロー情報

### UserEscrow構造体

```solidity
struct UserEscrow {
    uint totalDeposited;    // 累積預け入れ額
    uint totalBurned;       // 累積焼却額
    uint currentBalance;    // 現在のエスクロー残高
    uint depositCount;      // 預け入れ回数
    uint lastDepositTime;   // 最終預け入れ時刻
}
```

### 取得方法

```solidity
UserEscrow memory escrow = adapter.getUserEscrow(userAddress);
```

## 🔐 セキュリティ

### 実装済みセキュリティ機能

✅ **ReentrancyGuard**: リエントランシー攻撃防止
✅ **Pausable**: 緊急停止機能
✅ **AccessControl**: ロールベースアクセス制御
✅ **Input Validation**: ゼロアドレス・ゼロ金額チェック
✅ **CEI Pattern**: Checks-Effects-Interactions パターン
✅ **Safe Math**: Solidity 0.8.27のオーバーフロー保護

### Slither監査結果

- **日付**: 2025-01-13
- **結果**: ✅ 合格
- **重大な脆弱性**: なし
- **検出結果**: すべて誤検知または情報提供のみ

## 📝 イベント

### GaslessDepositExecuted
```solidity
event GaslessDepositExecuted(
    address indexed user,
    address indexed operator,
    uint nlpAmount,
    uint jpycEquivalent
);
```

### EscrowedNLPBurned
```solidity
event EscrowedNLPBurned(
    address indexed user,
    address indexed operator,
    uint nlpAmount,
    uint jpycEquivalent,
    string reason
);
```

### EscrowedNLPTransferred
```solidity
event EscrowedNLPTransferred(
    address indexed from,
    address indexed to,
    address indexed operator,
    uint nlpAmount,
    string reason
);
```

## 🚀 デプロイメント

### コンストラクタパラメータ

```solidity
constructor(
    address _nlpToken,           // SoneiumのNLPトークンアドレス
    address _defaultAdmin,       // デフォルト管理者
    uint _exchangeFeeRate,       // 交換手数料 (0-10000)
    uint _operationalFeeRate     // オペレーション手数料 (0-10000)
)
```

### デプロイスクリプト

```bash
# Soneium Mainnet
forge script script/DeployJPYCExchangeAdapter.s.sol:DeployJPYCExchangeAdapter \
    --rpc-url $SONEIUM_RPC_URL \
    --broadcast \
    --verify

# Soneium Minato Testnet
forge script script/DeployJPYCExchangeAdapter.s.sol:DeployJPYCExchangeAdapterSoneium \
    --rpc-url $SONEIUM_MINATO_RPC_URL \
    --broadcast \
    --verify
```

### 環境変数

```bash
SONEIUM_ADMIN=0x...              # 管理者アドレス
SONEIUM_OPERATOR=0x...           # オペレーターアドレス
SONEIUM_NLP_TOKEN=0x...          # NLPトークンアドレス（Soneium）
INITIAL_NLP_TO_JPYC_RATE=100    # 初期レート（100 = 1:1）
MIN_DEPOSIT_AMOUNT=1000000000000000000  # 最小預け入れ額（1 NLP）
```

## 🧪 テスト

### テスト実行

```bash
# NLPToJPYCExchangeAdapterのテストのみ
forge test --match-path test/NLPToJPYCExchangeAdapter.t.sol -vv

# すべてのテスト
forge test
```

### テストカバレッジ

- **テスト数**: 39
- **合格率**: 100%
- **カバレッジ**:
  - ✅ 初期化とデプロイメント
  - ✅ Permit預け入れ（正常系・異常系）
  - ✅ エスクロー焼却（正常系・異常系）
  - ✅ エスクロー転送・返金（正常系・異常系）
  - ✅ 設定変更（レート、手数料、最小額）
  - ✅ アクセス制御
  - ✅ Pause機能

## 📈 ガス最適化

- `unchecked` ブロックの使用（オーバーフロー保護が不要な箇所）
- 状態変数の効率的な配置
- イベントの最適化

## ⚠️ 重要な注意事項

### ユーザー側の制限

❌ **ユーザーは直接コントラクトを呼び出せません**
- すべての操作はOPERATOR_ROLE（バックエンド）が実行
- ユーザーはフロントエンドでpermit署名を生成するのみ

### クロスチェーン制約

⚠️ **JPYCはPolygonネットワーク上にのみ存在**
- このコントラクトはSoneium上のNLPエスクローのみを管理
- JPYC送金はPolygon上でバックエンドが別途実行

### バックエンドの責任

バックエンドは以下を実行する必要があります：
1. ユーザーのpermit署名を受け取る
2. Soneium上で`depositNLPWithPermit`を呼び出し
3. Polygon上でJPYCを送金
4. 成功時: Soneium上で`burnEscrowedNLP`を呼び出し
5. 失敗時: Soneium上で`transferEscrowedNLP`を呼び出し（返金）

## 📚 関連リソース

- [OpenZeppelin AccessControl](https://docs.openzeppelin.com/contracts/5.x/access-control)
- [EIP-2612: Permit Extension](https://eips.ethereum.org/EIPS/eip-2612)
- [ReentrancyGuard](https://docs.openzeppelin.com/contracts/5.x/api/utils#ReentrancyGuard)
- [Pausable](https://docs.openzeppelin.com/contracts/5.x/api/utils#Pausable)

## 📞 サポート

問題や質問がある場合は、GitHubのIssueを作成してください。

---

**最終更新日**: 2025-01-13
**バージョン**: 1.0.0
**Solidity**: ^0.8.27
**ライセンス**: MIT
