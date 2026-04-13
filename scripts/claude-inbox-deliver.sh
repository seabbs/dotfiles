#!/bin/bash
# claude-inbox-deliver.sh — deliver queued inbox messages
# Called by the Stop hook in claude-session-track.sh
# when a session finishes a turn and is waiting for input.
#
# Reads ~/.claude/inbox/{session-id}.md, injects the
# message into the target tmux pane via send-keys,
# then removes the inbox file.

INBOX_DIR="$HOME/.claude/inbox"
STATUS_DIR="$HOME/.claude/session-monitor"

deliver() {
  local session_id="$1"
  local inbox_file="$INBOX_DIR/$session_id.md"

  [ -f "$inbox_file" ] || return 0

  # Read session state to find tmux pane
  local status_file="$STATUS_DIR/$session_id.json"
  [ -f "$status_file" ] || return 0

  local pane_id state
  pane_id=$(jq -r '.tmux_pane // empty' "$status_file")
  state=$(jq -r '.state // empty' "$status_file")

  [ -z "$pane_id" ] && return 0

  # Only deliver when waiting or idle
  case "$state" in
    waiting|idle) ;;
    *) return 0 ;;
  esac

  # Verify pane still exists
  if ! tmux display-message -t "$pane_id" -p '' \
      2>/dev/null; then
    rm -f "$inbox_file"
    return 0
  fi

  # Extract message body (skip YAML front matter)
  local body
  body=$(awk '
    /^---$/ { fm++; next }
    fm >= 2 { print }
  ' "$inbox_file")

  [ -z "$body" ] && { rm -f "$inbox_file"; return 0; }

  # Inject via tmux send-keys
  # Use literal flag to avoid key interpretation
  tmux send-keys -t "$pane_id" -l "$body"
  tmux send-keys -t "$pane_id" Enter

  rm -f "$inbox_file"
}

# If called with a session ID, deliver just that one
if [ -n "${1:-}" ]; then
  deliver "$1"
else
  # Deliver all pending inbox messages
  [ -d "$INBOX_DIR" ] || exit 0
  for f in "$INBOX_DIR"/*.md; do
    [ -f "$f" ] || continue
    sid=$(basename "$f" .md)
    deliver "$sid"
  done
fi
