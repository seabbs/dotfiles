#!/bin/bash
# tmux status segment: show archie's agent-session monitor in the local status
# bar, next to the home agents. Non-blocking: prints a cached value instantly
# and refreshes in the background, so the status bar never waits on ssh.
#
# The background refresh is THROTTLED (every ~10s) independently of the 5s
# status interval, so the local monitor stays responsive while archie is polled
# half as often (kinder on battery / the Tailscale link). The one poll also
# warms the cross-machine finder caches (sessions + agents), so prefix+f /
# prefix+a open instantly with fresh archie state from the same ssh.
#
# No-op on archie itself (it already shows its own agents directly).
[ "$(hostname -s)" = "archie" ] && exit 0

HUB=archie
THROTTLE=10
R='~/code/seabbs/dotfiles/scripts/agent-sessions.sh'
SC="$HOME/.agent/archie-status"           # status segment cache
FC="$HOME/.cache/sessionizer"             # finder caches (sessions/agents)
mkdir -p "$(dirname "$SC")" "$FC" 2>/dev/null

# Print the last-known status immediately, labelled so it is clearly archie.
[ -s "$SC" ] && printf '#[fg=#f5a97f]archie#[default] %s ' "$(cat "$SC")"

# Throttle: only poll archie if the status cache is older than THROTTLE seconds.
now=$(date +%s)
mtime=$(stat -f %m "$SC" 2>/dev/null || echo 0)
[ $(( now - mtime )) -lt "$THROTTLE" ] && exit 0

# One background refresh warms all three caches over the multiplexed ssh. The
# lock prevents pile-up; the ssh options bound it if archie is slow/unreachable
# (a degraded home uplink can make even a connect take several seconds, so the
# timeout is generous but ServerAlive still kills a truly dead link). Atomic
# writes (unique .tmp per process) so a concurrent finder refresh of the same
# cache file can never see a half-written file; any temp left by a failed ssh is
# swept at the end of the run so they cannot accumulate.
SSH_OPTS=(-o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2
          -o BatchMode=yes)
if mkdir "$SC.lock" 2>/dev/null; then
  (
    t=$$
    ssh "${SSH_OPTS[@]}" "$HUB" "$R --status" \
      >"$SC.$t" 2>/dev/null && mv "$SC.$t" "$SC"
    ssh "${SSH_OPTS[@]}" "$HUB" \
      "tmux list-sessions -F '#{session_activity}|#{session_name}|#{@hub}'" \
      >"$FC/$HUB-sessions.$t" 2>/dev/null \
      && mv "$FC/$HUB-sessions.$t" "$FC/$HUB-sessions"
    ssh "${SSH_OPTS[@]}" "$HUB" "$R --list" \
      >"$FC/$HUB-agents-all.$t" 2>/dev/null \
      && mv "$FC/$HUB-agents-all.$t" "$FC/$HUB-agents-all"
    rm -f "$SC.$t" "$FC/$HUB-sessions.$t" "$FC/$HUB-agents-all.$t"
    rmdir "$SC.lock"
  ) >/dev/null 2>&1 &
fi
exit 0
