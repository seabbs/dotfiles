#!/usr/bin/env bash
# Open a new tmux split with diffview.nvim showing current changes.
#
# Usage:
#   show-diff.sh                    # working tree vs HEAD (uncommitted)
#   show-diff.sh last               # just the last commit (HEAD~1..HEAD)
#   show-diff.sh last 3             # last 3 commits (HEAD~3..HEAD)
#   show-diff.sh pr                 # current branch vs its PR base
#   show-diff.sh main...HEAD        # explicit rev range
#   show-diff.sh HEAD~3..HEAD       # any valid DiffviewOpen range
set -euo pipefail

if [ -z "${TMUX:-}" ]; then
  echo "show-diff: not inside tmux" >&2
  exit 1
fi

repo=$(git rev-parse --show-toplevel 2>/dev/null) || {
  echo "show-diff: not in a git repo" >&2
  exit 1
}

resolve_range() {
  case "${1:-}" in
    "")
      echo ""
      ;;
    last)
      local n="${2:-1}"
      if ! [[ "$n" =~ ^[0-9]+$ ]] || [ "$n" -lt 1 ]; then
        echo "show-diff: 'last' needs a positive integer, got '$n'" >&2
        return 1
      fi
      echo "HEAD~${n}..HEAD"
      ;;
    pr)
      local base
      base=$(gh pr view --json baseRefName -q .baseRefName 2>/dev/null) || {
        echo "show-diff: no PR found for this branch" >&2
        return 1
      }
      echo "origin/${base}...HEAD"
      ;;
    *)
      # Numeric shorthand: `show-diff 3` → last 3 commits
      if [[ "$1" =~ ^[0-9]+$ ]]; then
        echo "HEAD~${1}..HEAD"
      else
        echo "$1"
      fi
      ;;
  esac
}

range=$(resolve_range "$@")

if [ -n "$range" ]; then
  nvim_cmd="nvim -c 'DiffviewOpen ${range}'"
else
  nvim_cmd="nvim -c DiffviewOpen"
fi

tmux split-window -h -c "$repo" "$nvim_cmd"
