# MultiTokenDistribution Guide

## 概要

MultiTokenDistributionコントラクトは、NewLoエコシステムにおいて複数のERC20トークン（WETH、USDC、USDT等）を効率的に配布するためのコントラクトです。Role-basedアクセス制御により、異なる権限レベルでの安全で効率的な運用を実現します。

## 主な機能

### 🎯 **多様なトークンサポート**
- WETH (Wrapped Ether)
- USDC (USD Coin)
- USDT (Tether USD)
- wstETH (Wrapped Staked ETH)
- stETH (Staked ETH)
- ASTR (Astar Token)
- その他のERC20トークン

### 🔐 **Role-basedアクセス制御**
- **ADMIN_ROLE**: 全ての管理権限、役割の付与・取り消し
- **DISTRIBUTOR_ROLE**: トークン配布の実行権限
- **TOKEN_MANAGER_ROLE**: トークンの追加・設定権限
- **EMERGENCY_ROLE**: 緊急時の操作権限（pause/unpause、緊急引き出し）

### 🔧 **管理機能**
- トークンの追加・削除
- トークンの有効/無効切り替え
- 緊急時の一時停止機能
- バッチ配布機能
- Role-basedな権限管理

### 📊 **統計・履歴機能**
- 配布統計の追跡
- ユーザー別の受取履歴
- トークン別の配布記録

## Soneiumトークンアドレス

### Soneium Mainnet (Chain ID: 1868)
| トークン | アドレス | デシマル |
|---------|---------|---------|
| WETH | `0x4200000000000000000000000000000000000006` | 18 |
| USDT | `0x3A337a6adA9d885b6Ad95ec48F9b75f197b5AE35` | 6 |
| USDC | `0xbA9986D2381edf1DA03B0B9c1f8b00dc4AacC369` | 6 |
| wstETH | `0xaA9BD8c957D803466FA92504BDd728cC140f8941` | 18 |
| stETH | `0x0Ce031AEd457C870D74914eCAA7971dd3176cDAF` | 18 |
| ASTR | `0x2CAE934a1e84F693fbb78CA5ED3B0A6893259441` | 18 |

### Soneium Minato Testnet (Chain ID: 1946)
| トークン | アドレス | デシマル |
|---------|---------|---------|
| WETH | `0x4200000000000000000000000000000000000006` | 18 |
| USDC | `0xE9A198d38483aD727ABC8b0B1e16B2d338CF0391` | 6 |
| wstETH | `0x5717D6A621aA104b0b4cAd32BFe6AD3b659f269E` | 18 |

## アクセス制御システム

### 役割の定義

#### ADMIN_ROLE (デフォルト管理者ロール)
- 全ての機能へのアクセス権限
- 他の役割の付与・取り消し権限
- 最高レベルの管理権限

#### DISTRIBUTOR_ROLE
- `distributeToken()`: 単一ユーザーへの配布
- `batchDistributeToken()`: バッチ配布

#### TOKEN_MANAGER_ROLE
- `addToken()`: 新しいトークンの追加
- `setTokenStatus()`: トークンの有効/無効切り替え

#### EMERGENCY_ROLE
- `pause()`/`unpause()`: コントラクトの一時停止/再開
- `emergencyWithdraw()`: 緊急時のトークン引き出し

### 役割の管理

#### 役割の付与
```solidity
// ADMIN_ROLEを持つアカウントのみ実行可能
distribution.grantRole(DISTRIBUTOR_ROLE, distributorAddress);
distribution.grantRole(TOKEN_MANAGER_ROLE, tokenManagerAddress);
distribution.grantRole(EMERGENCY_ROLE, emergencyManagerAddress);
```

#### 役割の取り消し
```solidity
// ADMIN_ROLEを持つアカウントのみ実行可能
distribution.revokeRole(DISTRIBUTOR_ROLE, distributorAddress);
```

#### 役割の確認
```solidity
// 特定のアカウントが役割を持っているかチェック
bool hasRole = distribution.hasRole(DISTRIBUTOR_ROLE, distributorAddress);
```

## デプロイメント

### 1. 環境設定
```bash
# .envファイルを作成
cp .env.example .env

# 必要な環境変数を設定
PRIVATE_KEY=0x...  # デプロイヤーの秘密鍵
RPC_URL=https://rpc.soneium.org/  # SoneiumのRPC URL
```

### 2. コントラクトのデプロイ

#### 完全デプロイメント（推奨）
```bash
# Soneium Mainnetにデプロイ（トークン設定も含む）
forge script script/DeployMultiTokenDistribution.s.sol:DeployMultiTokenDistribution --rpc-url $RPC_URL --broadcast --verify

# Soneium Minato Testnetにデプロイ
forge script script/DeployMultiTokenDistribution.s.sol:DeployMultiTokenDistribution --rpc-url https://rpc.minato.soneium.org/ --broadcast --verify
```

#### コントラクトのみデプロイ
```bash
# コントラクトのみデプロイ（トークン設定は後で手動）
forge script script/DeployMultiTokenDistribution.s.sol:DeployMultiTokenDistributionOnly --rpc-url $RPC_URL --broadcast --verify
```

#### 後からトークンを設定
```bash
# 既存のコントラクトにトークンを設定
export DISTRIBUTION_ADDRESS=0x...  # デプロイされたコントラクトのアドレス
forge script script/DeployMultiTokenDistribution.s.sol:SetupTokensScript --rpc-url $RPC_URL --broadcast
```

## 使用方法

### 1. トークンの追加（TOKEN_MANAGER_ROLE必要）
```solidity
// TOKEN_MANAGER_ROLEを持つアカウントが実行
distribution.addToken("WETH", 0x4200000000000000000000000000000000000006, 18);
```

### 2. 単一ユーザーへの配布（DISTRIBUTOR_ROLE必要）
```solidity
// DISTRIBUTOR_ROLEを持つアカウントが実行
// 1 ETH分のWETHを配布
distribution.distributeToken("WETH", userAddress, 1 ether);

// 1000 USDCを配布
distribution.distributeToken("USDC", userAddress, 1000 * 10**6);
```

### 3. バッチ配布（DISTRIBUTOR_ROLE必要）
```solidity
address[] memory users = [user1, user2, user3];
uint256[] memory amounts = [1 ether, 2 ether, 3 ether];

// DISTRIBUTOR_ROLEを持つアカウントが実行
// 複数ユーザーに一括配布
distribution.batchDistributeToken("WETH", users, amounts);
```

### 4. 配布履歴の確認（誰でも実行可能）
```solidity
// ユーザーの全配布履歴を取得
DistributionRecord[] memory history = distribution.getUserDistributionHistory(userAddress);

// 特定トークンの配布履歴を取得
DistributionRecord[] memory wethHistory = distribution.getUserTokenHistory(userAddress, "WETH");
```

### 5. 統計情報の取得（誰でも実行可能）
```solidity
// 総配布回数
uint256 totalDistributions = distribution.totalDistributions();

// 総ユーザー数
uint256 totalUsers = distribution.totalUsers();

// 特定トークンの統計
(address tokenAddress, uint8 decimals, bool isActive, uint256 totalDistributed, uint256 totalUsers) = 
    distribution.supportedTokens("WETH");
```

## 管理機能

### トークンの有効/無効切り替え（TOKEN_MANAGER_ROLE必要）
```solidity
// TOKEN_MANAGER_ROLEを持つアカウントが実行
// トークンを無効化
distribution.setTokenStatus("WETH", false);

// トークンを有効化
distribution.setTokenStatus("WETH", true);
```

### 緊急時の機能（EMERGENCY_ROLE必要）
```solidity
// EMERGENCY_ROLEを持つアカウントが実行
// コントラクトを一時停止
distribution.pause();

// 一時停止を解除
distribution.unpause();

// 緊急時のトークン引き出し
distribution.emergencyWithdraw("WETH", adminAddress, 10 ether);

// 全トークンを引き出し（amount=0で全額）
distribution.emergencyWithdraw("WETH", adminAddress, 0);
```

### 役割管理（ADMIN_ROLE必要）
```solidity
// ADMIN_ROLEを持つアカウントが実行
// 配布担当者を追加
distribution.grantRole(DISTRIBUTOR_ROLE, distributorAddress);

// トークン管理者を追加
distribution.grantRole(TOKEN_MANAGER_ROLE, tokenManagerAddress);

// 緊急時管理者を追加
distribution.grantRole(EMERGENCY_ROLE, emergencyManagerAddress);

// 役割を取り消し
distribution.revokeRole(DISTRIBUTOR_ROLE, oldDistributorAddress);
```

## テスト

### 全テストを実行
```bash
forge test --match-contract MultiTokenDistributionTest -vv
```

### 特定のテスト実行
```bash
# 配布機能のテスト
forge test --match-test test_distributeToken -vv

# バッチ配布のテスト
forge test --match-test test_batchDistribute -vv
```

## セキュリティ機能

### 1. **Role-basedアクセス制御**
- OpenZeppelinのAccessControlを使用
- 最小権限の原則に基づく権限分離
- ADMIN_ROLEによる役割管理
- 4つの異なる役割による細分化された権限

### 2. **再帰攻撃対策**
- ReentrancyGuardによる保護
- CEI（Checks-Effects-Interactions）パターンの実装

### 3. **緊急時対応**
- Pausable機能による緊急停止（EMERGENCY_ROLE）
- 緊急時のトークン引き出し機能（EMERGENCY_ROLE）

### 4. **入力検証**
- 包括的な入力パラメータの検証
- カスタムエラーによる明確なエラーメッセージ

### 5. **安全なトークン操作**
- SafeERC20による安全なトークン転送
- 残高チェックによるオーバーフロー防止

## 実装の利点

### 1. **セキュリティ**
- Role-basedアクセス制御による権限分離
- 最小権限の原則の実装
- 各操作に必要な最小限の権限のみを付与

### 2. **効率性**
- 標準的なERC20インターフェースを使用
- 追加のwrap処理が不要
- ガス効率の良い実装

### 3. **拡張性**
- 新しいトークンの簡単な追加
- 設定可能なトークン状態管理
- 将来的な機能拡張に対応

### 4. **運用性**
- 包括的な統計情報
- 詳細な配布履歴
- バッチ処理による効率的な操作
- 柔軟な権限管理システム

### 5. **安全性**
- 業界標準のセキュリティパターン
- 包括的なテストカバレッジ
- 緊急時対応機能

## 運用シナリオ

### 標準的な運用体制
```solidity
// 初期設定（デプロイ時）
constructor(adminAddress) // 管理者にすべての役割を付与

// 運用開始時の役割分離
// 1. 配布専用アカウントを設定
distribution.grantRole(DISTRIBUTOR_ROLE, distributorBot);

// 2. トークン管理専用アカウントを設定
distribution.grantRole(TOKEN_MANAGER_ROLE, tokenManager);

// 3. 緊急時対応アカウントを設定
distribution.grantRole(EMERGENCY_ROLE, emergencyManager);

// 4. 必要に応じて管理者から他の役割を削除（最小権限の原則）
distribution.revokeRole(DISTRIBUTOR_ROLE, admin);
distribution.revokeRole(TOKEN_MANAGER_ROLE, admin);
distribution.revokeRole(EMERGENCY_ROLE, admin);
```

### 緊急時の対応手順
1. **EMERGENCY_ROLE**を持つアカウントがコントラクトを一時停止
2. 問題の調査と対応策の検討
3. 必要に応じて緊急引き出しを実行
4. 修正後にコントラクトを再開

## 使用例

### 基本的な配布フロー（Role-based）
```solidity
// 1. トークンを追加（TOKEN_MANAGER_ROLEが必要）
// tokenManagerアカウントが実行
distribution.addToken("WETH", 0x4200000000000000000000000000000000000006, 18);

// 2. コントラクトにトークンを送金（誰でも可能）
IERC20(wethAddress).transfer(distributionAddress, 100 ether);

// 3. ユーザーに配布（DISTRIBUTOR_ROLEが必要）
// distributorアカウントが実行
distribution.distributeToken("WETH", user1, 1 ether);
distribution.distributeToken("WETH", user2, 2 ether);

// 4. 結果確認（誰でも可能）
uint256 user1Balance = distribution.userReceivedAmounts(user1, "WETH");
// user1Balance = 1 ether
```

### 役割別の操作例
```solidity
// === ADMIN_ROLE（管理者）の操作 ===
// 役割の付与
distribution.grantRole(DISTRIBUTOR_ROLE, distributorBot);
distribution.grantRole(TOKEN_MANAGER_ROLE, tokenManager);
distribution.grantRole(EMERGENCY_ROLE, emergencyManager);

// === TOKEN_MANAGER_ROLE（トークン管理者）の操作 ===
// 新しいトークンの追加
distribution.addToken("USDC", usdcAddress, 6);
distribution.addToken("USDT", usdtAddress, 6);

// トークンの無効化
distribution.setTokenStatus("USDT", false);

// === DISTRIBUTOR_ROLE（配布担当者）の操作 ===
// 単一配布
distribution.distributeToken("WETH", user1, 1 ether);

// バッチ配布
address[] memory users = [user1, user2, user3];
uint256[] memory amounts = [1 ether, 2 ether, 3 ether];
distribution.batchDistributeToken("WETH", users, amounts);

// === EMERGENCY_ROLE（緊急時対応者）の操作 ===
// 緊急停止
distribution.pause();

// 緊急引き出し
distribution.emergencyWithdraw("WETH", safeAddress, 10 ether);

// 運用再開
distribution.unpause();
```

### バッチ配布の例（大規模運用）
```solidity
// DISTRIBUTOR_ROLEを持つアカウントが実行
// 大量のユーザーに効率的に配布
address[] memory users = new address[](1000);
uint256[] memory amounts = new uint256[](1000);

// ユーザーと金額を設定
for (uint256 i = 0; i < 1000; i++) {
    users[i] = userAddresses[i];
    amounts[i] = 1 ether; // 各ユーザーに1 ETH相当
}

// 一括配布実行（ガス制限に注意）
distribution.batchDistributeToken("WETH", users, amounts);
```

## 注意事項

1. **トークンの事前準備**: 配布前にコントラクトに十分なトークンを送金してください
2. **Role-based権限管理**: 各役割の適切な権限管理が重要です
   - **ADMIN_ROLE**: 最も重要な役割。安全に管理してください
   - **DISTRIBUTOR_ROLE**: 配布専用アカウント。自動化に適しています
   - **TOKEN_MANAGER_ROLE**: トークン管理専用。慎重に操作してください
   - **EMERGENCY_ROLE**: 緊急時のみ使用。複数のsignerで管理推奨
3. **最小権限の原則**: 各アカウントには必要最小限の権限のみを付与してください
4. **ガス使用量**: バッチ配布時は大量のガスが必要になる場合があります
5. **テストネット**: 本番環境での使用前に必ずテストネットで動作確認を行ってください
6. **役割の移行**: 役割を変更する際は、慎重な手順を踏んでください

## サポート

- GitHub Issues: 問題報告や機能要求
- Documentation: 最新の仕様書とAPI参照
- Community: 開発者コミュニティでのサポート

---

このガイドにより、MultiTokenDistributionコントラクトを効率的に活用し、NewLoエコシステムでの多様なトークン配布を実現できます。 