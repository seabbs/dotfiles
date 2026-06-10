#!/bin/bash
# tmux status segment: show archie's agent-session monitor in the local status
# bar, next to the home agents. Non-blocking: prints a cached value instantly
# and refreshes it in the background, so the status bar never waits on ssh.
# No-op on archie itself (it already shows its own agents directly).
[ "$(hostname -s)" = "archie" ] && exit 0

cache="$HOME/.agent/archie-status"
lock="$cache.lock"
mkdir -p "$(dirname "$cache")"

# Print the last-known value immediately, labelled so it is clearly archie.
if [ -s "$cache" ]; then
  printf '#[fg=#f5a97f]archie#[default] %s ' "$(cat "$cache")"
fi

# Refresh in the background (lock prevents pile-up); multiplexed ssh keeps it
# fast. ConnectTimeout bounds it if archie is unreachable.
if mkdir "$lock" 2>/dev/null; then
  (
    out=$(ssh -o ConnectTimeout=2 -o BatchMode=yes archie \
      '~/code/seabbs/dotfiles/scripts/agent-sessions.sh --status' 2>/dev/null) \
      || out=""
    printf '%s' "$out" >"$cache"
    rmdir "$lock"
  ) >/dev/null 2>&1 &
fi
exit 0
