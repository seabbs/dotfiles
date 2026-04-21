#!/bin/bash
# claude-conductor-gather.sh — collect all active session
# data in one pass, output JSON for the conductor skill.
#
# Usage: claude-conductor-gather.sh > /tmp/conductor.json
#
# Output: JSON object with sessions array, each entry has
# state, project, cwd, tmux location, age, recent prompts.

STATUS_DIR="$HOME/.agent/session-monitor"
HISTORY="$HOME/.claude/history.jsonl"
SESSIONS_DIR="$HOME/.claude/sessions"
PROJECTS_DIR="$HOME/.claude/projects"

[ -d "$STATUS_DIR" ] || { echo '{"sessions":[]}'; exit 0; }

NOW=$(date +%s)
PANES=$(tmux list-panes -a -F '#{pane_id}' 2>/dev/null)

# Build session data
jq -n '[]' > /tmp/_conductor_sessions.json

for f in "$STATUS_DIR"/*.json; do
  [ -f "$f" ] || continue

  SID=$(basename "$f" .json)
  DATA=$(cat "$f")

  STATE=$(printf '%s' "$DATA" | jq -r '.state')
  CWD=$(printf '%s' "$DATA" | jq -r '.cwd')
  PROJECT=$(printf '%s' "$DATA" | jq -r '.project')
  PANE=$(printf '%s' "$DATA" | jq -r '.tmux_pane // empty')
  TS=$(printf '%s' "$DATA" | jq -r '.tmux_session')
  TW=$(printf '%s' "$DATA" | jq -r '.tmux_window')
  TWN=$(printf '%s' "$DATA" | jq -r '.tmux_window_name')
  UPDATED=$(printf '%s' "$DATA" | jq -r '.updated')
  AGENT=$(printf '%s' "$DATA" | jq -r '.agent // "claude"')

  AGE=$(( NOW - UPDATED ))

  # Stale detection
  if [ -n "$PANE" ] && [ -n "$PANES" ]; then
    if ! printf '%s\n' "$PANES" \
        | grep -qF "$PANE"; then
      STATE="stale"
    fi
  fi
  if [ "$AGE" -gt 86400 ] \
      && [ "$STATE" != "running" ]; then
    STATE="stale"
  fi

  # Age string
  if [ "$AGE" -lt 60 ]; then
    AGE_STR="${AGE}s"
  elif [ "$AGE" -lt 3600 ]; then
    AGE_STR="$(( AGE / 60 ))m"
  elif [ "$AGE" -lt 86400 ]; then
    AGE_STR="$(( AGE / 3600 ))h"
  else
    AGE_STR="$(( AGE / 86400 ))d"
  fi

  # Session name from metadata
  NAME=""
  SF="$SESSIONS_DIR/$SID.json"
  if [ -f "$SF" ]; then
    NAME=$(jq -r '.name // empty' "$SF")
  fi

  # Recent prompts from history
  PROMPTS="[]"
  if [ -f "$HISTORY" ]; then
    PROMPTS=$(grep "$SID" "$HISTORY" \
      | tail -3 \
      | jq -r '.display[:120]' \
      | jq -R -s 'split("\n") | map(select(. != ""))')
  fi

  # Last assistant response from project JSONL
  # Path encoding: / and . in cwd become -
  LAST_RESPONSE=""
  if [ -n "$CWD" ]; then
    ENCODED=$(printf '%s' "$CWD" | tr '/.' '--')
    PROJ_FILE="$PROJECTS_DIR/$ENCODED/$SID.jsonl"
    if [ -f "$PROJ_FILE" ]; then
      LAST_RESPONSE=$(tail -100 "$PROJ_FILE" \
        | jq -r 'select(.type == "assistant")
                 | .message.content[]?
                 | select(.type == "text")
                 | .text' 2>/dev/null \
        | tail -1 \
        | cut -c1-200)
    fi
  fi

  # Sort key
  case "$STATE" in
    permission) SORT=1 ;;
    running)    SORT=2 ;;
    waiting)    SORT=3 ;;
    idle)       SORT=4 ;;
    stale)      SORT=5 ;;
    *)          SORT=9 ;;
  esac

  # State icon
  case "$STATE" in
    running)    ICON="●" ;;
    waiting)    ICON="◐" ;;
    idle)       ICON="○" ;;
    permission) ICON="▲" ;;
    stale)      ICON="✗" ;;
    *)          ICON="?" ;;
  esac

  jq --argjson sessions "$(cat /tmp/_conductor_sessions.json)" \
    --arg sid "$SID" \
    --arg state "$STATE" \
    --arg icon "$ICON" \
    --arg project "$PROJECT" \
    --arg name "$NAME" \
    --arg cwd "$CWD" \
    --arg ts "$TS" \
    --arg tw "$TW" \
    --arg twn "$TWN" \
    --arg pane "$PANE" \
    --arg age "$AGE_STR" \
    --argjson sort "$SORT" \
    --argjson prompts "$PROMPTS" \
    --arg agent "$AGENT" \
    --arg last_response "$LAST_RESPONSE" \
    -n '$sessions + [{
      session_id: $sid,
      agent: $agent,
      state: $state,
      icon: $icon,
      project: $project,
      name: $name,
      cwd: $cwd,
      tmux_session: $ts,
      tmux_window: $tw,
      tmux_window_name: $twn,
      tmux_pane: $pane,
      age: $age,
      sort_key: $sort,
      recent_prompts: $prompts,
      last_response: $last_response
    }]' > /tmp/_conductor_sessions.json
done

# Sort by sort_key and output
jq -n --argjson s "$(cat /tmp/_conductor_sessions.json)" \
  '{sessions: ($s | sort_by(.sort_key))}' \

rm -f /tmp/_conductor_sessions.json
