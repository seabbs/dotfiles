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
mkdir -p "$LOG_DIR"

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

ok_count=0
skip_count=0

log() {
  printf "%-50s %s\n" "$1" "$2" >> "$LOG_FILE"
  $INTERACTIVE && printf "%-50s %s\n" "$1" "$2"
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
