# 自動運転（オーケストレーション）の設定

`/za:auto` がこのファイルを読んで動く。プロジェクト固有の値はすべてここに置き、
スキル本体には持たせない。**値を変えるときはこのファイルだけを直す。** 項目はすべて必須
（欠けていると `/za:auto` は何もせずに止まる）。

## ボード

| 項目 | 値 |
|---|---|
| owner | `{GitHub のユーザー名または org}` |
| project | `{プロジェクト番号。`gh project list --owner <owner>` で確認}` |

## Status の値

ボードの `Status` フィールドの選択肢名を、**ボード側の表記そのまま**（空白・大文字を含めて）書く。

| 役割 | 値 |
|---|---|
| backlog | `Backlog` |
| ready | `Ready` |
| in_progress | `In progress` |
| in_review | `In review` |
| done | `Done` |

## ラベル

リポジトリに実在するラベル名を書く（`gh label list` で確認）。

| 役割 | ラベル名 | 意味 |
|---|---|---|
| needs_decision | `要判断` | 人間が決めるまで着手できない。`/za:auto` は拾わない |
| needs_manual_check | `要実機確認` | 実装は自動でできるが、マージ前に人間が実機で確かめる。`In review` で止める |

## 依存の書式

issue 本文の `## 依存` 節に、**行頭 `- blocked by:` で 1 行 1 依存**を書く。`/za:auto` は
この形の行だけを機械的に読む（他の書き方は依存として扱われず、警告として報告される）。

- 同じリポジトリ: `- blocked by: #123`
- 他のリポジトリ: `- blocked by: owner/repo#123`
- 依存なし: `- なし（すぐ着手可）`

行の末尾に補足（`（〜が決まってから）` など）を付けてよい。解決済みを示す取り消し線
（`~~blocked by: #123~~`）は依存として読まない。

## 上限と停止

| 項目 | 値 | 意味 |
|---|---|---|
| max_per_run | `1` | 1 回の起動で処理する issue の上限。慣らし運転が済んでから増やす |
| max_failures | `2` | 同じ issue の失敗がこの回数に達したら、その issue に `needs_decision` を付けて `Backlog` に落とし、この起動を止める |
| ci_timeout_minutes | `20` | CI の完了をこの時間まで待つ。超えたら `In review` のまま次の起動で再判定する |
| max_leftover_issues | `2` | 1 件のマージあたりに積み残しから作る issue の上限 |

## ゲート（変更不可の前提）

次は設定で緩められない。`/za:auto` の側で固定している。

- **CI は必須。** `.github/workflows/` にワークフローが無いリポジトリでは起動しない
- マージは「CI がすべて通過」「レビューが収束」「`needs_manual_check` が無い」のときだけ
- PR の差分が `docs/ORCHESTRATION.md` / `docs/MERGE.md` / `.github/workflows/**` に触れていたら、
  `needs_manual_check` と同じ扱い（`In review` で止める）

マージ方法・base・head ブランチの扱いは `docs/MERGE.md` に従う（ここには書かない）。

## 人間が見る場所

- `needs_decision` の issue: ボードの `Backlog` をラベルで絞る
- `needs_manual_check` の PR: ボードの `In review`
- 失敗の記録: `/za:auto` が issue に残すコメント（`za:auto:` で始まる）

## 自動運転を止めたいとき

`/loop` で回している場合はそのループを止める（`/za:auto` は自分でループを止められない）。
実行中の 1 件は途中で止めず、その件の報告まで待ってから止める。途中で止めてしまった場合も、
次の起動時に `/za:auto` がボードと実態を突き合わせて直すが、ローカルが作業ブランチに残って
いれば手で `main` に戻す必要がある。
