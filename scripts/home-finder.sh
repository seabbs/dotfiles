#!/bin/bash
# Open the HOME tmux finder popup (windows via sessionizer, or agents) from
# anywhere — including from within a nested hub session, where it still pops
# the home finder so you can jump home or to any hub. Bound to alt-f / alt-a
# via AeroSpace, which fires above tmux, so it works regardless of whether a
# hub session has the outer tmux passing keys through.
set -euo pipefail
TMUX=/opt/homebrew/bin/tmux
DOT="$HOME/code/seabbs/dotfiles"

case "${1:-windows}" in
  agents) script="$DOT/scripts/agent-sessions.sh" ;;
  *)      script="$DOT/scripts/sessionizer.sh" ;;
esac

# Pop the finder on the most-recently-used local (home) tmux client, even if it
# is currently viewing a nested hub session.
client=$("$TMUX" list-clients -F '#{client_activity} #{client_name}' 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2)
[ -n "$client" ] && "$TMUX" display-popup -c "$client" -w 60% -h 60% -E "$script"
