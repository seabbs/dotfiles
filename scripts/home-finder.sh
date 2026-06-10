#!/bin/bash
# Open a home tmux finder popup (windows via sessionizer, or agents) from
# anywhere — even while focused on a remote machine's window or while keys are
# passing through to a nested session. Bound to dedicated keys via AeroSpace,
# which catches them above tmux so they always fire regardless of prefix state.
set -euo pipefail
TMUX=/opt/homebrew/bin/tmux
AS=/opt/homebrew/bin/aerospace
DOT="$HOME/code/seabbs/dotfiles"

case "${1:-windows}" in
  agents) script="$DOT/scripts/agent-sessions.sh" ;;
  *)      script="$DOT/scripts/sessionizer.sh" ;;
esac

# Focus the home ghostty window (the one not showing a remote host), so the
# popup is visible and the finder switches the right client.
win=$("$AS" list-windows --all 2>/dev/null \
  | grep -i ghostty | grep -iv archie | head -1 | cut -d'|' -f1 | tr -d ' ')
[ -n "$win" ] && "$AS" focus --window-id "$win"

# Show the finder popup on the local tmux client (whatever session it is on).
client=$("$TMUX" list-clients -F '#{client_name}' 2>/dev/null | head -1)
[ -n "$client" ] && "$TMUX" display-popup -c "$client" -w 60% -h 60% -E "$script"
