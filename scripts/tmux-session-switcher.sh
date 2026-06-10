#!/bin/bash
# Popup session switcher: fuzzy-pick a tmux session (or the remote "archie"
# hub) and switch to it, creating the archie mosh session on demand. Meant to
# run inside a tmux display-popup, alongside the f (windows) / a (agents)
# popups.
set -euo pipefail

current=$(tmux display-message -p '#{session_name}')

# Existing local sessions, plus a synthetic archie entry if it is not already
# running, so the hub is reachable even before its session exists.
sessions=$(tmux list-sessions -F '#{session_name}' 2>/dev/null || true)
if ! printf '%s\n' "$sessions" | grep -qx archie; then
  sessions=$(printf '%s\narchie (connect)\n' "$sessions")
fi

choice=$(printf '%s\n' "$sessions" | grep -vx "$current" \
  | sed '/^$/d' | fzf --prompt="session> " --height=100% --reverse) || exit 0

choice=${choice%% (connect)}

if [ "$choice" = "archie" ] && ! tmux has-session -t archie 2>/dev/null; then
  # On archie itself there is nothing to connect to; otherwise start mosh.
  if [ "$(hostname -s)" != "archie" ]; then
    tmux new-session -d -s archie "/bin/zsh -lc 'mosh archie'"
  fi
fi

tmux switch-client -t "$choice"
