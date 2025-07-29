# 双方向クロスチェーンスワップ検証スクリプト

このスクリプトは、Ethereum Sepolia と Sui testnet 間の双方向クロスチェーンスワップの動作を検証します。

## 機能

- **Ethereum -> Sui スワップ検証**: Sepolia から Sui への資産移動
- **Sui -> Ethereum スワップ検証**: Sui から Sepolia への資産移動
- **ハッシュロック機能**: セキュアな原子スワップの実装
- **タイムロック機能**: 期限切れ時の自動返金
- **部分フィル機能**: 大きなスワップの効率的な実行

## 前提条件

### 必要なソフトウェア
1. **Node.js** (v18以上)
   - [Node.js公式サイト](https://nodejs.org/)からダウンロード
   - インストール確認: `node --version`

2. **Git** (リポジトリのクローン用)
   - [Git公式サイト](https://git-scm.com/)からダウンロード
   - インストール確認: `git --version`

### 必要なアカウントとウォレット
1. **Sepolia テストネットウォレット**
   - MetaMaskなどのウォレットでSepoliaテストネットを追加
   - Sepolia ETHを取得: [Sepolia Faucet](https://sepoliafaucet.com/)

2. **Sui テストネットウォレット**
   - Sui Walletをインストール: [Sui Wallet](https://chrome.google.com/webstore/detail/sui-wallet/opcgpfmipidbgpenhmajoajpbobppdil)
   - Suiテストネットに切り替え
   - テストネットSUIを取得: [Sui Faucet](https://discord.gg/sui)

### 必要な環境変数設定
- `.env.local` ファイルに秘密鍵を設定（詳細は下記）

### コントラクトデプロイ
- Ethereum と Sui のエスクローコントラクトがデプロイ済みであること

## セットアップ

### 1. 依存関係のインストール

```bash
cd scripts
npm install
```

### 2. 環境変数の設定

`.env.local` ファイルを作成し、以下の変数を設定してください：

```env
# ユーザーウォレットの秘密鍵
VITE_SEPOLIA_USER_PRIVATE_KEY=0x...
VITE_SUI_USER_PRIVETE_KEY=base64_encoded_private_key

# Resolver ウォレットの秘密鍵
VITE_RESOLVER_PRIVATE_KEY=0x...

# コントラクトアドレス（デプロイ後に更新）
ETH_ESCROW_ADDRESS=0x...
SUI_ESCROW_PACKAGE_ID=0x...
SUI_USED_SECRETS_REGISTRY_ID=0x...
```

### 3. コントラクトアドレスの更新

`scripts/verify-bidirectional-swap.ts` ファイル内の以下の定数を実際のデプロイされたアドレスに更新してください：

```typescript
const ETH_ESCROW_ADDRESS = '0x...'; // 実際のEthereumエスクローアドレス
const SUI_ESCROW_PACKAGE_ID = '0x...'; // 実際のSuiパッケージID
const SUI_USED_SECRETS_REGISTRY_ID = '0x...'; // 実際のレジストリID
```

## 使用方法

### 1. 初回セットアップ

#### 1.1 ディレクトリに移動
```bash
cd scripts
```

#### 1.2 依存関係をインストール
```bash
npm install
```

#### 1.3 環境変数ファイルを作成
```bash
# .env.local ファイルを作成
touch .env.local
```

#### 1.4 環境変数を設定
`.env.local` ファイルを開いて、以下の内容を追加してください：

```env
# ユーザーウォレットの秘密鍵（必ず設定してください）
VITE_SEPOLIA_USER_PRIVATE_KEY=0x1234567890abcdef...
VITE_SUI_USER_PRIVETE_KEY=base64_encoded_private_key_here

# Resolver ウォレットの秘密鍵（必ず設定してください）
VITE_RESOLVER_PRIVATE_KEY=0xabcdef1234567890...
```

**注意**: 
- 秘密鍵は必ず `0x` で始まる形式で入力してください
- Sui の秘密鍵は base64 エンコードされた形式で入力してください
- これらの秘密鍵は安全に管理し、公開しないでください

### 2. スクリプトの実行

#### 2.1 基本的な実行（推奨）
```bash
npm run test
```

#### 2.2 開発モードでの実行
```bash
npm run dev
```

#### 2.3 直接実行（上級者向け）
```bash
npx tsx verify-bidirectional-swap.ts
```

### 3. 実行結果の確認

正常に実行されると、以下のようなログが表示されます：

```
🚀 双方向クロスチェーンスワップ検証開始
==================================================

📊 Ethereum -> Sui スワップ検証
------------------------------
🔍 Ethereum -> Sui スワップ検証開始...
📝 シークレット生成: 0x...
🔒 ハッシュロック生成: 0x...
⏰ タイムロック設定: 1234567890
📦 Ethereum エスクロー作成: 0x...
✅ Ethereum エスクロー フィル完了
📦 Sui エスクロー作成: 0x...
✅ Sui エスクロー フィル完了
✅ Ethereum -> Sui スワップ検証成功

📊 Sui -> Ethereum スワップ検証
------------------------------
🔍 Sui -> Ethereum スワップ検証開始...
...
✅ Sui -> Ethereum スワップ検証成功

🎉 双方向クロスチェーンスワップ検証完了
```

### 4. よくあるエラーと対処法

#### 4.1 環境変数エラー
```
Error: 必要な環境変数が設定されていません
```
**対処法**: `.env.local` ファイルが正しく設定されているか確認してください

#### 4.2 ネットワークエラー
```
Error: Failed to fetch
```
**対処法**: インターネット接続を確認し、RPC URLが正しいか確認してください

#### 4.3 ガス代不足エラー
```
Error: insufficient funds
```
**対処法**: ウォレットに十分なガス代があるか確認してください

### 5. テスト金額の確認

現在のテスト金額：
- **Ethereum -> Sui**: 0.00001 ETH（約 $0.00002）
- **Sui -> Ethereum**: 0.01 SUI（約 $0.01）

これらの金額は `verify-bidirectional-swap.ts` ファイル内で変更可能です。

## 検証フロー

### Ethereum -> Sui スワップ

1. **シークレット生成**: 32バイトのランダムシークレットを生成
2. **ハッシュロック作成**: シークレットからハッシュロックを生成
3. **Ethereum エスクロー作成**: Sepolia でエスクローを作成
4. **Resolver フィル**: Resolver がエスクローをフィル
5. **Sui エスクロー作成**: Sui で対応するエスクローを作成
6. **Sui エスクロー フィル**: シークレットを使用してSuiエスクローをフィル

### Sui -> Ethereum スワップ

1. **シークレット生成**: 32バイトのランダムシークレットを生成
2. **ハッシュロック作成**: シークレットからハッシュロックを生成
3. **Sui エスクロー作成**: Sui でエスクローを作成
4. **Sui エスクロー フィル**: シークレットを使用してSuiエスクローをフィル
5. **Ethereum エスクロー作成**: Sepolia で対応するエスクローを作成
6. **Resolver フィル**: Resolver がEthereumエスクローをフィル

## レート設定

現在のレート設定：
- **1 SUI = 0.001 ETH**
- **1 ETH = 1000 SUI**

テスト金額設定：
- **Ethereum -> Sui**: 0.00001 ETH
- **Sui -> Ethereum**: 0.01 SUI

これらのレートは `scripts/verify-bidirectional-swap.ts` 内で変更可能です：

```typescript
const ETH_TO_SUI_RATE = 0.001; // 1 SUI = 0.001 ETH
const SUI_TO_ETH_RATE = 1000; // 1 ETH = 1000 SUI

// テスト用の金額
const testEthAmount = parseEther('0.00001'); // 0.00001 ETH (eth->sui)
const testSuiAmount = BigInt(10000000); // 0.01 SUI (sui->eth) (1e7)
```

## エラーハンドリング

スクリプトは以下のエラーを適切に処理します：

- **環境変数不足**: 必要な秘密鍵が設定されていない場合
- **ネットワークエラー**: RPC接続の問題
- **コントラクトエラー**: トランザクション実行の失敗
- **バリデーションエラー**: 無効なパラメータ

## ログ出力

スクリプトは詳細なログを出力し、各ステップの進行状況を追跡できます：

```
🚀 双方向クロスチェーンスワップ検証開始
==================================================

📊 Ethereum -> Sui スワップ検証
------------------------------
🔍 Ethereum -> Sui スワップ検証開始...
📝 シークレット生成: 0x...
🔒 ハッシュロック生成: 0x...
⏰ タイムロック設定: 1234567890
📦 Ethereum エスクロー作成: 0x...
✅ Ethereum エスクロー フィル完了
📦 Sui エスクロー作成: 0x...
✅ Sui エスクロー フィル完了
✅ Ethereum -> Sui スワップ検証成功
```

## トラブルシューティング

### よくある問題と対処法

#### 1. 環境変数エラー
**症状**: `Error: 必要な環境変数が設定されていません`
**対処法**:
- `.env.local` ファイルが存在するか確認: `ls -la .env.local`
- ファイルの内容を確認: `cat .env.local`
- 秘密鍵が正しい形式か確認（0xで始まる）

#### 2. ネットワークエラー
**症状**: `Error: Failed to fetch` または `Network error`
**対処法**:
- インターネット接続を確認
- ファイアウォールの設定を確認
- VPNを使用している場合は一時的に無効化

#### 3. コントラクトエラー
**症状**: `Error: Contract not found` または `Transaction failed`
**対処法**:
- コントラクトが正しくデプロイされているか確認
- コントラクトアドレスが正しいか確認
- テストネットが正しく設定されているか確認

#### 4. ガス代不足
**症状**: `Error: insufficient funds` または `Out of gas`
**対処法**:
- Sepolia ETHの残高を確認: [Sepolia Etherscan](https://sepolia.etherscan.io/)
- Sui テストネットSUIの残高を確認
- 必要に応じてファウセットから取得

#### 5. 権限エラー
**症状**: `Error: Permission denied` または `Access denied`
**対処法**:
- ファイルの権限を確認: `ls -la`
- 必要に応じて権限を変更: `chmod 644 .env.local`

#### 6. Node.js バージョンエラー
**症状**: `Error: Unsupported Node.js version`
**対処法**:
- Node.js バージョンを確認: `node --version`
- 必要に応じて Node.js をアップデート

### デバッグモードでの実行

詳細なログを確認したい場合：

```bash
# デバッグ情報を表示
DEBUG=* npm run test

# または直接実行
DEBUG=* npx tsx verify-bidirectional-swap.ts
```

### ログファイルの確認

エラーが発生した場合、ログファイルを確認してください：

```bash
# ログファイルを作成して実行
npm run test > log.txt 2>&1

# ログファイルを確認
cat log.txt
```

## セキュリティ注意事項

- **秘密鍵の管理**: 秘密鍵は安全に管理し、公開リポジトリにコミットしないでください
- **テストネット使用**: 本番環境ではなく、テストネットでのみ実行してください
- **小額テスト**: 最初は小額でテストしてから、大きな金額でテストしてください

## ライセンス

MIT License 