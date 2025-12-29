---
name: create-pr
description: 現在のブランチからPull Requestを作成
---

# 概要

現在のブランチの変更内容からPull Requestを作成する。

# 前提条件

- GitHub MCPがインストールされ、利用可能な状態であること
- リポジトリ: daisuke289/ebay_camera_research
- mainブランチ以外にいること
- リモートにプッシュ済みであること

# 処理フロー

1. **現在のブランチ名を取得**: `git branch --show-current` で現在のブランチ名を取得
2. **mainブランチでないことを確認**: mainブランチの場合はエラーを通知
3. **Issue番号の抽出**: ブランチ名が `feature/issue-X-...` 形式の場合、Issue番号を抽出
4. **コミット履歴の取得**: `git log main..HEAD --oneline` でコミット一覧を取得
5. **PRタイトル・本文の生成**:
   - タイトル: 最新コミットメッセージまたはブランチ名から生成
   - 本文: 変更概要（コミット履歴から自動生成）
6. **PR作成**: GitHub MCPの `create_pull_request` でPR作成
7. **Issue番号がある場合**: 本文に `Closes #X` を含める

# PRテンプレート

```
## Summary
- 変更概要（コミット履歴から自動生成）

## Related Issue
Closes #X（Issue番号がある場合）

---
Generated with Claude Code
```

# エラーハンドリング

- mainブランチにいる場合、処理を中断しエラー通知
- リモートにプッシュされていない場合、プッシュを促すメッセージを表示
