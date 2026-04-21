#!/usr/bin/env bash
# Open a new tmux split with diffview.nvim showing current changes.
# Usage:
#   show-diff.sh                 # working tree vs HEAD (uncommitted)
#   show-diff.sh main...HEAD     # branch diff vs main
#   show-diff.sh HEAD~3..HEAD    # arbitrary DiffviewOpen rev range
set -euo pipefail

if [ -z "${TMUX:-}" ]; then
  echo "show-diff: not inside tmux" >&2
  exit 1
fi

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "show-diff: not in a git repo" >&2
  exit 1
}

range="${1:-}"
if [ -n "$range" ]; then
  nvim_cmd="nvim -c 'DiffviewOpen ${range}'"
else
  nvim_cmd="nvim -c DiffviewOpen"
fi

tmux split-window -h -c "$repo" "$nvim_cmd"
