#!/bin/bash
# Toggle the active tmux client between the most-recent home session and the
# most-recent hub session (e.g. archie). Invoked above tmux (AeroSpace) so it
# works even while a hub session has the outer tmux dormant. If in home with no
# hub open yet, it opens the first HUB_HOSTS host as a hub session.
set -euo pipefail
TMUX=/opt/homebrew/bin/tmux

client=$("$TMUX" list-clients -F '#{client_activity} #{client_name}' 2>/dev/null \
  | sort -rn | head -1 | cut -d' ' -f2)
[ -z "$client" ] && exit 0

cur=$("$TMUX" display-message -c "$client" -p '#{session_name}')
cur_hub=$("$TMUX" display-message -c "$client" -p '#{@hub}')
sessions=$("$TMUX" list-sessions \
  -F '#{session_activity}|#{session_name}|#{@hub}' 2>/dev/null)

if [ -n "$cur_hub" ]; then
  # In a hub -> jump to the most-recent non-hub (home) session.
  target=$(printf '%s\n' "$sessions" | awk -F'|' '$3!="1"' \
    | sort -rn -t'|' -k1 | awk -F'|' -v c="$cur" '$2!=c {print $2; exit}')
else
  # In home -> jump to the most-recent hub session, or open one on demand.
  target=$(printf '%s\n' "$sessions" | awk -F'|' '$3=="1"' \
    | sort -rn -t'|' -k1 | awk -F'|' -v c="$cur" '$2!=c {print $2; exit}')
  if [ -z "${target:-}" ]; then
    hub=$(echo "${HUB_HOSTS:-archie}" | awk '{print $1}')
    "$TMUX" new-session -d -s "$hub" "/bin/zsh -lc 'mosh $hub'"
    "$TMUX" set-option -t "$hub" @hub 1
    "$TMUX" set-option -t "$hub" status off
    target="$hub"
  fi
fi

[ -n "${target:-}" ] && "$TMUX" switch-client -c "$client" -t "=$target"
