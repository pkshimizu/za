---
name: auto
# model / effort は意図的に設定しない。auto は za:goal / za:issue を Skill ツールで呼び出す
# オーケストレーターであり、各フェーズではそのサブスキル側の model / effort 設定が適用される。
description: >-
  プロジェクトボードの Ready にある issue を上から順に 1 件ずつ取り、za:goal（実装 → PR →
  レビュー収束）→ ゲート判定（CI 通過・レビュー収束・実機確認ラベルの有無）→ マージ →
  ボード更新 → 依存が解けた issue の昇格 → 積み残しの issue 化、を回すオーケストレーター。
  マージは za:merge を呼ばず、docs/MERGE.md のルールに従って za:auto 自身が行う。ゲートを
  1 つでも通らなければマージせず、In review で止めて人に回す。ボード番号・ラベル名・上限など
  プロジェクト固有の値は対象リポジトリの docs/ORCHESTRATION.md から読み、無ければ止まる。
  1 回の起動で処理する件数は設定の上限（既定 1 件）まで。引数は取らない。
  ユーザーが「ボードの issue を自動で片付けて」「Ready を順に回して」「自動運転して」
  「/za:auto を回して」などと明示的に求めたとき、または /za:auto を実行したときに使う。
  曖昧な依頼では使わず、自動運転の意図かを先に確認する。
---

# za:auto — ボードの Ready を 1 件ずつ片付ける

プロジェクトボードの `Ready` から次の 1 件を選び、`za:goal`（実装 → PR → レビュー収束）と
ゲート判定を経て、マージ・ボード更新まで進める。issue 番号ひとつを渡す `za:goal` の一段上で、
「次に何をやるか」自体を決めて回す。人間が関わるのは**決めること**（`needs_decision`）と
**実機で確かめること**（`needs_manual_check`）だけにし、それ以外はボードの整理まで機械が回す。

このスキルは 1 回の起動（1 tick）で設定の上限件数まで処理して終わる。継続して回すときは
`/loop` から起動する（このスキル自身はループしない・止められない）。

## マージの扱い

**`za:merge` は呼ばない。** `za:merge` は人が承認してマージするためのスキルで、その前提は
このスキルでも変えない。代わりに `za:auto` は、**機械で判定できるゲート**（CI がすべて通過・
レビューが収束・実機確認ラベルが無い・コンフリクトなし・`docs/MERGE.md` の前提を満たす）を
すべて通った PR だけを、`docs/MERGE.md` のルールに従って自分でマージする（手順 6）。

ゲートを 1 つでも通らない PR、人の判断が要る状況（想定外の確認、判定できない状態）は
**マージせず `In review` で止めて人に回す**。安全側に倒すのが既定で、迷ったらマージしない。
`git push --force`、`gh pr merge --admin` など、履歴や保護を迂回する操作は行わない。

推奨する運用は、マージ先を `main` ではなく**リリースブランチ**（`develop` 等）にすること。
`docs/MERGE.md` の base をそのブランチにしておけば、`za:auto` の影響はリリースブランチに閉じ、
`main` へのリリースは `za:release`（人が承認する）が担う。

## 前提

- 対象リポジトリはカレントディレクトリ。設定は **`docs/ORCHESTRATION.md`** から読む
  （書式は `assets/ORCHESTRATION.template.md`）。**無い・必須項目が欠ける場合は何もせず止まる。**
  既定値で動かない（ボード番号やラベル名を推測で補うと、違う issue を触る）。
- **CI は必須。** `.github/workflows/` にワークフローが無ければ起動しない（設定では緩められない）。
- 設定は手順 0 で**デフォルトブランチの版を 1 回だけ読み、その起動中は固定**する。マージした
  PR が設定を変えていても、次の起動まで反映しない。
- サブスキル（`za:goal` / `za:issue`）が「停止して報告する」と書いている場面も、`za:auto` の
  手順は続く（Skill ツールは同じ文脈に手順を注入するだけなので）。サブスキルの報告を読み、
  手順 4 の判定へ進む。サブスキルが人の確認を求める場面は、末尾の表のとおり**人に回す**。

## 手順

### 0. 設定と前提を解決する（1 つでも欠けたら何も書かずに止まる）

1. `git status --porcelain` が空、かつ現在ブランチがデフォルトブランチ
   （`gh repo view --json defaultBranchRef -q .defaultBranchRef.name`）であること。
   作業ブランチに残っている場合は、前回の途中終了なので**止まる**（手で戻し、不要な作業ブランチを
   消してから再実行するよう案内する）。`git pull --ff-only` で最新化する。
2. `git show origin/<default>:docs/ORCHESTRATION.md` を読み、次をすべて解決する:
   - ボード: `gh project view <project> --owner <owner> --format json -q .id` で **project id**（`PVT_…`）
   - Status / Priority の **field id** と 5 つの Status の **option id**
     （`gh project field-list <project> --owner <owner> --format json`。設定の値名と一致する option
     が 5 つとも見つかること）
   - ラベル `needs_decision` / `needs_manual_check` が `gh label list` に**実在する**こと
   - `.github/workflows/*.yml` がデフォルトブランチに 1 つ以上あること
   - 上限（`max_per_run` / `max_failures` / `ci_timeout_minutes` / `max_leftover_issues`）
   - `docs/MERGE.md` が読めること（マージ方法・base・head の扱い・マージの前提）
3. ボード全件を取得する: `gh project item-list <project> --owner <owner> --format json --limit 500`。
   各 item は `id` / `status` / `priority` / `labels` / `content.number` / `content.body` /
   `content.repository` を持つ（**`content` に issue の open/closed は無い**ので、必要な item は
   `gh issue view <番号> --json state,stateReason,labels,closedByPullRequestsReferences` で個別に引く）。

### 1. ボードと実態を突き合わせる（リコンシリエーション）

前回が途中で落ちた・人が手で動かした、で Status と実態がずれていることがある。着手前に直す。
対象は `Ready` / `In progress` / `In review` の item（`Done` と `Backlog` は触らない）。

| 実態 | 処置 |
|---|---|
| issue が CLOSED（`stateReason` 問わず）なのに `Done` でない | `Done` にして、手順 7 の昇格を走らせる |
| issue が OPEN で、head が `feature/<番号>-*` の open PR がある（`gh pr list --state open --search "head:feature/<番号>-"`） | `In review` にして、この起動で**手順 5 のゲートから再開**する（`za:goal` は呼ばない）。処理件数に数える |
| `In progress` で open PR も無い | `Ready` に戻して報告する（前回の途中終了） |
| `content.repository` がカレントのリポジトリでない | 触らない。報告だけする |

### 2. 次の 1 件を選ぶ

候補: `status == ready` かつ issue が OPEN かつ `needs_decision` が付いていない、かつ
このリポジトリの issue。並びは **Priority 昇順 → item-list の返却順（ボードの手動順）→
issue 番号昇順**。マイルストーンは条件にしない（順序は依存で決まる）。

先頭候補から順に、次を確認して通ったものを採用する:

- **失敗回数**（末尾「失敗の記録」）が `max_failures` に達している → 候補にしない。
  `needs_decision` を付けて `Backlog` に落とし、報告する
- **依存**: 本文の `## 依存` 節から `^\s*- blocked by:\s*(#\d+|[\w.-]+/[\w.-]+#\d+)` に一致する行を
  読む（取り消し線 `~~` の行は除く）。参照先を `gh issue view --json state,stateReason` で引き:
  - OPEN が 1 つでもある → **`Backlog` に戻して**次の候補へ
  - `stateReason` が `NOT_PLANNED` で閉じたものがある → 却下された前提の上に実装しない。
    `needs_decision` を付けて `Backlog` に落とし、次の候補へ
  - 他リポジトリの参照が取得できない → 未解決とみなし `Backlog` に戻す
  - `blocked by:` の形でない依存らしき記述（「#54 のマージ後」等）→ 依存とは扱わないが、
    **警告として報告に載せる**
- 上記を通った先頭が採用。**候補が 0 件なら止まる**（理由: `Ready` に対象なし。残りが
  `needs_decision` / `needs_manual_check` だけならその旨も書く）。

### 3. `In progress` にして `za:goal` を実行する

1. Status を `In progress` に:
   `gh project item-edit --project-id <PVT> --id <item id> --field-id <Status field> --single-select-option-id <In progress>`
2. Skill ツールで **`za:goal <番号>`** を実行する。実装 → PR 作成 → レビュー収束まで `za:goal` の
   手順に従う（`za:goal` は元から確認なしで動き、マージはしない）。

### 4. 結果を観測して判定する（自己申告ではなく状態で決める）

`za:goal` の報告に頼らず、次を観測する:

- `gh pr list --state open --search "head:feature/<番号>-" --json number,url` で **PR の有無**
- PR があれば `git log origin/<base>..origin/<head> --grep='^review-round:' --oneline | wc -l` と
  `za:review` のサマリー（「未解消の指摘」欄が「なし」か）で**収束したか**

| 観測 | 判定 |
|---|---|
| PR が無い | **失敗**。原因が `gh` / ネットワーク / push など環境なら `kind=env`、それ以外は `kind=issue` として記録（末尾）。Status を `Ready` に戻す。`git switch <default>` して作業ブランチを片付け、次の候補へ |
| PR があるが未収束（打ち切り） | `In review` にして**ゲート不合格**（`kind=issue`）。次の候補へ |
| PR があり収束 | `In review` にして手順 5 へ |

### 5. `In review` にしてゲートを判定する

Status を `In review` にしてから、次をすべて満たすかを見る。1 つでも満たさなければ
**マージせず**、理由を issue コメント（末尾）に残して次の候補へ。

1. **`needs_manual_check` が issue に付いていない。** 付いていれば `In review` で止める
   （**成功扱い**。失敗には数えない。人が実機で確かめてからマージする）
2. **PR の差分が `docs/ORCHESTRATION.md` / `docs/MERGE.md` / `.github/workflows/**` に触れていない**
   （`gh pr diff <番号> --name-only`）。触れていれば 1 と同じ扱い（ゲート自体の変更は人が見る）
3. **レビューが収束している**（手順 4）
4. **CI がすべて通過**: `gh pr checks <番号> --watch --fail-fast` を Bash のタイムアウトを
   `ci_timeout_minutes` にして実行する。
   - 全チェックの結論が `success` / `skipped` / `neutral` → 合格
   - `failure` / `cancelled` → 不合格（`kind=issue`）
   - チェックが 1 つも無い（"no checks reported"）→ 不合格（CI が走っていない。ワークフローの
     トリガーを疑う）
   - タイムアウト → **`In review` のまま次へ**（失敗に数えない。次の起動の手順 1 でゲートから再開）
5. **コンフリクトなし**: `gh pr view <番号> --json mergeable,mergeStateStatus`。`UNKNOWN` の間は
   数回引き直す。`CONFLICTING` → 不合格（`kind=issue`）
6. **`docs/MERGE.md` の「マージの前提」**のうち機械で判定できる項目（PR 本文の確認事項が
   すべてチェック済み 等）。満たさなければ不合格。機械で判定できない前提が書かれていれば、
   それは人の判断なので**不合格として人に回す**

### 6. マージする

すべてのゲートを通った PR を、`docs/MERGE.md` のルールに従ってマージする:

- マージ方法（merge commit / squash / rebase）と head ブランチを削除するかは `docs/MERGE.md` の
  指定に従う。指定が無ければリポジトリの慣習（既存 PR のマージ履歴）に合わせ、判断がつかなければ
  **マージせず人に回す**
- `gh pr merge <番号> --<方法> [--delete-branch]`。`--match-head-commit <手順 4 で見た head の SHA>`
  を付け、ゲート判定後に head が進んでいたら拒否させる（進んでいたら不合格として次へ）
- マージに失敗した → 不合格（`kind=env`）。回避策は取らず、`In review` のまま次の候補へ
- マージ後、`git switch <default>` → `git pull --ff-only`。ローカルに作業ブランチが残っていれば
  削除する

### 7. `Done` にして、依存が解けた issue を昇格する

1. Status を `Done` にする（マージで issue は自動クローズされている）。
2. 手順 0 で取得済みの item-list から **`Backlog` の item の本文をローカルで解析**し
   （検索 API は使わない。`gh issue list --search "#57"` は 57 を含む無関係な issue や自分自身を
   返す）、`blocked by:` に今閉じた issue を含むものを集める。
3. それぞれについて、依存を**すべて**手順 2 の規則で再確認し、全部 CLOSED（`NOT_PLANNED` を
   除く）なら `Ready` に上げる。`needs_decision` が付いているものは上げない。
4. 昇格した issue を報告に載せる（リリース issue が閉じたときは一斉に上がる）。

### 8. 積み残しを issue 化する

マージした PR の積み残し（レビューで持ち越した設計変更、PR 本文に残った未達の確認事項、
スコープ外として送った改善）のうち、**対応が要るもの**だけを issue にする。次を守る:

- `za:review` が「記録のみ」にした minor / nit は対象外（issue にしない、と `za:review` が定めている）
- 1 件のマージあたり `max_leftover_issues` まで
- 作成前に `gh issue list --state open --search "<タイトルの要点>"` で重複を弾く
- プランは**リポジトリの外**（scratchpad）に `{yyyymmdd}-{slug}.md` として書き、Skill ツールで
  **`za:issue <そのパス>`** を実行する（リポジトリ内に置くと `za:issue` が `docs/plans/done/` へ
  移動して作業ツリーが汚れ、次の起動が止まる）。`za:issue` は作成前に承認を求めるので、
  「確認は不要、そのまま作成して」を添えて呼ぶ（`za:issue` 自身がその省略を認めている）
- 作った issue は**必ず `needs_decision` を付けて `Backlog`** に置く（`gh project item-add` →
  Status を設定）。自動運転が自分の仕事を生成して回り続ける閉路を切る。`Ready` に上げるのは人

### 9. 報告して、次へ進むか止まる

1 件ごとに次を 1 画面で報告する:

- 対象 issue（番号・タイトル）と最終 Status
- `za:goal` の成果（ブランチ・PR URL・レビュー周回数）と判断ログ
- ゲートの結果（各項目の合否）とマージの有無
- 昇格した issue、作った issue
- 止まった場合は**停止条件のどれか**と、人が次に何をすればよいか

処理件数（手順 1 の再開分を含む）が `max_per_run` に達したら止まる。達していなければ
手順 2 に戻る。

## 失敗の記録

失敗した issue に、次のマーカーを含むコメントを残す:

```
<!-- za:auto:failure kind=issue|env pr=<番号 or none> -->
za:auto: <日時> <どの手順で・何が起きたか・次に人が見るべきこと>
```

- `kind=issue`: その issue に起因する失敗（レビュー未収束、CI 失敗、コンフリクト、実装不能）。
  **失敗回数に数える**
- `kind=env`: 環境に起因する失敗（`gh` の失敗、ネットワーク、ランナー停止、push 失敗）。
  数えない。この起動は止める（同じ環境で次の issue も失敗するため）
- 失敗回数 = その issue の **`kind=issue` マーカーの数**（人が消せばリセットされる。それは人の判断）
- 今回の失敗で `max_failures` に達したら、`needs_decision` を付けて `Backlog` に落とし、
  **この起動を止める**（次の起動では候補にならないので、同じ issue に毎回突撃しない）

## 停止条件（この起動を終える）

1 件の失敗では止めず次の候補へ進む。次のときだけこの起動を終える（理由を報告に明記）:

- `docs/ORCHESTRATION.md` / `docs/MERGE.md` が無い、必須項目が欠ける、ラベル・Status・CI が
  実在しない（手順 0）
- 作業ツリーに未コミット変更がある、または作業ブランチに残っている（手順 0）
- `Ready` に対象が 1 件も無い。残りが `needs_decision` / `needs_manual_check` だけの場合も含む
- 同じ issue の失敗が `max_failures` に達した
- 環境起因（`kind=env`）の失敗が起きた
- 処理件数が `max_per_run` に達した

`/loop` で回している場合、この起動が止まっても次の tick は起動する。上の理由が解消しない限り
次の tick も同じ理由で止まるので、報告には「`/loop` を止めるか、〜を解消してから」を添える。

## サブスキルが人の確認を求める場面

| スキル・場面 | `za:auto` での扱い |
|---|---|
| `za:goal` 全般（実装方針・PR 作成・指摘の採否） | `za:goal` 自身の自動採用ルールに任せる（元から確認なしで動く） |
| `za:goal` の「前提不成立で停止」 | 手順 4 で失敗として記録し、次の候補へ |
| `za:review` が 3 周で収束せず、直すか issue 化するかを尋ねる | 直さない。未収束としてゲート不合格（人が PR を見る） |
| `za:issue` の作成前の承認 | `za:issue` が認める「確認不要」の省略を使う（作る issue は `needs_decision` + `Backlog` 固定） |
| 上記に無い確認・判定できない状態 | マージも作成もせず、`In review` / `Backlog` で止めて人に回す |
