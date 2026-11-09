#!/usr/bin/env bash
# Tests for sync_submodules in scripts/sync-repos.sh, against throwaway
# repos. Run: bash scripts/tests/test-sync-repos-submodules.sh
set -u
here="$(cd "$(dirname "$0")" && pwd)"
script="$here/../sync-repos.sh"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp" || exit 1

export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t
export GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_CONFIG_COUNT=1
export GIT_CONFIG_KEY_0=protocol.file.allow GIT_CONFIG_VALUE_0=always

# Load the functions only, not the main loop.
LOG_FILE="$tmp/log" ERR_FILE="$tmp/err" INTERACTIVE=false
eval "$(sed -n '/^log() {/,/^: > "\$LOG_FILE"/p' "$script" | sed '$d')"

sp="s p"
git init -q -b main sub
git -C sub commit -q --allow-empty -m a
git init -q -b main sup
git -C sup submodule add -q ../sub "$sp"
git -C sup commit -q -m add

# A fresh clone of sup, with its submodule checked out at the pointer.
setup() {
  rm -rf c
  git clone -q --recurse-submodules sup c
}
# Add a commit upstream and record it as the pointer, leaving the checkout
# at its old commit.
bump() {
  git -C sub commit -q --allow-empty -m "$1"
  local old
  old=$(git -C "c/$sp" rev-parse HEAD)
  git -C "c/$sp" fetch -q origin
  git -C "c/$sp" checkout -q --detach origin/main
  git -C c add "$sp"
  git -C c commit -q -m bump
  git -C "c/$sp" checkout -q --detach "$old"
}

fails=0
# expect <name> <log text> <head: pin|kept> [branch]
expect() {
  local name=$1 want_log=$2 want_head=$3 want_br=${4:-} before pin head br
  before=$(git -C "c/$sp" rev-parse HEAD)
  : > "$LOG_FILE"
  sync_submodules "$tmp/c" c
  pin=$(git -C c rev-parse "HEAD:$sp")
  head=$(git -C "c/$sp" rev-parse HEAD)
  br=$(git -C "c/$sp" branch --show-current)
  local ok=true
  grep -q "submodule $want_log" "$LOG_FILE" || ok=false
  case $want_head in
    pin) [ "$head" = "$pin" ] || ok=false ;;
    kept) [ "$head" = "$before" ] || ok=false ;;
  esac
  [ "$br" = "$want_br" ] || ok=false
  if $ok; then
    echo "ok   $name"
  else
    echo "FAIL $name: $(cat "$LOG_FILE") head=$head pin=$pin br=$br"
    fails=$((fails + 1))
  fi
}

setup
expect "at pointer" "ok" pin

setup; bump b
expect "behind, detached" "ok (updated)" pin

setup; bump c
git -C "c/$sp" checkout -q -B main
expect "behind, on a branch" "ok (fast-forwarded)" pin main

setup
git -C "c/$sp" checkout -q -B main
git -C "c/$sp" commit -q --allow-empty -m local
expect "ahead" "skipped (ahead or diverged)" kept main

setup; bump d
git -C "c/$sp" checkout -q -B main
git -C "c/$sp" commit -q --allow-empty -m local
expect "diverged" "skipped (ahead or diverged)" kept main

setup; bump e
touch "c/$sp/x"
expect "dirty" "skipped (dirty)" kept

# The pointer names a commit that no remote has.
setup
git -C "c/$sp" commit -q --allow-empty -m lost
git -C c add "$sp"
git -C c commit -q -m "lost pointer"
git -C "c/$sp" reset -q --hard HEAD~1
git -C "c/$sp" reflog expire --expire=now --all
git -C "c/$sp" gc -q --prune=now
expect "pointer commit missing" "skipped (commit missing)" kept

if [ "$fails" -ne 0 ]; then
  echo "$fails failed"
  exit 1
fi
echo "all passed"
