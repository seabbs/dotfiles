#!/bin/bash
# agent-sessions.sh — tmux popup: list and switch to AI CLI agent sessions
# Reads state from ~/.agent/session-monitor/
#
# Usage:
#   agent-sessions.sh            interactive fzf picker
#   agent-sessions.sh --list     list sessions (for scripting)
#   agent-sessions.sh --count    count active sessions
#   agent-sessions.sh --status   tmux status bar segment
#   agent-sessions.sh --clean    remove stale entries
#   agent-sessions.sh --switch ID  switch to session by ID

STATUS_DIR="$HOME/.agent/session-monitor"

# Remote hub hosts to span (space-separated ssh aliases), overridable via env.
HUB_HOSTS="${HUB_HOSTS:-archie}"
HOST_STATE="$HOME/.cache/agent-host"
mkdir -p "$HOME/.cache" 2>/dev/null
RA='~/code/seabbs/dotfiles/scripts/agent-sessions.sh'
host_scope() { cat "$HOST_STATE" 2>/dev/null || echo all; }
SELF_HOST="$(hostname -s)"
self_host() { printf '%s' "$SELF_HOST"; }
# Cache a remote command's output (instant), refresh in background. See
# sessionizer.sh for the rationale.
CACHE_DIR="$HOME/.cache/sessionizer"
mkdir -p "$CACHE_DIR" 2>/dev/null
remote_cached() {
  local host="$1" key="$2" cmd="$3"
  local cache="$CACHE_DIR/$host-$key" lock
  [ -f "$cache" ] && cat "$cache"
  lock="$cache.lock"
  if mkdir "$lock" 2>/dev/null; then
    # Bound the refresh: a degraded link must not hang holding the lock and
    # block every later refresh. ServerAlive kills a dead connection quickly.
    ( ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$host" "$cmd" >"$cache.tmp" 2>/dev/null && mv "$cache.tmp" "$cache"
      rm -f "$cache.tmp"; rmdir "$lock" ) >/dev/null 2>&1 &
  fi
}
remote_hubs() {
  local h
  for h in $HUB_HOSTS; do [ "$h" != "$(self_host)" ] && echo "$h"; done
}
# Mark a local session as a dormant hub gateway (passthrough + hidden bar).
flag_hub() {
  # Prefix stays active so prefix+f/a here run the HOME finder (hub sessions
  # are mac tmux sessions); status off hides the outer bar.
  tmux set-option -t "$1" @hub 1
  tmux set-option -t "$1" status off
}

# Agents merged across home + hub hosts, tagged [home]/[hub], scope-aware.
list_hosts() {
  local filter="${1:-}" scope h; scope="$(host_scope)"
  if [ "$scope" = "all" ] || [ "$scope" = "home" ]; then
    list_sessions "$filter" | sed 's/^/[home] /'
  fi
  for h in $(remote_hubs); do
    if [ "$scope" = "all" ] || [ "$scope" = "$h" ]; then
      remote_cached "$h" "agents-${filter:-all}" "$RA --list $filter" \
        | sed "s/^/[$h] /"
    fi
  done
}

clean_stale() {
  [ -d "$STATUS_DIR" ] || return 0
  local files
  files=("$STATUS_DIR"/*.json)
  [ -f "${files[0]}" ] || return 0
  local panes
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  while IFS=$'\t' read -r filepath pane; do
    [ -z "$pane" ] && continue
    if ! printf '%s\n' "$panes" \
        | grep -qF "$pane"; then
      rm -f "$filepath"
    fi
  done < <(
    jq -r '[input_filename, .tmux_pane // ""] | @tsv' "${files[@]}"
  )
}

list_sessions() {
  local filter="${1:-}"
  [ -d "$STATUS_DIR" ] || return 0
  local files
  files=("$STATUS_DIR"/*.json)
  [ -f "${files[0]}" ] || return 0
  local now panes
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)

  # Single jq call reads every session file in one fork.
  jq -r '[input_filename, .state, .project, .tmux_session,
          .tmux_window, .updated,
          .tmux_pane // "", .agent // "claude"] | @tsv' "${files[@]}" |
  while IFS=$'\t' read -r filepath state project ts tw updated pane_id agent; do
    local sid age age_str
    sid=$(basename "$filepath" .json)
    age=$(( now - updated ))

    # Stale detection: pane gone or idle/waiting over 24h
    if [ -n "$pane_id" ] && [ -n "$panes" ]; then
      if ! printf '%s\n' "$panes" \
          | grep -qF "$pane_id"; then
        state="stale"
      fi
    fi
    if [ "$age" -gt 86400 ] \
        && [ "$state" != "running" ]; then
      state="stale"
    fi

    # Apply filter
    if [ -n "$filter" ] && [ "$filter" != "$state" ]; then
      continue
    fi

    # State indicator
    local icon
    case "$state" in
      running)    icon="●" ;;
      waiting)    icon="◐" ;;
      idle)       icon="○" ;;
      permission) icon="▲" ;;
      stale)      icon="✗" ;;
      *)          icon="?" ;;
    esac

    # Age since last update
    if [ "$age" -lt 60 ]; then
      age_str="${age}s"
    elif [ "$age" -lt 3600 ]; then
      age_str="$(( age / 60 ))m"
    else
      age_str="$(( age / 3600 ))h"
    fi

    # Tmux location
    local location="—"
    if [ -n "$ts" ] && [ "$ts" != "" ]; then
      location="$ts:$tw"
    fi

    # Agent label
    local agent_label
    case "$agent" in
      claude) agent_label="C" ;;
      gemini) agent_label="G" ;;
      *)      agent_label="?" ;;
    esac

    # Sort: permission > running > waiting > idle > stale
    # Within same state, sort by recency (most recent first)
    local sort_key
    case "$state" in
      permission) sort_key=1 ;;
      running)    sort_key=2 ;;
      waiting)    sort_key=3 ;;
      idle)       sort_key=4 ;;
      stale)      sort_key=5 ;;
      *)          sort_key=9 ;;
    esac

    # Pad updated to fixed width for secondary sort (descending)
    local inv_updated=$(( 9999999999 - updated ))

    printf "%d\t%010d\t%s [%s] %-10s\t%-20s\t%-15s\t%s\t%s\n" \
      "$sort_key" "$inv_updated" "$icon" "$agent_label" "$state" \
      "$project" "$location" "$age_str" "$sid"
  done | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
}

count_sessions() {
  [ -d "$STATUS_DIR" ] || { echo 0; return; }
  local files
  files=("$STATUS_DIR"/*.json)
  [ -f "${files[0]}" ] || { echo 0; return; }
  local count=0 permission=0
  while read -r state; do
    count=$(( count + 1 ))
    [ "$state" = "permission" ] && permission=$(( permission + 1 ))
  done < <(jq -r '.state' "${files[@]}")
  if [ "$permission" -gt 0 ]; then
    printf "%d (▲%d)" "$count" "$permission"
  else
    printf "%d" "$count"
  fi
}

switch_to() {
  local sid="$1"
  local f="$STATUS_DIR/$sid.json"
  [ -f "$f" ] || exit 1

  local pane ts tw
  IFS=$'\t' read -r pane ts tw < <(
    jq -r '[.tmux_pane, .tmux_session, .tmux_window] | @tsv' "$f"
  )

  [ -z "$ts" ] && exit 1
  tmux switch-client -t "=$ts"
  tmux select-window -t "=$ts:$tw"
  tmux select-pane -t "$pane"
}

status_bar() {
  [ -d "$STATUS_DIR" ] || return 0
  local files
  files=("$STATUS_DIR"/*.json)
  [ -f "${files[0]}" ] || return 0
  local now panes
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  local total=0 running=0 permission=0 waiting=0 idle=0
  while IFS=$'\t' read -r state updated pane_id; do
    local age=$(( now - updated ))
    # Skip stale: pane gone or stale over 24h
    if [ -n "$pane_id" ] && [ -n "$panes" ]; then
      printf '%s\n' "$panes" \
        | grep -qF "$pane_id" || continue
    fi
    [ "$age" -gt 86400 ] \
      && [ "$state" != "running" ] && continue
    total=$(( total + 1 ))
    case "$state" in
      running)    running=$(( running + 1 )) ;;
      permission) permission=$(( permission + 1 )) ;;
      waiting)    waiting=$(( waiting + 1 )) ;;
      idle)       idle=$(( idle + 1 )) ;;
    esac
  done < <(jq -r '[.state, .updated, .tmux_pane // ""] | @tsv' "${files[@]}")
  [ "$total" -eq 0 ] && return 0

  # Build segments
  local parts=""
  if [ "$permission" -gt 0 ]; then
    parts="#[fg=#f7768e,bold]▲${permission}"
  fi
  if [ "$running" -gt 0 ]; then
    [ -n "$parts" ] && parts="$parts "
    parts="${parts}#[fg=#9ece6a]●${running}"
  fi
  if [ "$waiting" -gt 0 ]; then
    [ -n "$parts" ] && parts="$parts "
    parts="${parts}#[fg=#a9b1d6]◐${waiting}"
  fi
  if [ "$idle" -gt 0 ]; then
    [ -n "$parts" ] && parts="$parts "
    parts="${parts}#[fg=#565f89]○${idle}"
  fi
  printf "%s#[default]" "$parts"
}

purge_stale() {
  [ -d "$STATUS_DIR" ] || return 0
  local files
  files=("$STATUS_DIR"/*.json)
  [ -f "${files[0]}" ] || {
    printf "Purged 0 stale session(s)\n"; return 0;
  }
  local now panes count=0
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  while IFS=$'\t' read -r filepath pane state updated; do
    local age=$(( now - updated )) remove=false
    # Pane gone
    if [ -n "$pane" ] && [ -n "$panes" ]; then
      printf '%s\n' "$panes" \
        | grep -qF "$pane" || remove=true
    fi
    # Idle/waiting over 24h
    if [ "$age" -gt 86400 ] \
        && [ "$state" != "running" ]; then
      remove=true
    fi
    if [ "$remove" = true ]; then
      rm -f "$filepath"
      count=$(( count + 1 ))
    fi
  done < <(
    jq -r '[input_filename, .tmux_pane // "",
            .state, .updated] | @tsv' "${files[@]}"
  )
  printf "Purged %d stale session(s)\n" "$count"
}

# Sub-commands
case "${1:-}" in
  --list)   list_sessions "$2"; exit 0 ;;
  --list-hosts) list_hosts "$2"; exit 0 ;;
  --cycle-host)
    cur="$(host_scope)"
    order=(all home $(remote_hubs))
    n=all
    for i in "${!order[@]}"; do
      [ "${order[$i]}" = "$cur" ] && \
        n="${order[$(( (i + 1) % ${#order[@]} ))]}" && break
    done
    echo "$n" > "$HOST_STATE"
    printf 'change-prompt(%s ❯ )+reload(%s --list-hosts)' "$n" "$0"
    exit 0
    ;;
  --count)  count_sessions; exit 0 ;;
  --status) status_bar; exit 0 ;;
  --clean)  clean_stale; exit 0 ;;
  --purge)
    # Purge stale agents locally and on every hub, then refresh each hub's
    # cache so the purged entries disappear from the picker immediately.
    purge_stale
    for _h in $(remote_hubs); do
      ssh "$_h" "$RA --purge" 2>/dev/null
      rm -f "$CACHE_DIR/$_h"-agents-* 2>/dev/null
      ssh "$_h" "$RA --list" >"$CACHE_DIR/$_h-agents-all" 2>/dev/null
    done
    exit 0
    ;;
  --switch) switch_to "$2"; exit 0 ;;
  --target)
    [ -f "$STATUS_DIR/$2.json" ] \
      && jq -r '.tmux_session // empty' "$STATUS_DIR/$2.json"
    exit 0
    ;;
esac

# Interactive: clean stale, then fzf picker
clean_stale

echo all > "$HOST_STATE"
sessions=$(list_hosts)

if [ -z "$sessions" ]; then
  printf "\n  No active agent sessions.\n"
  printf "  Sessions are tracked via CLI agent hooks.\n\n"
  read -r -n 1
  exit 0
fi

selected=$(printf '%s\n' "$sessions" | fzf \
  --no-sort \
  --delimiter=$'\t' \
  --with-nth=1..4 \
  --border-label ' agent sessions ' \
  --prompt ' all  ' \
  --header $'C-r host  C-a all  C-p ▲perm  C-o ●run  C-w ◐wait  C-i ○idle  C-x ✗stale  C-d purge' \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-r:transform($0 --cycle-host)" \
  --bind "ctrl-a:change-prompt( all  )+reload($0 --list-hosts)" \
  --bind "ctrl-p:change-prompt( ▲ perm  )+reload($0 --list-hosts permission)" \
  --bind "ctrl-o:change-prompt( ● run  )+reload($0 --list-hosts running)" \
  --bind "ctrl-w:change-prompt( ◐ wait  )+reload($0 --list-hosts waiting)" \
  --bind "ctrl-i:change-prompt( ○ idle  )+reload($0 --list-hosts idle)" \
  --bind "ctrl-x:change-prompt( ✗ stale  )+reload($0 --list-hosts stale)" \
  --bind "ctrl-d:execute-silent($0 --purge)+reload($0 --list-hosts)" \
)

[ -z "$selected" ] && exit 0

# Route by host tag ([home]/[hub]); sid is the last tab-separated field.
host_tag=$(printf '%s' "$selected" | sed -E 's/^\[([^]]+)\].*/\1/')
sid=$(printf '%s' "$selected" | awk -F'\t' '{print $NF}')
if [ "$host_tag" = "home" ]; then
  switch_to "$sid"
else
  # Remote hub: nested mosh session, created on demand (flagged @hub).
  if tmux has-session -t "=$host_tag" 2>/dev/null; then
    ssh "$host_tag" "$RA --switch '$sid'" 2>/dev/null || true
  else
    # First time: select the agent's window on the host, then attach that
    # session directly via mosh so we land on it, not the host's home session.
    tsession=$(ssh "$host_tag" "$RA --target '$sid'" 2>/dev/null)
    ssh "$host_tag" "$RA --switch '$sid'" 2>/dev/null || true
    tmux new-session -d -s "$host_tag" \
      "/bin/zsh -lc 'mosh --predict=experimental $host_tag -- tmux attach -t ${tsession:-home}'"
    flag_hub "$host_tag"
  fi
  tmux switch-client -t "=$host_tag"
fi
