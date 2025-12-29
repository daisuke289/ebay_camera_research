# eBay カメラリサーチツール

## プロジェクト概要

eBayのカメラ販売データを取得・分析し、売れ筋商品を特定するツール。
Google スプレッドシートに登録された約3000件のカメラ商品について、eBay APIで販売実績を取得し、売れ行き率（バランス）を算出する。

### 目的
- eBayでの売れ筋カメラを特定する
- 国内（ヤフオク、メルカリ、Yahoo!フリマ）での仕入れ判断に活用
- 出品数と落札数のバランスから需要を可視化

### 売れ行き率（バランス）の定義
```
バランス = 過去90日の落札数 ÷ 現在の出品数
```
- 2.0以上: 需要 > 供給（即仕入れ候補）
- 1.0〜2.0: 需要と供給が均衡（仕入れ検討）
- 0.5〜1.0: 供給がやや多い（様子見）
- 0.5未満: 供給過多（避ける）

---

## 技術スタック

- **言語**: Ruby 3.x
- **API**:
  - Google Sheets API v4（スプレッドシート読み書き）
  - eBay Browse API / Finding API（販売データ取得）
  - Exchange Rate API（為替レート取得）
- **開発環境**: VS Code + Claude Code

---

## ディレクトリ構成

```
ebay_camera_research/
├── CLAUDE.md                 # このファイル（プロジェクト設計）
├── Gemfile                   # 依存gem定義
├── Gemfile.lock
├── .env                      # 環境変数（API キー等）※gitignore対象
├── .env.example              # 環境変数サンプル
├── .gitignore
├── config/
│   └── google_credentials.json  # Google API認証ファイル ※gitignore対象
├── lib/
│   ├── google_sheets_client.rb  # Google Sheets API クライアント
│   ├── ebay_url_parser.rb       # eBay URL パラメータ解析
│   ├── ebay_api_client.rb       # eBay API クライアント
│   ├── exchange_rate_client.rb  # 為替レート取得
│   └── balance_calculator.rb    # バランス計算ロジック
├── bin/
│   ├── setup.rb                 # 初期セットアップ
│   ├── fetch_all.rb             # 全件取得（バッチ処理）
│   ├── fetch_batch.rb           # 指定範囲のみ取得
│   └── update_sheet.rb          # スプレッドシート更新
├── logs/                        # 実行ログ
│   └── .gitkeep
└── tmp/                         # 一時ファイル
    └── .gitkeep
```

---

## スプレッドシート構造

| 列 | ヘッダー | 内容 | 備考 |
|----|---------|------|------|
| A | No | 連番 | 読み取り専用 |
| B | カテゴリ | コンパクトカメラ、フィルムカメラ等 | 読み取り専用 |
| C | メーカー | CANON, NIKON, LEICA等 | 読み取り専用 |
| D | 商品名 | CANON AF35M等 | 読み取り専用 |
| E | ebay出品URL | 出品中商品の検索URL | 読み取り専用 |
| F | ebay落札URL | 販売済商品の検索URL | 読み取り専用 |
| G | 出品数 | 現在の出品数 | **← 書き込み対象** |
| H | 落札数 | 過去90日の落札数 | **← 書き込み対象** |
| I | バランス | 落札数÷出品数 | **← 書き込み対象** |
| J | 平均価格(USD) | 過去90日の平均落札価格 | **← 書き込み対象** |
| K | 平均価格(JPY) | JPY換算価格 | **← 書き込み対象** |
| L | 最低価格(USD) | 過去90日の最低落札価格 | **← 書き込み対象** |
| M | 最高価格(USD) | 過去90日の最高落札価格 | **← 書き込み対象** |
| N | 更新日時 | データ取得日時 | **← 書き込み対象** |

---

## eBay URL パラメータ

スプレッドシートのURLから抽出するパラメータ：

| パラメータ | 例 | 意味 |
|-----------|-----|------|
| `_nkw` | `canon af35m -ml -ii` | 検索キーワード（除外条件含む） |
| `_sacat` | `15230` | eBayカテゴリID |
| `LH_BIN` | `1` | Buy It Now のみ |
| `LH_PrefLoc` | `2` | 発送元フィルタ |
| `LH_ItemCondition` | `3000` | 商品状態（中古） |
| `LH_Sold` | `1` | 販売済みのみ（落札URL用） |
| `LH_Complete` | `1` | 終了済みのみ（落札URL用） |

---

## API制限と対策

### eBay API
- **制限**: 5,000 calls/day（Basic プラン）
- **対策**:
  - 1日あたり最大500件を処理
  - 全件（3000件）は約6-7日で完了
  - 高優先度商品（バランス上位）は頻繁に更新

### Google Sheets API
- **制限**: 300 requests/minute
- **対策**: バッチ更新で1回のリクエストにまとめる

### 為替レート API
- **制限**: 1,500 calls/month（無料プラン）
- **対策**: 1日1回のみ取得、キャッシュ利用

---

## 開発フェーズ

### Phase 1: プロジェクト基盤構築
- [ ] ディレクトリ構成作成
- [ ] Gemfile 作成（必要なgem定義）
- [ ] .env.example 作成
- [ ] .gitignore 作成

### Phase 2: Google Sheets API 連携
- [ ] Google Cloud Console でプロジェクト作成
- [ ] Sheets API 有効化
- [ ] サービスアカウント作成、認証ファイル取得
- [ ] GoogleSheetsClient クラス実装
- [ ] スプレッドシート読み込みテスト
- [ ] スプレッドシート書き込みテスト

### Phase 3: eBay URL 解析
- [ ] EbayUrlParser クラス実装
- [ ] 出品URL からパラメータ抽出
- [ ] 落札URL からパラメータ抽出
- [ ] テストケース作成

### Phase 4: eBay API 連携
- [ ] eBay Developer アカウント確認
- [ ] API キー取得（Production環境）
- [ ] EbayApiClient クラス実装
- [ ] 出品数取得メソッド実装
- [ ] 落札数取得メソッド実装（過去90日）
- [ ] API制限対応（レート制限、リトライ）

### Phase 5: 為替レート取得
- [ ] ExchangeRateClient クラス実装
- [ ] USD/JPY レート取得
- [ ] キャッシュ機能

### Phase 6: バランス計算・集計
- [ ] BalanceCalculator クラス実装
- [ ] スコア計算ロジック

### Phase 7: バッチ処理・実行スクリプト
- [ ] fetch_all.rb 実装（全件処理）
- [ ] fetch_batch.rb 実装（範囲指定処理）
- [ ] update_sheet.rb 実装（結果書き戻し）
- [ ] ログ出力機能

### Phase 8: 運用・改善
- [ ] エラーハンドリング強化
- [ ] 進捗表示
- [ ] 再開機能（中断からの継続）

---

## 環境変数（.env）

```env
# Google Sheets
GOOGLE_SPREADSHEET_ID=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
GOOGLE_CREDENTIALS_PATH=./config/google_credentials.json

# eBay API
EBAY_APP_ID=your_app_id
EBAY_CERT_ID=your_cert_id
EBAY_DEV_ID=your_dev_id
EBAY_OAUTH_TOKEN=your_oauth_token

# Exchange Rate API
EXCHANGE_RATE_API_KEY=your_api_key

# 処理設定
BATCH_SIZE=500
API_DELAY_SECONDS=1
```

---

## 使用方法

### 初回セットアップ
```bash
# 依存関係インストール
bundle install

# 環境変数設定
cp .env.example .env
# .env を編集してAPIキー等を設定

# Google認証ファイル配置
# config/google_credentials.json を配置
```

### データ取得
```bash
# 全件取得（API制限により数日かかる）
ruby bin/fetch.rb fetch_all

# 価格情報も一緒に取得
ruby bin/fetch.rb fetch_all --with-price

# バッチ単位で取得（1バッチ=500件）
ruby bin/fetch.rb fetch_batch 1    # 1-500件目
ruby bin/fetch.rb fetch_batch 2    # 501-1000件目

# 特定メーカーのみ
ruby bin/fetch.rb fetch_maker CANON

# バッチ取得 + 価格情報
ruby bin/fetch.rb fetch_batch 1 --with-price
```

### 価格分析
```bash
# キーワードで価格帯分析
ruby bin/fetch.rb analyze_price "canon eos 5d mark iii"

# スプレッドシートの特定行を分析
ruby bin/fetch.rb analyze_row 5

# 状態別の価格比較
ruby bin/fetch.rb price_comparison "nikon d850"
```

### 価格分析の出力例
```
======================================================================
📊 価格帯分析: canon eos 5d mark iii
======================================================================

📈 基本統計
   販売件数: 85件（過去90日）
   平均価格: $850.50 (¥133,528)
   中央値:   $825.00 (¥129,525)
   最低価格: $450
   最高価格: $1200
   標準偏差: $185.30

📊 パーセンタイル
   10%: $520  25%: $650  50%: $825  75%: $980  90%: $1100

📦 価格帯分布
   $400-599    ████████░░░░░░░░░░░░ 18件 (21.2%)
   $600-799    ████████████░░░░░░░░ 25件 (29.4%)
   $800-999    ████████████████░░░░ 32件 (37.6%)  ← ボリュームゾーン
   $1000-1199  ████░░░░░░░░░░░░░░░░ 10件 (11.8%)

🎯 分析結果
   ボリュームゾーン: $800-999（最も取引が多い価格帯）
   仕入れ推奨価格帯: $650-825 (下位25%〜中央値)

💡 仕入れ推奨
   目標仕入れ価格: $390 (¥61,230)
   想定販売価格:   $825 (¥129,525)
   想定利益率:     111.5%
   アドバイス:     価格が安定している。相場が読みやすい
======================================================================
```

### 結果確認
スプレッドシートの G〜N 列が更新される。
バランス列で降順ソートすれば売れ筋ランキング。
価格情報も取得した場合は J〜M 列に価格データが入る。

---

## 仕入れリサーチ用リンク生成

バランス上位の商品について、国内サイトの検索リンクを生成：

```
ヤフオク: https://auctions.yahoo.co.jp/search/search?p={検索キー}
メルカリ: https://jp.mercari.com/search?keyword={検索キー}
Yahoo!フリマ: https://paypayfleamarket.yahoo.co.jp/search/{検索キー}
```

※ 将来的にスプレッドシートに列追加、または別シートで出力

---

## 注意事項

- eBay API は本番環境（Production）のキーを使用すること
- API キーは絶対にGitにコミットしない
- 大量リクエスト時はAPI制限に注意（1秒間隔を空ける）
- スプレッドシートのURLは共有設定でサービスアカウントに編集権限を付与すること

---

## 参考リンク

- [eBay Developer Program](https://developer.ebay.com/)
- [eBay Browse API Documentation](https://developer.ebay.com/api-docs/buy/browse/overview.html)
- [Google Sheets API Documentation](https://developers.google.com/sheets/api)
- [Exchange Rates API](https://exchangeratesapi.io/)

---

## Workflow

あなたは、以下のステップを実行します。

### Step 1: タスク受付と準備
1. ユーザーから **GitHub Issue 番号**を受け付けたらフロー開始です。`/create-gh-branch` カスタムコマンドを実行し、Issueの取得とブランチを作成します。
2. Issueの内容を把握し、関連するコードを調査します。

### Step 2: 実装計画の策定と承認
1. 分析結果に基づき、実装計画を策定します。
2. 計画をユーザーに提示し、承認を得ます。**承認なしに次へ進んではいけません。**

### Step 3: 実装・レビュー・修正サイクル
1. 承認された計画に基づき、実装を行います。
2. 実装完了後、**あなた自身でコードのセルフレビューを行います。**
3. 実装内容とレビュー結果をユーザーに報告します。
4. **【ユーザー承認】**: 報告書を提示し、承認を求めます。
   - `yes`: コミットして完了。
   - `fix`: 指摘に基づき修正し、再度レビューからやり直す。

---

## カスタムコマンド

| コマンド | 説明 |
|---------|------|
| `/create-gh-branch <Issue番号>` | Issueからブランチ作成 |
| `/create-pr` | 現在のブランチからPR作成 |
| `/list-issues` | オープンなIssue一覧表示 |
