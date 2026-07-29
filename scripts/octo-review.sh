#!/usr/bin/env bash
# Open a GitHub PR in octo.nvim from gh-dash.
# Usage: octo-review.sh <owner/repo> <pr-number> [repo-path]
#
# Companion to tuicr-review.sh, not a replacement: tuicr (C) is for reading
# the diff, octo (E) is for editing PR metadata and threading comments.
#
# octo resolves the forge repo from the git remote of the directory nvim
# starts in, so it needs a clone. gh-dash passes {{.RepoPath}} from its
# repoPaths mapping, which is empty for repos outside the mapped orgs; those
# fall back to a cached clone. The cache is shared with tuicr-review.sh so a
# repo is only ever cloned once.
#
# Unlike tuicr, this opens a new tmux window rather than taking over the
# gh-dash popup: an editor session should outlive the popup it was launched
# from, and quitting nvim should not drop you back into the dash mid-edit.
set -euo pipefail

REPO="${1:-}"
PR="${2:-}"
REPO_PATH="${3:-}"
CACHE_DIR="$HOME/.cache/tuicr-review"

if [ -z "$REPO" ] || [ -z "$PR" ]; then
  echo "Usage: octo-review.sh <owner/repo> <pr-number> [repo-path]" >&2
  exit 1
fi

# Expand a leading ~ that gh-dash's repoPaths mapping passes through literally.
REPO_PATH="${REPO_PATH/#\~/$HOME}"

if [ -n "$REPO_PATH" ] && [ -d "$REPO_PATH/.git" ]; then
  target="$REPO_PATH"
else
  target="$CACHE_DIR/$REPO"
  if [ ! -d "$target/.git" ]; then
    echo "No local checkout for $REPO; cloning to $target..."
    mkdir -p "$(dirname "$target")"
    gh repo clone "$REPO" "$target" -- --filter=blob:none
  fi
fi

# No -c ":silent": a failing Octo command should say so rather than leave an
# empty buffer. octo picks up GH_TOKEN itself via the gh_env in its config.
if [ -n "${TMUX:-}" ]; then
  exec tmux new-window -c "$target" -n "octo-$PR" \
    "nvim -c 'Octo pr edit $PR'"
else
  cd "$target"
  exec nvim -c "Octo pr edit $PR"
fi
