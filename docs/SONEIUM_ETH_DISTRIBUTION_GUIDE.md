# SoneiumETHDistribution: 超効率的ETH配布システム

## 📋 概要

SoneiumETHDistributionは、Soneiumネットワーク上でETHを大量の人に効率的に配布するためのスマートコントラクトです。TokenDistributionV2を参考に設計され、ネイティブETHの配布に特化しています。

## 🚀 主要な特徴

- **ネイティブETH配布** - ERC20トークンではなく、直接ETHを配布
- **大規模配布対応** - 最大500ユーザーまで一括配布可能
- **セキュリティ重視** - ロールベースアクセス制御、リエントランシー保護
- **運用管理機能** - 残高監視、統計追跡、重複防止
- **緊急時対応** - 一時停止機能、緊急引き出し機能

## 🏗️ システム構成

```
SoneiumETHDistribution
├── AccessControl          # ロールベースアクセス制御
├── ReentrancyGuard       # リエントランシー攻撃防止
├── Pausable              # 緊急停止機能
├── 配布機能              # バルク配布機能
├── 統計・監視機能        # 配布状況追跡
└── 管理機能              # 緊急時対応
```

## 👥 ロール管理

### 利用可能なロール

| ロール | 説明 | 権限 |
|--------|------|------|
| `DEFAULT_ADMIN_ROLE` | 管理者 | 全ての権限、ロール管理 |
| `DISTRIBUTOR_ROLE` | 配布者 | ETH配布実行 |
| `DEPOSIT_MANAGER_ROLE` | 入金管理者 | ETH入金・緊急引き出し |
| `PAUSER_ROLE` | 停止権限者 | コントラクト一時停止 |

## 🔧 セットアップ手順

### Step 1: コントラクトデプロイ

```bash
# 環境変数設定
export PRIVATE_KEY="your_private_key"
export RPC_URL="https://rpc.soneium.org"

# デプロイ実行
forge script script/DeploySoneiumETHDistribution.s.sol --rpc-url $RPC_URL --broadcast --verify
```

### Step 2: ETHの入金

```solidity
// 方法1: depositETH関数を使用
contract.depositETH{value: 100 ether}();

// 方法2: 直接送金（receive関数で受信）
(bool success, ) = contractAddress.call{value: 100 ether}("");
```

### Step 3: ロール設定

```solidity
// 配布者ロールを付与
distribution.grantRole(distribution.DISTRIBUTOR_ROLE(), distributorAddress);

// 入金管理者ロールを付与
distribution.grantRole(distribution.DEPOSIT_MANAGER_ROLE(), depositManagerAddress);

// 停止権限者ロールを付与
distribution.grantRole(distribution.PAUSER_ROLE(), pauserAddress);
```

## 💰 配布方法

### 1. 均等配布

全員に同じ金額を配布する場合：

```solidity
address[] memory recipients = [
    0x1234567890123456789012345678901234567890,
    0x2345678901234567890123456789012345678901,
    0x3456789012345678901234567890123456789012
];

uint256 amount = 1 ether; // 1 ETH per person

// 配布実行
uint batchId = distribution.distributeEqual(recipients, amount);
```

### 2. 変動配布

異なる金額を配布する場合：

```solidity
address[] memory recipients = [
    0x1234567890123456789012345678901234567890,
    0x2345678901234567890123456789012345678901,
    0x3456789012345678901234567890123456789012
];

uint256[] memory amounts = [
    1 ether,   // 1 ETH
    2 ether,   // 2 ETH
    0.5 ether  // 0.5 ETH
];

// 配布実行
uint batchId = distribution.distributeVariable(recipients, amounts);
```

## 📊 統計・監視機能

### 配布統計の取得

```solidity
(
    uint totalDistributed,      // 総配布量
    uint totalDistributions,    // 総配布回数
    uint todayDistributed,      // 今日の配布量
    uint contractBalance,       // 現在残高
    bool isLowBalance,         // 残高警告
    bool isAntiDuplicateEnabled // 重複防止モード
) = distribution.getDistributionStats();
```

### ユーザー情報の取得

```solidity
(
    uint totalReceived,     // 総受取額
    uint lastReceived,      // 最後の受取時刻
    bool canReceiveToday    // 今日受取可能か
) = distribution.getUserDistributionInfo(userAddress);
```

### 残高チェック

```solidity
(uint balance, bool isLowBalance) = distribution.getContractBalance();

// 最大配布可能ユーザー数
uint maxUsers = distribution.getMaxDistributableUsers(1 ether);
```

## 🛡️ セキュリティ機能

### 重複配布防止

```solidity
// 重複配布防止モードを有効化（24時間以内の重複を防止）
distribution.setAntiDuplicateMode(true);

// 無効化
distribution.setAntiDuplicateMode(false);
```

### 緊急時対応

```solidity
// 緊急一時停止
distribution.pause();

// 再開
distribution.unpause();

// 緊急引き出し
distribution.emergencyWithdraw(0, adminAddress); // 全額引き出し
distribution.emergencyWithdraw(10 ether, adminAddress); // 指定額引き出し
```

## 📝 実装例

### 日次報酬配布システム

```solidity
contract DailyRewardDistribution {
    SoneiumETHDistribution public immutable distribution;
    mapping(uint => bool) public dailyDistributionCompleted;
    
    constructor(address _distribution) {
        distribution = SoneiumETHDistribution(_distribution);
    }
    
    function distributeDailyRewards(
        address[] calldata users, 
        uint rewardAmount
    ) external onlyOwner {
        uint today = block.timestamp / 86400;
        require(!dailyDistributionCompleted[today], "Already distributed today");
        
        // 重複防止モードを有効化
        distribution.setAntiDuplicateMode(true);
        
        // 日次報酬を配布
        distribution.distributeEqual(users, rewardAmount);
        
        dailyDistributionCompleted[today] = true;
    }
}
```

### イベント報酬配布システム

```solidity
contract EventRewardDistribution {
    SoneiumETHDistribution public immutable distribution;
    
    struct Prize {
        address winner;
        uint amount;
        string eventName;
    }
    
    function distributeEventRewards(Prize[] calldata prizes) external onlyOwner {
        address[] memory winners = new address[](prizes.length);
        uint[] memory amounts = new uint[](prizes.length);
        
        for (uint i = 0; i < prizes.length; i++) {
            winners[i] = prizes[i].winner;
            amounts[i] = prizes[i].amount;
        }
        
        distribution.distributeVariable(winners, amounts);
    }
}
```

## 🔄 運用フロー

### 1. 初期セットアップ

```bash
# 1. コントラクトをデプロイ
forge script script/DeploySoneiumETHDistribution.s.sol --rpc-url $RPC_URL --broadcast

# 2. コントラクトに大量のETHを入金
cast send $CONTRACT_ADDRESS --value 1000ether --private-key $PRIVATE_KEY

# 3. 適切な権限を各アドレスに付与
cast send $CONTRACT_ADDRESS "grantRole(bytes32,address)" $DISTRIBUTOR_ROLE $DISTRIBUTOR_ADDRESS --private-key $PRIVATE_KEY
```

### 2. 日常運用

```solidity
// 配布リストの準備
address[] memory dailyUsers = getUsersForToday();
uint dailyReward = 0.1 ether;

// 配布実行
distribution.distributeEqual(dailyUsers, dailyReward);

// 統計確認
(uint totalDistributed, , , uint balance, bool isLowBalance,) = distribution.getDistributionStats();

// 残高が少ない場合は補充
if (isLowBalance) {
    // 管理者に通知して補充を依頼
    notifyLowBalance(balance);
}
```

### 3. 監視・メンテナンス

```solidity
// 定期的な残高チェック
function checkContractHealth() external view returns (string memory) {
    (uint balance, bool isLowBalance) = distribution.getContractBalance();
    
    if (isLowBalance) {
        return "WARNING: Low balance detected";
    }
    
    return "OK: Sufficient balance";
}

// 配布履歴の確認
function getDailyReport() external view returns (uint) {
    uint today = block.timestamp / 86400;
    return distribution.getDailyDistribution(today * 86400);
}
```

## ⚠️ 注意事項

### セキュリティ

1. **プライベートキーの管理**: デプロイ・運用時のプライベートキーは厳重に管理
2. **ロール管理**: 必要最小限の権限のみ付与
3. **定期的な監査**: 大量の資金を扱うため、定期的なセキュリティ監査を実施

### 運用

1. **残高監視**: 定期的な残高チェックとアラート設定
2. **ガス価格**: 大量配布時のガス使用量を考慮
3. **受取者リスト**: 重複チェックとアドレス検証

### 技術的制約

1. **バッチサイズ**: 最大500ユーザーまで（ガス制限）
2. **重複防止**: 24時間以内の重複配布防止
3. **残高不足**: 配布前の残高確認が必要

## 📈 ガス使用量の目安

| 操作 | 推定ガス使用量 |
|------|---------------|
| 1ユーザーへの配布 | 約30,000 gas |
| 10ユーザーへの配布 | 約200,000 gas |
| 100ユーザーへの配布 | 約1,500,000 gas |
| 500ユーザーへの配布 | 約6,500,000 gas |

## 🎯 使用例

### 1. エアドロップキャンペーン

```solidity
// 1000人に0.1 ETHずつ配布
address[] memory airdropRecipients = getAirdropList();
distribution.distributeEqual(airdropRecipients, 0.1 ether);
```

### 2. ゲーム報酬配布

```solidity
// ゲームの成績に応じて異なる報酬を配布
address[] memory players = getTopPlayers();
uint[] memory rewards = calculateRewards(players);
distribution.distributeVariable(players, rewards);
```

### 3. DeFiプロトコルの収益分配

```solidity
// ステーキング量に応じて収益を分配
address[] memory stakers = getStakers();
uint[] memory earnings = calculateEarnings(stakers);
distribution.distributeVariable(stakers, earnings);
```

## 🔍 トラブルシューティング

### よくある問題と解決方法

1. **配布が失敗する**
   - コントラクトの残高を確認
   - ロール権限を確認
   - 重複配布設定を確認

2. **ガス不足エラー**
   - バッチサイズを小さくする
   - ガス制限を調整

3. **権限エラー**
   - 適切なロールが付与されているか確認

## 📞 サポート

技術的な問題やご質問がございましたら、NewLoチームまでお気軽にお問い合わせください。

---

**SoneiumETHDistribution v1.0**  
**Created by NewLo Team**  
**License: MIT** 