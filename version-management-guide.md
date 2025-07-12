# Version Management Best Practices Guide 2024

## 概要

このガイドでは、ソフトウェアプロジェクトのバージョン管理に関する最新のベストプラクティスをまとめています。プロジェクトの種類に応じた適切な手法を選択し、自動化ツールを活用して効率的な開発・リリースプロセスを構築するための実用的な情報を提供します。

## 🎯 主要なバージョン管理戦略

### 1. セマンティックバージョニング（SemVer）

**最も推奨される方法**

形式：`MAJOR.MINOR.PATCH`（例：`2.5.1`）

- **MAJOR**：互換性を破る変更
- **MINOR**：後方互換性を保った新機能追加
- **PATCH**：後方互換性を保ったバグ修正

**追加ラベル：**
- プレリリース：`1.0.0-alpha`、`2.0.0-beta.2`、`1.4.0-rc.1`
- ビルドメタデータ：`1.4.2+exp.sha.5114f85`

**適用例：**
```
1.0.0 → 初回リリース
1.0.1 → バグ修正
1.1.0 → 新機能追加
2.0.0 → 破壊的変更
```

### 2. カレンダーバージョニング（CalVer）

**時間基準のバージョニング**

形式：`YYYY.MM`（例：`2024.12`）または`YY.MM.PATCH`（例：`24.12.1`）

**使用例：**
- Ubuntu：`22.04`、`24.10`
- Android Studio：`2023.1`、`2024.1`

### 3. ハイブリッドアプローチ

**プロジェクトの特性に応じた組み合わせ**

例：Python（時間ベースのリリーススケジュール + セマンティック形式）
- `3.12.2`（年1回のマイナーバージョン、定期的なパッチ）

## 🔧 自動化ツールとワークフロー

### Git Tags を使用した自動バージョン管理

#### GitVersion（推奨）
```yaml
# GitVersion.yml
workflow: GitFlow
mode: ContinuousDeployment
branches:
  main:
    increment: Patch
  feature:
    increment: Minor
  hotfix:
    increment: Patch
```

#### GitHub Actions での自動化
```yaml
name: Version and Release
on:
  push:
    branches: [ main ]
    
jobs:
  version:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          fetch-depth: 0
      
      - name: Install GitVersion
        uses: gittools/actions/gitversion/setup@v0.9.7
        with:
          versionSpec: '5.x'
          
      - name: Determine Version
        uses: gittools/actions/gitversion/execute@v0.9.7
        
      - name: Create Release
        uses: actions/create-release@v1
        env:
          GITHUB_TOKEN: ${{ secrets.GITHUB_TOKEN }}
```

### コミットメッセージ規約による自動化

#### Conventional Commits
```
feat: 新機能追加      → MINOR バージョンアップ
fix: バグ修正        → PATCH バージョンアップ
BREAKING CHANGE: 破壊的変更 → MAJOR バージョンアップ
```

#### semantic-release の活用
```json
{
  "branches": ["main"],
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/npm",
    "@semantic-release/github"
  ]
}
```

## 📊 プロジェクトタイプ別推奨手法

### ライブラリ・SDK・API
**推奨：SemVer**
- 後方互換性の明確な伝達が重要
- 依存関係管理との相性が良い
- 例：npm パッケージ、Rust crates

### Web アプリケーション・SaaS
**推奨：CalVer または SemVer**
- 定期リリース：CalVer
- 機能ベースリリース：SemVer
- 例：`2024.12.1`（月次リリース）

### スマートコントラクト・ブロックチェーン
**推奨：SemVer + 環境別タグ**
```
v1.2.3-mainnet
v1.2.3-testnet
v1.2.4-rc.1
```

### 内部ツール・プロトタイプ
**推奨：シンプルな連番または CalVer**
- 複雑さを避けて迅速な開発を優先
- 例：`v1`、`v2`、`v3`

## 🚀 実装戦略

### 1. 単一の真実の源（Single Source of Truth）

**Python の場合：**
```python
# __version__.py
__version__ = "1.2.3"

# setup.py
from mypackage.__version__ import __version__
setup(version=__version__)
```

**Node.js の場合：**
```json
// package.json
{
  "version": "1.2.3"
}
```

### 2. 自動化スクリプトの例

**バージョンバンプスクリプト：**
```bash
#!/bin/bash
# bump-version.sh

VERSION_TYPE=${1:-patch}  # patch, minor, major
CURRENT_VERSION=$(git describe --tags --abbrev=0 2>/dev/null || echo "0.0.0")

# Strip the 'v' prefix if present
CURRENT_VERSION=${CURRENT_VERSION#v}

case $VERSION_TYPE in
  patch)
    NEW_VERSION=$(echo $CURRENT_VERSION | awk -F. '{printf "%d.%d.%d", $1, $2, $3+1}')
    ;;
  minor)
    NEW_VERSION=$(echo $CURRENT_VERSION | awk -F. '{printf "%d.%d.0", $1, $2+1}')
    ;;
  major)
    NEW_VERSION=$(echo $CURRENT_VERSION | awk -F. '{printf "%d.0.0", $1+1}')
    ;;
esac

echo "Bumping version from $CURRENT_VERSION to $NEW_VERSION"
git tag -a "v$NEW_VERSION" -m "Version $NEW_VERSION"
git push origin "v$NEW_VERSION"
```

### 3. CI/CD パイプラインとの統合

**バージョン検証：**
```yaml
- name: Validate Version Consistency
  run: |
    TAG_VERSION=${GITHUB_REF#refs/tags/v}
    PACKAGE_VERSION=$(node -p "require('./package.json').version")
    
    if [ "$TAG_VERSION" != "$PACKAGE_VERSION" ]; then
      echo "Version mismatch!"
      exit 1
    fi
```

## 🏗️ 環境別デプロイメント戦略

### 環境の階層
1. **DEV**：開発環境
2. **QA**：品質保証環境
3. **STAGE**：ステージング環境
4. **PROD**：本番環境

### リリースブランチ戦略
```
main ← feature/bug branches
├── release/2024.12 ← QA環境
├── hotfix/2024.12.1 ← 緊急修正
└── tags/v2024.12.1 ← 本番リリース
```

## 📝 ベストプラクティス

### ✅ 推奨事項
1. **一貫性を保つ**：選択したスキームに従う
2. **早期かつ頻繁にバージョンアップ**：小さな変更でも記録
3. **自動化を活用**：手動エラーを防ぐ
4. **文書化を怠らない**：CHANGELOG.md の維持
5. **プレリリースタグの適切な使用**：`-alpha`、`-beta`、`-rc`

### ❌ 避けるべき事項
1. **複数箇所でのバージョン定義**：真実の源を一つに
2. **バージョンの再利用**：一度付けた番号は変更しない
3. **過度なメジャーバージョンアップ**：必要な時のみ
4. **バージョン管理の無視**：すべてのリリースにバージョンを付ける

## 🛠️ 推奨ツール

### バージョン管理ツール
- **GitVersion**：Git ベースの自動バージョニング
- **semantic-release**：コミットメッセージベースの自動化
- **bump-my-version**：手動バージョンバンプ
- **changesets**：モノレポ対応

### CI/CD 統合
- **GitHub Actions**
- **GitLab CI**
- **Azure DevOps**
- **Jenkins**

## 🔍 プロジェクト固有の考慮事項

### あなたのプロジェクト（Foundry/Smart Contract）向け推奨事項

1. **SemVer の採用**：コントラクト API の互換性管理
2. **環境別タグ**：`v1.2.3-mainnet`、`v1.2.3-testnet`
3. **セキュリティ重視**：パッチバージョンでのセキュリティ修正
4. **監査トレーサビリティ**：各バージョンの変更内容の明確な記録

### 実装例：
```toml
# foundry.toml
[profile.default]
# ... 既存の設定

[doc]
title = "MyContract"
version = "1.2.3"  # GitVersion で自動更新
```

## 📋 チェックリスト

### リリース前の確認項目
- [ ] バージョン番号が一意である
- [ ] CHANGELOG.md が更新されている
- [ ] 全テストが通過している
- [ ] ドキュメントが更新されている
- [ ] 破壊的変更が適切に文書化されている
- [ ] セキュリティ監査が完了している（該当する場合）

### 自動化の確認項目
- [ ] CI/CD パイプラインでのバージョン検証
- [ ] 自動タグ生成の設定
- [ ] リリースノートの自動生成
- [ ] 依存関係の自動更新チェック

## 📚 参考資料

- [Semantic Versioning 2.0.0](https://semver.org/)
- [Calendar Versioning](https://calver.org/)
- [GitVersion Documentation](https://gitversion.net/)
- [Conventional Commits](https://www.conventionalcommits.org/)
- [Keep a Changelog](https://keepachangelog.com/)

---

**結論：**
適切なバージョン管理戦略は、プロジェクトの性質、チームの規模、リリース頻度に依存します。スマートコントラクトプロジェクトの場合、SemVer + 自動化ツールの組み合わせが最も効果的です。まずは小さく始めて、プロジェクトの成長に合わせて段階的に改善していくことをお勧めします。