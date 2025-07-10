# MultiTokenDistribution Guide

## 概要

MultiTokenDistributionコントラクトは、NewLoエコシステムにおいて複数のERC20トークン（WETH、USDC、USDT等）を効率的に配布するためのコントラクトです。

## 主な機能

### 🎯 **多様なトークンサポート**
- WETH (Wrapped Ether)
- USDC (USD Coin)
- USDT (Tether USD)
- wstETH (Wrapped Staked ETH)
- stETH (Staked ETH)
- ASTR (Astar Token)
- その他のERC20トークン

### 🔧 **管理機能**
- トークンの追加・削除
- トークンの有効/無効切り替え
- 緊急時の一時停止機能
- バッチ配布機能

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

### 1. トークンの追加
```solidity
// 新しいトークンを追加
distribution.addToken("WETH", 0x4200000000000000000000000000000000000006, 18);
```

### 2. 単一ユーザーへの配布
```solidity
// 1 ETH分のWETHを配布
distribution.distributeToken("WETH", userAddress, 1 ether);

// 1000 USDCを配布
distribution.distributeToken("USDC", userAddress, 1000 * 10**6);
```

### 3. バッチ配布
```solidity
address[] memory users = [user1, user2, user3];
uint256[] memory amounts = [1 ether, 2 ether, 3 ether];

// 複数ユーザーに一括配布
distribution.batchDistributeToken("WETH", users, amounts);
```

### 4. 配布履歴の確認
```solidity
// ユーザーの全配布履歴を取得
DistributionRecord[] memory history = distribution.getUserDistributionHistory(userAddress);

// 特定トークンの配布履歴を取得
DistributionRecord[] memory wethHistory = distribution.getUserTokenHistory(userAddress, "WETH");
```

### 5. 統計情報の取得
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

### トークンの有効/無効切り替え
```solidity
// トークンを無効化
distribution.setTokenStatus("WETH", false);

// トークンを有効化
distribution.setTokenStatus("WETH", true);
```

### 緊急時の機能
```solidity
// コントラクトを一時停止
distribution.pause();

// 一時停止を解除
distribution.unpause();

// 緊急時のトークン引き出し
distribution.emergencyWithdraw("WETH", adminAddress, 10 ether);

// 全トークンを引き出し（amount=0で全額）
distribution.emergencyWithdraw("WETH", adminAddress, 0);
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

### 1. **アクセス制御**
- Owner権限による管理機能の制限
- 配布はOwnerのみが実行可能

### 2. **再帰攻撃対策**
- ReentrancyGuardによる保護
- CEI（Checks-Effects-Interactions）パターンの実装

### 3. **緊急時対応**
- Pausable機能による緊急停止
- 緊急時のトークン引き出し機能

### 4. **入力検証**
- 包括的な入力パラメータの検証
- カスタムエラーによる明確なエラーメッセージ

### 5. **安全なトークン操作**
- SafeERC20による安全なトークン転送
- 残高チェックによるオーバーフロー防止

## 実装の利点

### 1. **効率性**
- 標準的なERC20インターフェースを使用
- 追加のwrap処理が不要
- ガス効率の良い実装

### 2. **拡張性**
- 新しいトークンの簡単な追加
- 設定可能なトークン状態管理
- 将来的な機能拡張に対応

### 3. **運用性**
- 包括的な統計情報
- 詳細な配布履歴
- バッチ処理による効率的な操作

### 4. **安全性**
- 業界標準のセキュリティパターン
- 包括的なテストカバレッジ
- 緊急時対応機能

## 使用例

### 基本的な配布フロー
```solidity
// 1. トークンを追加
distribution.addToken("WETH", 0x4200000000000000000000000000000000000006, 18);

// 2. コントラクトにトークンを送金
IERC20(wethAddress).transfer(distributionAddress, 100 ether);

// 3. ユーザーに配布
distribution.distributeToken("WETH", user1, 1 ether);
distribution.distributeToken("WETH", user2, 2 ether);

// 4. 結果確認
uint256 user1Balance = distribution.userReceivedAmounts(user1, "WETH");
// user1Balance = 1 ether
```

### バッチ配布の例
```solidity
// 大量のユーザーに効率的に配布
address[] memory users = new address[](100);
uint256[] memory amounts = new uint256[](100);

// ユーザーと金額を設定
for (uint256 i = 0; i < 100; i++) {
    users[i] = userAddresses[i];
    amounts[i] = 1 ether; // 各ユーザーに1 ETH相当
}

// 一括配布実行
distribution.batchDistributeToken("WETH", users, amounts);
```

## 注意事項

1. **トークンの事前準備**: 配布前にコントラクトに十分なトークンを送金してください
2. **権限管理**: Owner権限の適切な管理が重要です
3. **ガス使用量**: バッチ配布時は大量のガスが必要になる場合があります
4. **テストネット**: 本番環境での使用前に必ずテストネットで動作確認を行ってください

## サポート

- GitHub Issues: 問題報告や機能要求
- Documentation: 最新の仕様書とAPI参照
- Community: 開発者コミュニティでのサポート

---

このガイドにより、MultiTokenDistributionコントラクトを効率的に活用し、NewLoエコシステムでの多様なトークン配布を実現できます。 