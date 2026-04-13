#!/bin/bash
# claude-session-track.sh — Claude Code hook for session monitoring
# Writes per-session state to ~/.claude/session-monitor/<id>.json
#
# Hook events handled:
#   SessionStart      → running
#   SessionEnd        → (removes file)
#   UserPromptSubmit  → running
#   PreToolUse        → running
#   PostToolUse       → running
#   Stop              → waiting (just finished a turn)
#   Notification      → permission | idle (done, needs input)

STATUS_DIR="$HOME/.claude/session-monitor"
mkdir -p "$STATUS_DIR"

INPUT=$(cat)
SESSION_ID=$(printf '%s' "$INPUT" \
  | jq -r '.session_id // empty')
[ -z "$SESSION_ID" ] && exit 0

EVENT=$(printf '%s' "$INPUT" \
  | jq -r '.hook_event_name // empty')
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

# SessionEnd: clean up
if [ "$EVENT" = "SessionEnd" ]; then
  rm -f "$STATUS_FILE"
  exit 0
fi

# Map event to state
case "$EVENT" in
  SessionStart|UserPromptSubmit|PreToolUse|PostToolUse)
    STATE="running"
    ;;
  Stop)
    STATE="waiting"
    ;;
  Notification)
    MATCHER=$(printf '%s' "$INPUT" \
      | jq -r '.notification_type // empty')
    case "$MATCHER" in
      permission_prompt) STATE="permission" ;;
      idle_prompt)       STATE="idle" ;;
      *)                 STATE="waiting" ;;
    esac
    ;;
  *) exit 0 ;;
esac

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
PROJECT=$(basename "$CWD")

# Tmux context
PANE_ID="${TMUX_PANE:-}"
TMUX_SESSION="" TMUX_WINDOW="" TMUX_WINNAME=""
if [ -n "$PANE_ID" ]; then
  TMUX_INFO=$(tmux display-message -t "$PANE_ID" \
    -p '#{session_name}|#{window_index}|#{window_name}' \
    2>/dev/null || true)
  if [ -n "$TMUX_INFO" ]; then
    TMUX_SESSION="${TMUX_INFO%%|*}"
    rest="${TMUX_INFO#*|}"
    TMUX_WINDOW="${rest%%|*}"
    TMUX_WINNAME="${rest#*|}"
  fi
fi

TMP_FILE=$(mktemp "$STATUS_DIR/.tmp.XXXXXX")
jq -n \
  --arg state "$STATE" \
  --arg cwd "$CWD" \
  --arg project "$PROJECT" \
  --arg pane "$PANE_ID" \
  --arg ts "$TMUX_SESSION" \
  --arg tw "$TMUX_WINDOW" \
  --arg twn "$TMUX_WINNAME" \
  --argjson updated "$(date +%s)" \
  '{state:$state,cwd:$cwd,project:$project,
    tmux_pane:$pane,tmux_session:$ts,
    tmux_window:$tw,tmux_window_name:$twn,
    updated:$updated}' \
  > "$TMP_FILE" \
  && mv "$TMP_FILE" "$STATUS_FILE"

# Deliver inbox messages when session is waiting for input
if [ "$STATE" = "waiting" ] || [ "$STATE" = "idle" ]; then
  INBOX_FILE="$HOME/.claude/inbox/$SESSION_ID.md"
  if [ -f "$INBOX_FILE" ]; then
    DELIVER="$HOME/code/seabbs/dotfiles/scripts/claude-inbox-deliver.sh"
    [ -x "$DELIVER" ] && "$DELIVER" "$SESSION_ID" &
  fi
fi

exit 0
