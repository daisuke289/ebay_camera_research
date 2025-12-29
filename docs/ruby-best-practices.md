# Ruby コーディング規約 (レビュー基準)

## S-01: コード構成 (Structure)
- **単一責任の原則**: 1クラス1責務、1メソッド1機能を守ること。
- **ファイル構成**: 1ファイルに1クラスを定義すること。
- **frozen_string_literal**: 全ファイルの先頭に `# frozen_string_literal: true` を付与すること。

## N-01: 命名規則 (Naming)
- **ファイル名**: スネークケース（`ebay_api_client.rb`）
- **クラス名**: パスカルケース（`EbayApiClient`）
- **メソッド名**: スネークケース（`get_active_listing_count`）
- **定数**: 大文字スネークケース（`DEFAULT_TIMEOUT`）

## P-01: パフォーマンス (Performance)
- **不要なループの回避**: 同じ処理を複数回実行していないか確認すること。
- **メモリ効率**: 大量データ処理時は `each` より `find_each` や `lazy` を検討すること。
- **API呼び出しの最適化**: バッチ処理やキャッシュを活用し、不要なAPI呼び出しを削減すること。

## E-01: エラーハンドリング (Error Handling)
- **適切な例外クラス**: `StandardError` を継承したカスタム例外、または適切な組み込み例外を使用すること。
- **rescue節でのロギング**: エラー発生時は必ずログを出力すること。
- **デフォルト値の返却**: 必要に応じて安全なデフォルト値を返すこと。

```ruby
def some_method
  # 処理
rescue StandardError => e
  logger.error("Failed: #{e.message}")
  default_value
end
```

## C-01: セキュリティ (Security)
- **環境変数からの機密情報取得**: APIキー、パスワード等は必ず `ENV` から取得すること。
- **外部入力のバリデーション**: ユーザー入力やAPI応答は必ず検証すること。
- **APIキーのハードコード禁止**: ソースコードに機密情報を直接記述しないこと。

## T-01: テスト (RSpec)
- **振る舞いをテスト**: 実装の詳細ではなく、期待される振る舞いをテストすること。
- **明確なテスト名**: テスト名から何をテストしているか明確にわかること。
- **モック/スタブの適切な使用**: 外部依存（API、ファイルI/O等）は適切にモック化すること。

## D-01: ドキュメント (Documentation)
- **YARD形式**: メソッドのドキュメントはYARD形式を使用すること。
- **日本語コメント**: コメントは日本語で記述すること。
- **キーワード引数**: 必須パラメータはキーワード引数で明示すること。

```ruby
# メソッドの説明
#
# @param keyword [String] 検索キーワード
# @param category_id [String] カテゴリID
# @return [Integer] 出品数
def get_active_listing_count(keyword:, category_id: nil)
end
```
