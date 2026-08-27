#!/bin/bash
# Update Claude Code plugins from marketplaces.
# Runs setup.sh --update to refresh marketplace cache and pull latest versions.

set -euo pipefail

SETUP="$HOME/.claude/setup.sh"
LOCK_DIR="$HOME/.local/share/update-claude-plugins"
LOCK_FILE="$LOCK_DIR/lock"
mkdir -p "$LOCK_DIR"

# One run at a time -- a stuck marketplace fetch would otherwise pile up.
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

if [ ! -f "$SETUP" ]; then
  echo "setup.sh not found at $SETUP"
  exit 1
fi

bash "$SETUP" --update
