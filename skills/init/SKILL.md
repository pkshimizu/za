---
name: init
description: >-
  za プラグインの各スキル（plan / issue / fix-issue / pr / review）が参照するドキュメントを
  プロジェクトの docs/ 配下に用意する初期化スキル。docs/CONTEXT.md・docs/PLAN.md・
  docs/ISSUE.md・docs/PR.md の 4 つを作成する。CONTEXT.md はリポジトリを調査して中身を
  埋め、PLAN/ISSUE/PR はルールのひな形を配置する。ユーザーが「za を使えるようにして」
  「za の初期設定をして」「docs を用意して」「このプロジェクトを za 対応にして」などと
  言ったとき、または /za:init を実行したときに使う。za の他スキルを使い始める前の準備として
  積極的に使う。
---

# za:init — za 用ドキュメントの初期化

`za` の各スキルは、プロジェクト固有のルールを `docs/` 配下のドキュメントから読み取って動く。
このスキルはそれらを一括で用意し、プロジェクトを `za` で回せる状態にする。

作成するのは次の 4 つ:

- `docs/CONTEXT.md` — プロジェクトの文脈・用語（`za:plan` が読む）
- `docs/PLAN.md` — プラン作成のルール（`za:plan` が読む）
- `docs/ISSUE.md` — issue 作成ルール＋コミット規約（`za:issue` / `za:fix-issue` / `za:review` が読む）
- `docs/PR.md` — PR 作成のルール（`za:pr` が読む）

ひな形は**このスキルの `assets/` 配下**にある。それを土台に、プロジェクトへ合わせて配置する。

## 手順

### 1. プロジェクトと既存ファイルを確認する

- カレントがプロジェクトのルートか確認する（リポジトリ直下で実行する想定）。
- `docs/` と上記 4 ファイルの有無を確認する。

### 2. 既存ファイルは保護する

すでに存在するファイルは**上書きしない**。ユーザーが手を入れている可能性があるため、
勝手に壊さない。

- 既存のものはスキップし、その旨を報告する。
- ユーザーが「作り直して」と明示した場合のみ、上書きする。

### 3. CONTEXT.md を生成する

CONTEXT.md は中身が肝なので、空テンプレートを置くだけにしない。**リポジトリを調査して
実際の内容で埋める**。

- 調査対象: README、主要ディレクトリ構成、ビルド/依存設定（`Cargo.toml` / `package.json` /
  `pyproject.toml` 等）、エントリポイント。そこから言語・スタック・形態・実行方法・主要な
  構成を読み取る。
- `assets/CONTEXT.template.md` を骨格として使い、各節を埋める。
- **Language（用語）**: そのプロジェクト固有の語を 2〜3 語見つけて定義する。一般的な
  プログラミング用語は載せない。適切な語が見つからなければ節ごと省いてよい。
- すでに `grill-with-docs` などで CONTEXT.md の書式が定まっている形跡があれば、それを尊重する。

### 4. PLAN.md / ISSUE.md / PR.md を配置する

`assets/PLAN.md` / `assets/ISSUE.md` / `assets/PR.md` を読み、`docs/` 配下へ作成する。
これらは `za` の各スキルが期待する書式に対応したルールのひな形。

- **PR.md の「確認事項」**は、プロジェクトの実際のビルド/テストコマンドに合わせて具体化する
  （例: Rust なら `cargo build` / `cargo clippy` / `cargo test`、Node なら `npm run build` /
  `npm test` 等）。ステップ3の調査結果から判断する。
- 他の箇所は基本そのままでよいが、プロジェクトの実情と明らかに異なる記述があれば調整する。

### 5. 完了報告

作成したファイル・スキップしたファイルを一覧で報告する。続けて、`za` の典型フロー
（`/za:plan` → `/za:issue` → `/za:fix-issue` → `/za:pr` → `/za:review`）を案内し、まずは
`/za:plan` から始められることを伝える。

## 補足

- `za:fix-issue` が読む `docs/rules/` や、`za:review` が読む `docs/review-perspectives/` は
  このスキルの対象外。`docs/rules/` は `za:review` が運用の中で育て、`docs/plans/` は
  `za:plan` が必要時に作る。必要なら別途用意すればよい。
