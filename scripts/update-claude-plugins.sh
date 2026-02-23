#!/bin/bash
# Update Claude Code plugins from marketplaces.
# Runs setup.sh --update to refresh marketplace cache and pull latest versions.

set -euo pipefail

SETUP="$HOME/.claude/setup.sh"

if [ ! -f "$SETUP" ]; then
  echo "setup.sh not found at $SETUP"
  exit 1
fi

bash "$SETUP" --update
