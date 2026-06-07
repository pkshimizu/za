# za

開発支援のための Claude Code プラグイン。

## 収録スキル

- **`/za:plan`** — 開発要件を確認し、プロジェクトのコンテキスト（`docs/CONTEXT.md`）と
  既存コードを踏まえた実装プランを `docs/plans/{yyyymmdd}-{title}.md` に作成する。
  不明点はまずコード調査で解消し、残ったものだけをユーザーに質問する。

## インストール（他マシン向け）

このリポジトリはプラグイン本体であると同時に marketplace を兼ねている。

```sh
claude plugin marketplace add pkshimizu/za
claude plugin install za@za
```

## ローカル開発

`~/.claude/skills/za/` に置くと `za@skills-dir` として自動ロードされ、編集が即反映される。
変更後は `/reload-plugins` で再読み込みする。
