#!/usr/bin/env bash
# wait-for-comment.sh
# hunk の未解決レビューコメント (user) が現れるまでブロックし、現れたら
# そのコメント配列を JSON で標準出力に出して終了する。タイムアウト時は空配列 [] を出す。
#
# バックグラウンド実行 (run_in_background) を想定。プロセス終了で呼び出し元が
# 再起動され、出力(コメント)を受け取って対応できる。
#
# 使い方: wait-for-comment.sh [repo] [interval_sec] [timeout_sec]
#   repo         : 対象リポジトリのパス (既定: git のトップレベル、無ければ .)
#   interval_sec : ポーリング間隔秒 (既定: 5)
#   timeout_sec  : この秒数コメントが無ければ [] を返して終了 (既定: 1800)
set -uo pipefail

repo="${1:-}"
if [ -z "$repo" ]; then
  repo="$(git rev-parse --show-toplevel 2>/dev/null || echo .)"
fi
interval="${2:-5}"
timeout="${3:-1800}"

if ! command -v hunk >/dev/null 2>&1; then
  echo 'ERROR: hunk コマンドが見つかりません' >&2
  exit 1
fi
if ! command -v jq >/dev/null 2>&1; then
  echo 'ERROR: jq コマンドが見つかりません' >&2
  exit 1
fi

elapsed=0
while :; do
  json="$(hunk session comment list --repo "$repo" --type user --json 2>/dev/null)" || json='{"comments":[]}'
  count="$(printf '%s' "$json" | jq '.comments | length' 2>/dev/null || echo 0)"
  if [ "${count:-0}" -gt 0 ]; then
    printf '%s\n' "$json" | jq -c '.comments'
    exit 0
  fi
  if [ "$elapsed" -ge "$timeout" ]; then
    echo '[]'
    exit 0
  fi
  sleep "$interval"
  elapsed=$((elapsed + interval))
done
