# NLPToJPYCExchangeAdapter 修正計画

## ✅ 完了ステータス: すべてのタスク完了 (2025-01-13)

## 実施した修正事項

### 1. ✅ 不要な関数の削除
- ✅ `batchBurnEscrowedNLP` - 削除完了
- ✅ `depositNLP` - 削除完了（permitのみ使用）
- ✅ `withdrawNLP` - 削除完了（ユーザー側から叩けると整合性が合わないため）
- ✅ `emergencyWithdrawNLP` - 削除完了（NLP用途ではなくネイティブコイン用途のため）
- ✅ `setTreasury` - 削除完了
- ✅ `getExchangeStats` - 削除完了
- ✅ `getContractNLPBalance` - 削除完了
- ✅ `setExchangeMode` - 削除完了
- ✅ `updateWhitelist` - 削除完了

### 2. ✅ 不要な機能の削除
- ✅ `ExchangeStats` struct - 削除完了（交換ではなくエスクローなので不要）
- ✅ `ExchangeMode` enum - 削除完了（role base実行で十分）
- ✅ `whitelist` mapping - 削除完了
- ✅ `_checkExchangePermission` - 削除完了
- ✅ `treasury` address - 削除完了
- ✅ `WHITELIST_MANAGER_ROLE` - 削除完了

### 3. ✅ 手数料機能の追加
- ✅ `exchangeFeeRate` - 追加完了（basis points）
- ✅ `operationalFeeRate` - 追加完了（basis points）
- ✅ 手数料計算ロジック - 実装完了
- ✅ `getExchangeQuote` で手数料込みの見積もり - 実装完了
- ✅ `updateExchangeFeeRate` - 追加完了
- ✅ `updateOperationalFeeRate` - 追加完了

### 4. ✅ Burn実装
- ✅ `burnEscrowedNLP` - コントラクトが保有するトークンをburn
- ✅ エスクロー残高の追跡 - 実装完了

### 5. ✅ 返金機能
- ✅ `transferEscrowedNLP` - JPYC付与失敗時のNLP返金に使用
- ✅ 柔軟な送金先指定（ユーザー本人または他のアドレス）

## 設計方針

### エスクロー vs 直接Burn
**NLPToMultiTokenExchange:**
- ユーザーがapprove → 直接burn → トークンtransfer
- 同一チェーン内で完結するのでエスクロー不要

**NLPToJPYCExchangeAdapter:**
- クロスチェーン（Soneium ↔ Polygon）
- フロー:
  1. ユーザーがSoneiumでNLPを預ける（エスクロー）
  2. オフチェーンシステムがPolygonでJPYCを送信
  3a. 成功 → OperatorがSoneiumでNLPをburn
  3b. 失敗 → OperatorがSoneiumでNLPを返金
- **エスクローが必須**

### 手数料の扱い
- On-chainで手数料率を設定・計算
- 実際の手数料徴収はoff-chain（JPYCがPolygon上）
- `getExchangeQuote` で手数料込みの見積もりを提供
- フロントエンド表示用

## ✅ 実装完了の詳細

### ✅ Phase 1: 不要な関数削除（完了）
1. ✅ `batchBurnEscrowedNLP` 削除
2. ✅ `depositNLP` 削除
3. ✅ `withdrawNLP` 削除
4. ✅ `emergencyWithdrawNLP` 削除
5. ✅ `setTreasury` 削除
6. ✅ `getExchangeStats` 削除
7. ✅ `getContractNLPBalance` 削除
8. ✅ `setExchangeMode` 削除
9. ✅ `updateWhitelist` 削除
10. ✅ テスト更新（58テスト → 39テスト、すべて合格）

### ✅ Phase 2: 手数料機能追加（完了）
1. ✅ `exchangeFeeRate` 追加（basis points、MAX 10000 = 100%）
2. ✅ `operationalFeeRate` 追加（basis points、MAX 10000 = 100%）
3. ✅ 手数料設定関数追加（`updateExchangeFeeRate`, `updateOperationalFeeRate`）
4. ✅ 手数料計算ロジック追加
5. ✅ `getExchangeQuote` 更新（手数料込み見積もり）
6. ✅ テスト追加（手数料計算、設定変更のテスト）

### ✅ Phase 3: Burn実装の検証・修正（完了）
1. ✅ `nlpToken.burn(nlpAmount)` の実装確認 - 正しい実装
2. ✅ コントラクトがトークンを保有しているため、`burn()` で問題なし
3. ✅ エスクロー残高の追跡機能実装
4. ✅ テスト更新完了

### ✅ Phase 4: 返金機能の実装（完了）
1. ✅ `transferEscrowedNLP` 関数実装（返金・転送に使用）
2. ✅ イベント追加（`EscrowedNLPTransferred`）
3. ✅ テスト追加完了

### ✅ Phase 5: 総合テスト（完了）
1. ✅ 全機能のテスト（39テストすべて合格）
2. ✅ 全プロジェクトテスト（408テストすべて合格）
3. ✅ セキュリティチェック（Slither監査完了 - 問題なし）
4. ✅ デプロイメントスクリプト更新完了

## 🎯 最終成果

### コードサイズ削減
- **コントラクト**: 753行 → 518行（-31%）
- **テスト**: 58テスト → 39テスト（不要なテスト削除）
- **テスト合格率**: 100%（39/39）

### アーキテクチャの明確化
- バックエンド制御モデルの確立
- `depositNLPWithPermit` に `onlyRole(OPERATOR_ROLE)` 追加
- フロントエンド: ユーザーのpermit署名のみ
- バックエンド: すべての操作（deposit, burn, transfer）

### セキュリティ
- ✅ ReentrancyGuard
- ✅ Pausable
- ✅ AccessControl（3ロール: OPERATOR, CONFIG, PAUSER）
- ✅ Input Validation
- ✅ CEI Pattern
- ✅ Slither監査合格
