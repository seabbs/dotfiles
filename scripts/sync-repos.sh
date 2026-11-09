#!/bin/bash
# Fetch and fast-forward the default branch for every repo under ~/code.
# Safe to run from any branch — updates local main/master without checkout.
#
# When run interactively, prints all results.
# When run by launchd (no tty), only logs failures.

CODE_DIR="$HOME/code"
LOG_DIR="$HOME/.local/share/sync-repos"
LOG_FILE="$LOG_DIR/last-run.log"
ERR_FILE="$LOG_DIR/errors.log"
LOCK_FILE="$LOG_DIR/lock"
mkdir -p "$LOG_DIR"

# One run at a time -- a hung fetch would otherwise pile up on every repo.
# flock isn't part of macOS by default (`brew install flock`, done by
# cli/setup.sh) -- fail loudly rather than let a missing binary make
# `flock -n 9` exit 127, indistinguishable from "lock held".
command -v flock >/dev/null 2>&1 || {
  echo "flock not found -- run 'brew install flock' (see cli/setup.sh)" >&2
  exit 1
}
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

ok_count=0
skip_count=0

log() {
  printf "%-50s %s\n" "$1" "$2" >> "$LOG_FILE"
  $INTERACTIVE && printf "%-50s %s\n" "$1" "$2"
  return 0
}

sub_warn() {
  log "$1" "submodule $2"
  echo "$(date '+%Y-%m-%d %H:%M') $1: submodule $2" >> "$ERR_FILE"
}

# A pull moves submodule pointers but not their checkouts (e.g. dotfiles'
# claude/), so bring each one up to its pointer. Only ever move a checkout
# forward: skip any with local changes or commits the pointer lacks, so a
# live checkout ahead of its pointer is never rolled back. A checkout on a
# branch is fast-forwarded on that branch rather than detached.
sync_submodules() {
  local dir=$1 name=$2 sub s want have
  [ -f "$dir/.gitmodules" ] || return 0
  git -C "$dir" submodule init --quiet 2>/dev/null
  for sub in $(git -C "$dir" config --file .gitmodules \
      --get-regexp 'submodule\..*\.path' | awk '{print $2}'); do
    s="$dir/$sub"
    want=$(git -C "$dir" rev-parse --verify -q "HEAD:$sub") || continue
    if [ ! -e "$s/.git" ]; then
      if git -C "$dir" submodule update --quiet -- "$sub" 2>/dev/null; then
        log "$name/$sub" "submodule ok (checked out)"
      else
        sub_warn "$name/$sub" "failed"
      fi
      continue
    fi
    have=$(git -C "$s" rev-parse HEAD 2>/dev/null)
    if [ "$have" = "$want" ]; then
      log "$name/$sub" "submodule ok"
    elif [ -n "$(git -C "$s" status --porcelain 2>/dev/null)" ]; then
      sub_warn "$name/$sub" "skipped (dirty)"
    elif ! { git -C "$s" cat-file -e "$want^{commit}" 2>/dev/null ||
        git -C "$s" fetch --quiet origin 2>/dev/null; } ||
        ! git -C "$s" merge-base --is-ancestor "$have" "$want" 2>/dev/null
    then
      sub_warn "$name/$sub" "skipped (ahead or diverged)"
    elif git -C "$s" symbolic-ref -q HEAD >/dev/null; then
      if git -C "$s" merge --ff-only --quiet "$want" 2>/dev/null; then
        log "$name/$sub" "submodule ok (fast-forwarded)"
      else
        sub_warn "$name/$sub" "failed"
      fi
    elif git -C "$dir" submodule update --quiet -- "$sub" 2>/dev/null; then
      log "$name/$sub" "submodule ok (updated)"
    else
      sub_warn "$name/$sub" "failed"
    fi
  done
}

: > "$LOG_FILE"
log "sync-repos" "$(date '+%Y-%m-%d %H:%M:%S')"

for repo in "$CODE_DIR"/*/*/.git; do
  [ -d "$repo" ] || continue
  dir=$(dirname "$repo")
  name=${dir#"$CODE_DIR"/}

  branch=$(git -C "$dir" symbolic-ref \
    refs/remotes/origin/HEAD 2>/dev/null |
    sed 's@^refs/remotes/origin/@@')
  branch=${branch:-main}

  git -C "$dir" fetch origin --quiet 2>/dev/null

  current=$(git -C "$dir" branch --show-current 2>/dev/null)
  if [ "$current" = "$branch" ]; then
    if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
      log "$name" "ok (pulled)"
      ok_count=$((ok_count + 1))
      sync_submodules "$dir" "$name"
    else
      log "$name" "skipped (dirty or diverged)"
      echo "$(date '+%Y-%m-%d %H:%M') $name: skipped (dirty or diverged)" \
        >> "$ERR_FILE"
      skip_count=$((skip_count + 1))
    fi
  else
    if git -C "$dir" fetch origin \
        "$branch:$branch" 2>/dev/null; then
      log "$name" "ok"
      ok_count=$((ok_count + 1))
    else
      log "$name" "skipped"
      echo "$(date '+%Y-%m-%d %H:%M') $name: skipped" >> "$ERR_FILE"
      skip_count=$((skip_count + 1))
    fi
  fi
done

log "---" ""
log "done" "$ok_count ok, $skip_count skipped"
log "finished" "$(date '+%Y-%m-%d %H:%M:%S')"
