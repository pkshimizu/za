# 自動運転（オーケストレーション）の設定

`za:auto` がこのファイルを読んで動く。プロジェクト固有の値はすべてここに置き、スキル本体には
持たせない。**値を変えるときはこのファイルだけを直す。** 「任意」と書いた項目以外は必須で、
欠けていると `za:auto` は何もせずに止まる。

各表の値は例。自分のプロジェクトの表記に置き換える。

## ボード

| 項目 | 値 |
|---|---|
| owner | `{GitHub のユーザー名または org}` |
| project | `{プロジェクト番号}` |
| priority_field | `Priority`（任意。無ければ並び順にボードの手動順だけを使う） |

プロジェクト番号は `gh project list --owner <owner>` で確認する。

## Status の値

ボードの `Status` フィールドの選択肢名を、**ボード側の表記そのまま**（空白・大文字を含めて）書く。
`za:auto` の手順書に出てくる `Ready` などは、この表の役割名を指す。

| 役割 | 値 |
|---|---|
| backlog | `Backlog` |
| ready | `Ready` |
| in_progress | `In progress` |
| in_review | `In review` |
| done | `Done` |

## ラベル

リポジトリに実在するラベル名を書く（`gh label list` で確認。無ければ先に作る）。

| 役割 | ラベル名 | 意味 |
|---|---|---|
| needs_decision | `{要判断}` | 人間が決めるまで着手できない。`za:auto` は拾わない |
| needs_manual_check | `{要実機確認}` | 実装は自動でできるが、マージ前に人間が実機で確かめる。`In review` で止める |

## 依存の書式

issue 本文の `## 依存` 節に、**行頭 `- blocked by:` で 1 行 1 依存**を書く。`za:auto` は
この形の行だけを機械的に読む（他の書き方は依存として扱われず、警告として報告される）。

- 同じリポジトリ: `- blocked by: #123`
- 他のリポジトリ: `- blocked by: owner/repo#123`
- 依存なし: `- なし（すぐ着手可）`

行の末尾に補足（`（〜が決まってから）` など）を付けてよい。解決済みを示す取り消し線
（`~~blocked by: #123~~`）は依存として読まない。

## 昇格の条件

依存が解けた issue を `Backlog` から `Ready` に上げるときの追加条件。

| 項目 | 値 | 意味 |
|---|---|---|
| require_milestone | `yes` | `yes` なら、マイルストーンが付いていない issue は昇格しない（スコープ外の扱い） |

`## 依存` 節に `blocked by:` 以外の記述（「〜の結果待ち」など未決定を示すもの）がある issue は、
この条件にかかわらず昇格しない。

## 上限と停止

初期値の目安。慣らし運転が済んでから増やす。

| 項目 | 値 | 意味 |
|---|---|---|
| max_per_run | `1` | 1 回の起動で `za:goal` を実行する issue の上限 |
| max_failures | `2` | 同じ issue の失敗（累計）がこの回数に達したら、その issue に `needs_decision` を付けて `Backlog` に落とし、この起動を止める |
| ci_timeout_minutes | `20` | CI の完了をこの時間まで待つ。超えたら `In review` のまま次の起動で再判定する |
| max_leftover_issues | `2` | 1 件のマージあたりに積み残しから作る issue の上限 |

## 人に回すパス

PR の差分が次に触れていたら、`za:auto` はマージせず `In review` で止めて人に回す
（`needs_manual_check` と同じ扱い）。`docs/ORCHESTRATION.md` / `docs/MERGE.md` /
`.github/workflows/**` は常に含まれる（書かなくてよい）。

| 項目 | 値 | 意味 |
|---|---|---|
| protected_paths | `Makefile`, `.swiftlint.yml`, `scripts/ci/**` | CI が依存する検証手段。ここを変える PR は人が見る（テストを通すために検証を弱める経路を塞ぐ） |
| manual_check_paths | `Sources/App/UI/**`（任意） | ここに触れる PR は実機確認が要るとみなし、`za:auto` が `needs_manual_check` を付けて止める |
| test_paths | `Tests/**`（任意） | ここに当たるファイルを削除する PR は人が見る |

PR 本文の確認事項（チェックボックス）はゲートに使われない。実機確認の要否はラベルと
`manual_check_paths` で決める。

## ゲート

マージの条件（CI 通過・レビュー収束・実機確認ラベルなし・コンフリクトなし など）は
`za:auto` の手順 5 が正本で、設定では緩められない。CI は必須で、`.github/workflows/` に
ワークフローが無いリポジトリでは起動しない。マージ方法・base・head ブランチの扱いは
`docs/MERGE.md` に従う。

## 人間が見る場所

- `needs_decision` の issue: ボードの `Backlog` をラベルで絞る
- `needs_manual_check` の PR、人に回された PR: ボードの `In review`。出口は `/za:merge` で
  マージするか、原因を解消して（ラベルを外す等）`Ready` に戻す（次の起動で再判定される）。
  ただし収束マーカーが無い PR と、ゲート自体（`docs/ORCHESTRATION.md` / `docs/PR.md` 等）を変える PR は
  `Ready` に戻しても再保留されるので、出口は `/za:merge` だけ。`/za:merge` 後に issue が
  閉じなければ（`za:merge` が閉じ損ねた・PR に `Closes` が無い）、issue を手で閉じると次の起動で
  `Done` に移る
- `za:auto` が残したコメント（`za:auto:` で始まる）: 着手・収束・保留・失敗の記録

## 自動運転を止めたいとき

継続運転（cron や `/schedule` からの `claude -p "/za:auto"`、または `/loop`）を止める。
`za:auto` は自分でループを止められない。実行中の 1 件は途中で止めず、その件の報告まで待って
から止める。途中で止めてしまった場合も次の起動時に `za:auto` がボードと実態を突き合わせて直すが、
ローカルが作業ブランチに残っていれば手で base（`docs/PR.md` の base ブランチ）に戻す必要がある。
