#!/bin/bash
# claude-sessions.sh — tmux popup: list and switch to Claude sessions
# Reads state from ~/.claude/session-monitor/
#
# Usage:
#   claude-sessions.sh            interactive fzf picker
#   claude-sessions.sh --list     list sessions (for scripting)
#   claude-sessions.sh --count    count active sessions
#   claude-sessions.sh --status   tmux status bar segment
#   claude-sessions.sh --clean    remove stale entries
#   claude-sessions.sh --switch ID  switch to session by ID

STATUS_DIR="$HOME/.claude/session-monitor"

clean_stale() {
  [ -d "$STATUS_DIR" ] || return 0
  local panes
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  for f in "$STATUS_DIR"/*.json; do
    [ -f "$f" ] || continue
    local pane
    pane=$(jq -r '.tmux_pane // empty' "$f")
    [ -z "$pane" ] && continue
    if ! printf '%s\n' "$panes" \
        | grep -qF "$pane"; then
      rm -f "$f"
    fi
  done
}

list_sessions() {
  local filter="${1:-}"
  [ -d "$STATUS_DIR" ] || return 0
  local now panes
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)

  for f in "$STATUS_DIR"/*.json; do
    [ -f "$f" ] || continue

    local data state project ts tw updated sid
    data=$(cat "$f")
    state=$(printf '%s' "$data" | jq -r '.state')
    project=$(printf '%s' "$data" | jq -r '.project')
    ts=$(printf '%s' "$data" | jq -r '.tmux_session')
    tw=$(printf '%s' "$data" | jq -r '.tmux_window')
    updated=$(printf '%s' "$data" | jq -r '.updated')
    sid=$(basename "$f" .json)

    # Stale detection: pane gone or idle/waiting over 24h
    local pane_id age
    pane_id=$(printf '%s' "$data" | jq -r '.tmux_pane // empty')
    age=$(( now - updated ))
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
      stale)       icon="✗" ;;
      *)          icon="?" ;;
    esac

    # Age since last update
    local age=$(( now - updated ))
    local age_str
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

    # Sort: permission > running > waiting > idle > stale
    # Within same state, sort by recency (most recent first)
    local sort_key
    case "$state" in
      permission) sort_key=1 ;;
      running)    sort_key=2 ;;
      waiting)    sort_key=3 ;;
      idle)       sort_key=4 ;;
      stale)       sort_key=5 ;;
      *)          sort_key=9 ;;
    esac

    # Pad updated to fixed width for secondary sort (descending)
    local inv_updated=$(( 9999999999 - updated ))

    printf "%d\t%010d\t%s %-10s\t%-20s\t%-15s\t%s\t%s\n" \
      "$sort_key" "$inv_updated" "$icon" "$state" \
      "$project" "$location" "$age_str" "$sid"
  done | sort -t$'\t' -k1,1n -k2,2n | cut -f3-
}

count_sessions() {
  [ -d "$STATUS_DIR" ] || { echo 0; return; }
  local count=0
  local permission=0
  for f in "$STATUS_DIR"/*.json; do
    [ -f "$f" ] || continue
    count=$(( count + 1 ))
    local state
    state=$(jq -r '.state' "$f")
    [ "$state" = "permission" ] && permission=$(( permission + 1 ))
  done
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

  local data pane ts tw
  data=$(cat "$f")
  pane=$(printf '%s' "$data" | jq -r '.tmux_pane')
  ts=$(printf '%s' "$data" | jq -r '.tmux_session')
  tw=$(printf '%s' "$data" | jq -r '.tmux_window')

  [ -z "$ts" ] && exit 1
  tmux switch-client -t "=$ts"
  tmux select-window -t "=$ts:$tw"
  tmux select-pane -t "$pane"
}

status_bar() {
  [ -d "$STATUS_DIR" ] || return 0
  local now panes
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  local total=0 running=0 permission=0 waiting=0 idle=0
  for f in "$STATUS_DIR"/*.json; do
    [ -f "$f" ] || continue
    local state updated pane_id age
    state=$(jq -r '.state' "$f")
    updated=$(jq -r '.updated' "$f")
    pane_id=$(jq -r '.tmux_pane // empty' "$f")
    age=$(( now - updated ))
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
  done
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
  local now panes count=0
  now=$(date +%s)
  panes=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)
  for f in "$STATUS_DIR"/*.json; do
    [ -f "$f" ] || continue
    local pane state updated age remove=false
    pane=$(jq -r '.tmux_pane // empty' "$f")
    state=$(jq -r '.state' "$f")
    updated=$(jq -r '.updated' "$f")
    age=$(( now - updated ))
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
      rm -f "$f"
      count=$(( count + 1 ))
    fi
  done
  printf "Purged %d stale session(s)\n" "$count"
}

# Sub-commands
case "${1:-}" in
  --list)   list_sessions "$2"; exit 0 ;;
  --count)  count_sessions; exit 0 ;;
  --status) status_bar; exit 0 ;;
  --clean)  clean_stale; exit 0 ;;
  --purge)  purge_stale; exit 0 ;;
  --switch) switch_to "$2"; exit 0 ;;
esac

# Interactive: clean stale, then fzf picker
clean_stale

sessions=$(list_sessions)

if [ -z "$sessions" ]; then
  printf "\n  No active Claude sessions.\n"
  printf "  Sessions are tracked via Claude Code hooks.\n\n"
  read -r -n 1
  exit 0
fi

selected=$(printf '%s\n' "$sessions" | fzf \
  --no-sort \
  --delimiter=$'\t' \
  --with-nth=1..4 \
  --border-label ' claude sessions ' \
  --prompt ' all  ' \
  --header $'C-r refresh  C-a all  C-p ▲perm  C-o ●run  C-w ◐wait  C-i ○idle  C-x ✗stale  C-d purge' \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-r:reload($0 --list)" \
  --bind "ctrl-a:change-prompt( all  )+reload($0 --list)" \
  --bind "ctrl-p:change-prompt( ▲ perm  )+reload($0 --list permission)" \
  --bind "ctrl-o:change-prompt( ● run  )+reload($0 --list running)" \
  --bind "ctrl-w:change-prompt( ◐ wait  )+reload($0 --list waiting)" \
  --bind "ctrl-i:change-prompt( ○ idle  )+reload($0 --list idle)" \
  --bind "ctrl-x:change-prompt( ✗ stale  )+reload($0 --list stale)" \
  --bind "ctrl-d:execute-silent($0 --purge)+reload($0 --list)" \
)

[ -z "$selected" ] && exit 0

# Session ID is the last tab-separated field
sid=$(printf '%s' "$selected" \
  | awk -F'\t' '{print $NF}')
switch_to "$sid"
