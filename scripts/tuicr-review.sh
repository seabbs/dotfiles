#!/usr/bin/env bash
# Review a GitHub PR in tuicr, from gh-dash or a shell.
# Usage: tuicr-review.sh <owner/repo> <pr-number> [repo-path]
#
# tuicr resolves the forge repo from the checkout it runs in, so it needs a
# clone. gh-dash passes {{.RepoPath}} from its repoPaths mapping, which is
# empty for repos outside the mapped orgs; those fall back to a cached clone.
#
# gh-dash hands the terminal to this command, so tuicr takes over the gh-dash
# popup and hands it back on quit. Do not open a tmux popup here: tmux allows
# only one popup per client and gh-dash is already running in one.
set -euo pipefail

REPO="${1:-}"
PR="${2:-}"
REPO_PATH="${3:-}"
CACHE_DIR="$HOME/.cache/tuicr-review"

if [ -z "$REPO" ] || [ -z "$PR" ]; then
  echo "Usage: tuicr-review.sh <owner/repo> <pr-number> [repo-path]" >&2
  exit 1
fi

if ! command -v tuicr >/dev/null 2>&1; then
  echo "tuicr is not installed. Run cli/setup.sh." >&2
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

# tuicr shells out to $EDITOR for `:edit`, and to gh for `:submit`. The popup
# runs a non-interactive shell that never sources .zshrc, so set EDITOR here.
export EDITOR="${EDITOR:-nvim}"
cd "$target"
exec tuicr pr "$PR"
