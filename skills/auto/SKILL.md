---
name: auto
# model / effort は意図的に設定しない。auto は za:goal / za:issue を Skill ツールで呼び出す
# オーケストレーターであり、各フェーズではそのサブスキル側の model / effort 設定が適用される。
description: >-
  プロジェクトボードの Ready にある issue を上から順に 1 件ずつ取り、za:goal（実装 → PR →
  レビュー収束）→ ゲート判定（CI 通過・レビュー収束・実機確認ラベルなし・コンフリクトなし
  など、手順 5 が正本）→ マージ → ボード更新 → 依存が解けた issue の昇格 → 積み残しの
  issue 化、を回すオーケストレーター。マージは za:merge を呼ばず、docs/MERGE.md のルールに
  従って za:auto 自身が行う。ゲートを 1 つでも通らなければマージせず、In review で止めて人に
  回す。ボード番号・ラベル名・上限などプロジェクト固有の値は対象リポジトリの
  docs/ORCHESTRATION.md から読み、必要な設定が無ければ止まる。1 回の起動で処理する件数は
  設定の上限まで。引数は取らない。ユーザーが「ボードの issue を自動で片付けて」「Ready を
  順に回して」「自動運転して」などと明示的に求めたとき、または /za:auto を実行したときに使う。
  曖昧な依頼では使わず、自動運転の意図かを先に確認する。
---

# za:auto — ボードの Ready を 1 件ずつ片付ける

プロジェクトボードの `Ready` から次の 1 件を選び、`za:goal`（実装 → PR → レビュー収束）と
ゲート判定を経て、マージ・ボード更新まで進める。issue 番号ひとつを渡す `za:goal` の一段上で、
「次に何をやるか」自体を決めて回す。人間が関わるのは**決めること**（`needs_decision`）と
**実機で確かめること**（`needs_manual_check`）だけにし、それ以外はボードの整理まで機械が回す。

このスキルは 1 回の起動（1 tick）で設定の上限件数まで処理して終わる。継続運転は、セッションを
分けて起動する（cron や `/schedule` から `claude -p "/za:auto"`）。`/loop` は同じセッションに
`za:goal` の作業ログが積み重なって文脈が圧縮されるので、短時間の慣らし運転にとどめる。
このスキル自身はループしない・止められない。

本文の `Ready` / `Backlog` / `In progress` / `In review` / `Done` は、`docs/ORCHESTRATION.md` の
役割名 ready / backlog / in_progress / in_review / done を指す。実際の表記は設定の値。

## マージの扱い

**`za:merge` は呼ばない。** `za:merge` は人が承認してマージするためのスキルで、その前提は
このスキルでも変えない。代わりに `za:auto` は、**機械で判定できるゲート**（手順 5）を
すべて通った PR だけを、`docs/MERGE.md` のルールに従って自分でマージする（手順 6）。

ゲートを 1 つでも通らない PR、人の判断が要る状況（想定外の確認、判定できない状態）は
**マージせず `In review` で止めて人に回す**。安全側に倒すのが既定で、迷ったらマージしない。
保留した PR の出口は 2 つ: 人が **`/za:merge`** でマージする（issue が閉じれば手順 1 で `Done` に
移る）か、原因を解消して（ラベルを外す等）item を **`Ready` に戻す**（次の起動でゲートから
再判定する）。ただし `hold reason=unconverged`（収束マーカーが無い・SHA が違う）は `za:auto` では
解けないので、出口は `/za:merge` だけ。
`git push --force`、`gh pr merge --admin` など、履歴や保護を迂回する操作は行わない。
機械の判断をボードに書くときは、必ず issue コメントに理由を残す（人が後から追えるように）。

マージ先は `docs/MERGE.md` の base。`za:fix-issue` / `za:pr` は `docs/PR.md` の base から
分岐して PR を作るので、この 2 つは一致していなければならない（手順 0 で検証する）。
推奨する運用は base をリリースブランチ（`develop` 等）にすること。`za:auto` の影響が
リリースブランチに閉じ、デフォルトブランチへのリリースは `za:release`（人が承認する）が担う。
以下「base」はこのブランチを指す。

## 前提

- 対象リポジトリはカレントディレクトリ。設定は **`docs/ORCHESTRATION.md`**（書式は
  `assets/ORCHESTRATION.template.md`）と **`docs/MERGE.md`** から読む。**どちらかが無い・必須
  項目が欠ける場合は何もせず止まる。** 既定値で動かない（ボード番号やラベル名を推測で補うと、
  違う issue を触る）。
- **CI は必須。** `.github/workflows/` にワークフローが無ければ起動しない（設定では緩められない）。
- 設定は手順 0 で **base 上の版を 1 回だけ読み、その起動中は固定**する（base に入る設定変更は、
  ゲート 3 により必ず人がマージしている）。
- サブスキル（`za:goal` / `za:issue`）が「停止して報告する」と書いている場面も、`za:auto` の
  手順は続く（Skill ツールは同じ文脈に手順を注入するだけなので）。サブスキルの報告を読み、
  手順 4 の判定へ進む。サブスキルが人の確認を求める場面は、末尾の表のとおり**人に回す**。
- tick の中で必要な状態（PR 番号・head の SHA・処理件数）は文脈に頼らず、そのつど `gh` で
  引き直す。

## 手順

### 0. 設定と前提を解決する

1 つでも欠けたら、ボードにも issue にも何も書かずに止まる。

1. `git status --porcelain` が空、かつ現在ブランチが base（`docs/PR.md` の「base ブランチ」節。
   無ければデフォルトブランチ `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`）
   であること。
   作業ブランチに残っている場合は、前回の途中終了なので**止まる**（手で戻し、不要な作業ブランチを
   消してから再実行するよう案内する）。`git fetch origin` → `git pull --ff-only`。
2. base を決める（`docs/PR.md` の「base ブランチ」節。無ければデフォルトブランチ）。
   `git show origin/<base>:docs/ORCHESTRATION.md` と同じく `docs/MERGE.md` を読み、次をすべて解決する:
   - ボード: `gh project view <project> --owner <owner> --format json -q .id` で **project id**（`PVT_…`）
   - Status の **field id** と 5 つの **option id**（`gh project field-list <project> --owner <owner>
     --format json`。設定の値名と一致する option が 5 つとも見つかること）。`priority_field` が
     あればその field id も
   - ラベル `needs_decision` / `needs_manual_check` が `gh label list` に**実在する**こと
   - `.github/workflows/*.yml` または `*.yaml` が base に 1 つ以上あること
   - 上限（`max_per_run` / `max_failures` / `ci_timeout_minutes` / `max_leftover_issues`）、
     `protected_paths`、`require_milestone`、任意の `manual_check_paths` / `test_paths`
   - `docs/MERGE.md` の base・マージ方法・head の扱い・マージの前提。**`docs/MERGE.md` の base と
     `docs/PR.md` の base が一致**すること（違えば止まる。`za:pr` が作る PR の base とマージ先が
     ずれる）。base が `origin` に存在すること
3. ボード全件を取得する: `gh project item-list <project> --owner <owner> --format json --limit 500`。
   返却が 500 件に達したら（取りこぼしの可能性）止まる。各 item は `id` / `status` / `priority` /
   `labels` / `content.number` / `content.body` / `content.repository` を持つ（**`content` に issue の
   open/closed は無い**）。
4. open PR の一覧を取る: `gh pr list --state open --limit 200 --json number,url,headRefName,headRefOid,baseRefName`。
   issue に紐づく PR は、`headRefName` を `^feature/<番号>-` で照合して決める（`gh pr list --search
   "head:…"` は使わない。完全一致かどうかが不確かで、`feature/1-` が `feature/12-` に当たる）。
   必要なら `gh issue view <番号> --json closedByPullRequestsReferences` も併用する。

### 1. ボードと実態を突き合わせる

前回が途中で落ちた・人が手で動かした、で Status と実態がずれていることがある。着手前に直す。
**触るのは `za:auto` が着手した痕跡（`<!-- za:auto:started -->` コメント）がある item だけ。**
人が手で動かしている item は、機械が正しいと決めつけて上書きしない（報告だけする）。

| 実態 | 処置 |
|---|---|
| issue が CLOSED（理由問わず）なのに `Done` でない | `Done` にして、手順 7 の昇格を走らせる |
| `In progress` で open PR も無い（着手痕跡あり） | `Ready` に戻し、コメントで理由を残す（前回の途中終了） |
| `Ready` / `In progress` で open PR がある（着手痕跡あり） | `In review` にし、手順 5 のゲートから再開する。**処理件数には数えない** |
| `In review` | **触らない**（人待ち）。例外は、最新の `za:auto` コメントが `hold reason=ci_timeout` のもので、これだけ手順 5 から再判定する（数えない） |
| `content.repository` がカレントのリポジトリでない | 触らない。報告だけする |

### 2. 次の 1 件を選ぶ

候補: `Ready` かつ issue が OPEN（`gh issue view --json state`）かつ `needs_decision` が付いて
いない、かつこのリポジトリの issue。並びは **Priority 昇順（未設定は末尾）→ item-list の返却順
（ボードの手動順）→ issue 番号昇順**。マイルストーンは選択の条件にしない（順序は依存で決まる）。

先頭候補から順に、次を確認して通ったものを採用する:

- **失敗回数**（末尾「失敗の記録」）が `max_failures` に達している → 候補にしない（本来は
  失敗時に `Backlog` へ落ちているはずなので、人がラベルだけ外した等の保険）
- **依存**: 本文の `## 依存` 節から `^\s*- blocked by:\s*(#\d+|[\w.-]+/[\w.-]+#\d+)` に一致する行を
  読む（取り消し線 `~~` の行は除く）。参照先を `gh issue view --json state,stateReason` で引き:
  - OPEN が 1 つでもある → **飛ばして**次の候補へ。Status は動かさず、issue に
    `<!-- za:auto:skip reason=blocked -->` を含むコメントで「依存 #N が未解決」と残す（同じ理由の
    連投はしない。人が承知で `Ready` に置いた可能性があるので、毎 tick `Backlog` へ差し戻す
    綱引きはしない）
  - `stateReason` が `NOT_PLANNED` で閉じたものがある → 却下された前提の上に実装しない。
    `needs_decision` を付けて `Backlog` に落とし、コメントを残して次の候補へ
  - 他リポジトリの参照が取得できない → 未解決とみなし飛ばす
  - `blocked by:` の形でない依存らしき記述（「#54 のマージ後」等）→ 依存とは扱わないが、
    **警告として報告に載せる**
- 上記を通った先頭が採用。**候補が 0 件なら止まる**（理由: `Ready` に対象なし。残りが
  `needs_decision` / `needs_manual_check` だけならその旨も書く）。

### 3. `In progress` にして `za:goal` を実行する

1. issue に `<!-- za:auto:started -->` を含むコメント（`za:auto: 着手 <日時>`）を残す。
2. Status を `In progress` に:
   `gh project item-edit --project-id <PVT> --id <item id> --field-id <Status field> --single-select-option-id <In progress>`
3. Skill ツールで **`za:goal <番号>`** を実行する。実装 → PR 作成 → レビュー収束まで `za:goal` の
   手順に従う（`za:goal` は元から確認なしで動き、マージはしない）。処理件数を +1 する。

### 4. 結果を観測して判定する

`za:goal` の報告に頼らず、状態で決める。`git fetch origin` してから:

- 手順 0-4 の方法で **PR の有無**を見る
- PR があれば **収束したか**: `za:review` のサマリー（指摘の一覧に状態「未解消」の行が無く、
  「レビュー範囲」に打ち切りの記載が無い）で判定する。収束していれば、PR に
  `<!-- za:auto:converged sha=<headRefOid> -->` を含むコメントを残す（再開経路で機械的に
  読めるように）。`headRefOid` は `gh pr view <番号> --json headRefOid` で取る

| 観測 | 判定 |
|---|---|
| PR が無い | **失敗**として記録し、Status を `Ready` に戻す。push 拒否・`gh` の失敗が原因なら `kind=env`（4-a で片付けてこの起動を止める）、それ以外は `kind=issue`（4-a で片付けて次の候補へ） |
| PR があるが未収束 | `In review` にして**ゲート不合格**（`kind=issue`）。手順 4-a で片付けて次の候補へ |
| PR があり収束 | `In review` にして手順 5 へ |

#### 4-a. 候補を切り替える前の後始末

失敗・不合格・保留で次の候補へ進む前に、必ず base のきれいな状態に戻す。
`za:goal` は作業ブランチに居るまま終わり、途中で落ちると未コミット変更が残る。

```sh
git reset --hard && git switch <base> && git pull --ff-only
git branch -D <作業ブランチ>      # 失敗した試行の変更は捨ててよい（PR があればリモートに残る）
```

戻したあと `git status --porcelain` が空で base にいることを再検証する。満たせなければ
`kind=env` としてこの起動を止める（汚れたツリーで次の issue を始めると、無関係な issue に失敗が
積まれる）。

### 5. ゲートを判定する

PR は `In review` にある。次をすべて満たすかを見る。判定の最初に
`gh pr view <番号> --json headRefOid,baseRefName,mergeable,mergeStateStatus` を引き、この **SHA を
手順 6 のマージに使う**。1 つでも満たさなければ**マージせず**、保留（`kind=hold`）または不合格
（`kind=issue`）として issue コメントに残し、手順 4-a で片付けて次の候補へ。

1. **`baseRefName` が `docs/MERGE.md` の base と一致**。違えば保留（人に回す）
2. **`needs_manual_check` が issue に付いていない。** 付いていれば保留（`hold reason=manual_check`。
   **成功扱い**で失敗には数えない。人が実機で確かめてからマージする）
3. **PR の差分が人に回すパスに触れていない**（`gh pr diff <番号> --name-only`）:
   `docs/ORCHESTRATION.md` / `docs/MERGE.md` / `.github/workflows/**` / 設定の `protected_paths`。
   触れていれば保留（`hold reason=protected_path`。ゲート自体と、ゲートが依存する検証手段の変更は
   人が見る）。設定に `test_paths` があれば、そこに当たるファイルの削除
   （`git diff --diff-filter=D --name-only origin/<base>...origin/<head>`）も同じ扱い。
   設定の `manual_check_paths` に触れていれば `needs_manual_check` を**付けて**保留する。ただし
   **その issue に `pr=` が現在の PR 番号と一致する `hold reason=manual_check` のマーカーが既にあり、
   いまラベルが外れているなら、人が確認を終えて外したとみなして付け直さず、このゲートは通す**
   （人の解除を上書きしない）。別の PR に対するマーカーしか無ければ、従来どおり付けて保留する
   （やり直した新しい PR を、古い確認で通さない）
4. **レビューが収束している**: PR コメントに `za:auto:converged` マーカーがあり、その `sha` が
   現在の `headRefOid` と一致する。マーカーが無い（人が作った PR、`za:goal` が途中で落ちた PR）・
   SHA が違う（収束後に push された）→ **判定できない**ので保留。`za:review` を通していない
   PR を CI だけでマージしない
5. **CI がすべて通過**: `gh pr checks <番号> --json name,bucket` で判定する
   （`bucket` は `pass` / `fail` / `pending` / `skipping` / `cancel`）。
   - すべて `pass` / `skipping` → 合格
   - `fail` / `cancel` がある → 不合格（`kind=issue`）
   - `pending` がある → `gh pr checks <番号> --watch --fail-fast` で待つ。Bash の 1 回の上限は
     10 分なので、合計が `ci_timeout_minutes` に達するまで繰り返す。超えたら保留
     （`hold reason=ci_timeout`。次の起動の手順 1 で再判定する）
   - チェックが 1 つも無い（"no checks reported"）→ push 直後は登録前のことがあるので、
     30 秒程度おいて数回引き直す。それでも無ければ **CI が走っていない**ので、issue に
     マーカーを付けずに**この起動を止める**（ワークフローのトリガーを疑う。issue の責任ではない）
6. **コンフリクトなし**: `mergeable` が `UNKNOWN` の間は数回引き直す。`CONFLICTING` → 不合格
   （`kind=issue`）
7. **`docs/MERGE.md` の「マージの前提」**のうち、ゲート 1〜6 で判定していない機械判定可能な
   項目（無ければ空）。「レビューが完了している」はゲート 4 で判定済みなので、`reviewDecision` で
   別途判定しない。機械で判定できない前提が書かれていれば保留。**PR 本文の確認事項は
   ゲートに使わない**（`za:pr` が書いた自己申告なので、合格の根拠にも保留の根拠にもしない。
   実機確認の要否はゲート 2 のラベルとゲート 3 の `manual_check_paths` だけで決める）

### 6. マージする

すべてのゲートを通った PR を、`docs/MERGE.md` のルールに従ってマージする:

- マージ方法（merge commit / squash / rebase）と head ブランチを削除するかは `docs/MERGE.md` の
  指定に従う。指定が無ければリポジトリの慣習（既存 PR のマージ履歴）に合わせ、判断がつかなければ
  保留（人に回す）
- `gh pr merge <番号> --<方法> [--delete-branch] --match-head-commit <手順 5 で取った SHA>`。
  ゲート判定後に head が進んでいたら拒否される → 保留（人に回す）
- 保護ルールで拒否された → issue の責任ではないので、マーカーを付けずに**この起動を止める**
  （設定か権限の問題）。それ以外の失敗は `kind=env`
- マージ後、`git switch <base>` → `git pull --ff-only`。PR が MERGED であることを
  `gh pr view --json state` で確認してから、ローカルの作業ブランチを `git branch -D` で消す

### 7. `Done` にして、依存が解けた issue を昇格する

1. `gh issue view <番号> --json state` を引き、OPEN なら `gh issue close <番号> --reason completed
   --comment "<PR URL> をマージ"` で閉じる（`Closes #N` による自動クローズはデフォルトブランチへの
   マージ時だけ。`za:pr` が付け損ねた場合も同じ）。そのうえで Status を `Done` にする。
2. 手順 0 で取得済みの item-list から **`Backlog` の item の本文をローカルで解析**し
   （検索 API は使わない。`gh issue list --search "#57"` は 57 を含む無関係な issue や自分自身を
   返す）、`blocked by:` に今閉じた issue を含むものを集める。
3. それぞれについて、次をすべて満たせば `Ready` に上げ、issue に「依存 #N が閉じたので Ready へ」と
   コメントする:
   - 依存を**すべて**手順 2 の規則で再確認し、全部 CLOSED（`NOT_PLANNED` を除く）
   - `## 依存` 節に `blocked by:` 以外の記述（未決定を示すもの）が無い
   - `needs_decision` が付いていない
   - `require_milestone` が `yes` なら、マイルストーンが付いている
4. 昇格した issue を報告に載せる（リリース issue が閉じたときは一斉に上がる）。

### 8. 積み残しを issue 化する

マージした PR の積み残し（レビューで持ち越した設計変更、スコープ外として送った改善）のうち、
**対応が要るもの**だけを issue にする。次を守る:

- `za:review` が「記録のみ」にした minor / nit は対象外（issue にしない、と `za:review` が定めている）
- 1 件のマージあたり `max_leftover_issues` まで。**`za:issue` には「分割せず 1 プラン 1 issue で
  作る」を明示**する（`za:issue` はプランを複数 issue に分割してよいので、上限が issue 数に効く
  ように）
- 作成前に `gh issue list --state open --search "<タイトルの要点>"` で重複を弾く
- プランは**リポジトリの外**（scratchpad）に `{yyyymmdd}-{slug}.md` として書き、Skill ツールで
  **`za:issue <そのパス>`** を実行する。`za:issue` は作成前に承認を求めるので「確認は不要、
  そのまま作成して」を添える（`za:issue` 自身がその省略を認めている）。`za:issue` は起点の
  プランを `docs/plans/done/` へ移動するので、**呼び出し後に `git status --porcelain` を見て、
  未追跡で増えた `docs/plans/done/<ファイル>` を削除**し、作業ツリーを空に戻す
- `za:issue` の報告から作成された issue 番号をすべて取り、それぞれに
  `gh issue edit <番号> --add-label <needs_decision>` → `gh project item-add <project> --owner <owner>
  --url <URL> --format json -q .id` → Status を `Backlog` に設定する。**必ず `needs_decision` +
  `Backlog`** に置く（自動運転が自分の仕事を生成して回り続ける閉路を切る。`Ready` に上げるのは人）。
  1 件でも失敗したら報告に載せる

### 9. 報告して、次へ進むか止まる

1 件ごとに次を 1 画面で報告する:

- 対象 issue（番号・タイトル）と最終 Status
- `za:goal` の成果（ブランチ・PR URL・レビュー周回数）と判断ログ
- ゲートの結果（各項目の合否）とマージの有無
- 昇格した issue、作った issue、手順 1 で直した item
- 止まった場合は**停止条件のどれか**と、人が次に何をすればよいか

処理件数（`za:goal` を実行した件数。手順 1 の再開分は含まない）が `max_per_run` に達したら
止まる。達していなければ手順 2 に戻る。

## 失敗と保留の記録

issue に、次のマーカーを含むコメントを残す。`za:auto:` で始まるコメントはすべて、同じ issue に
同じ理由で連続して残さない（最新の `za:auto` コメントと理由が同じならスキップ）。

```
<!-- za:auto:failure kind=issue|env pr=<番号 or none> -->
<!-- za:auto:hold reason=<manual_check|protected_path|unconverged|ci_timeout|base_mismatch|...> pr=<番号> -->
za:auto: <日時> <どの手順で・何が起きたか・次に人が見るべきこと>
```

- `kind=issue`: その issue に起因する失敗（レビュー未収束、CI 失敗、コンフリクト、実装不能）。
  **失敗回数に数える**。手順 3 以降で起きた失敗は原則これ
- `kind=env`: 環境に起因する失敗。**手順 0〜2 と 4-a、`gh` の認証・ネットワーク・push 拒否に
  限る**（手順 3 以降の失敗を都合よく env に倒さない）。数えない。**この起動は止める**（同じ
  環境で次の issue も失敗するため）
- `hold`: 保留。人に回すだけで失敗ではない。数えない。この起動は止めず次の候補へ
- 失敗回数 = その issue の **`kind=issue` マーカーの数（累計）**。間に人の操作があっても数える
  （人が消せばリセットされる。それは人の判断）
- 今回の失敗で `max_failures` に達したら、`needs_decision` を付けて `Backlog` に落とし、
  **この起動を止める**（次の起動では候補にならないので、同じ issue を毎回選ばない）

## 停止条件（この起動を終える）

1 件の失敗では止めず次の候補へ進む。次のときだけこの起動を終える（理由を報告に明記）:

- `docs/ORCHESTRATION.md` / `docs/MERGE.md` が無い、必須項目が欠ける、ラベル・Status・CI が
  実在しない（手順 0）
- 作業ツリーに未コミット変更がある、または作業ブランチに残っている（手順 0・4-a）
- `docs/PR.md` と `docs/MERGE.md` の base が食い違う、base が `origin` に無い（手順 0）
- `Ready` に対象が 1 件も無い。残りが `needs_decision` / `needs_manual_check` だけの場合も含む
- 同じ issue の失敗が `max_failures` に達した
- 環境起因（`kind=env`）の失敗、CI が走っていない、保護ルールでマージが拒否された
- 処理件数が `max_per_run` に達した

起動を止めるときも、手順 3 以降にいるなら先に 4-a を通して base のきれいな状態に
戻す（戻せなかった場合だけ、手順 0 の前提不成立として次の起動が止まる）。

継続運転している場合、この起動が止まっても次の起動は走る。上の理由が解消しない限り次も同じ
理由で止まるので、報告には「継続運転を止めるか、〜を解消してから」を添える。

## サブスキルが人の確認を求める場面

| スキル・場面 | `za:auto` での扱い |
|---|---|
| `za:goal` 全般（実装方針・PR 作成・指摘の採否） | `za:goal` 自身の自動採用ルールに任せる |
| `za:goal` の「前提不成立で停止」 | 手順 4 で失敗として記録し、次の候補へ |
| `za:review` が 3 周で収束せず、直すか issue 化するかを尋ねる | 直さない。未収束として不合格（人が PR を見る） |
| `za:issue` の作成前の承認 | `za:issue` が認める「確認不要」の省略を使う（作る issue は `needs_decision` + `Backlog` 固定） |
| 上記に無い確認・判定できない状態 | マージも作成もせず、保留として人に回す |
