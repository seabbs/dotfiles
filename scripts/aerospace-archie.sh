#!/bin/bash
# alt-a: focus the existing archie window, or open a new ghostty window that
# connects to archie via mosh (no local tmux, so no nesting). Switch back with
# AeroSpace (e.g. alt-/ focus-back-and-forth). The archie window's title shows
# the archie host (via tmux set-titles), so we match ghostty windows by it.
set -euo pipefail
AS=/opt/homebrew/bin/aerospace
GH=/Applications/Ghostty.app/Contents/MacOS/ghostty

win=$("$AS" list-windows --all 2>/dev/null \
  | grep -i ghostty | grep -i archie | head -1 | cut -d'|' -f1 | tr -d ' ')

if [ -n "${win:-}" ]; then
  "$AS" focus --window-id "$win"
else
  "$GH" -e bash -c 'export PATH="/opt/homebrew/bin:$PATH"; mosh archie'
fi
