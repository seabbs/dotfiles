#!/bin/bash
# agent-session-track.sh — AI CLI agent hook for session monitoring
# Writes per-session state to ~/.agent/session-monitor/<id>.json
#
# Supports:
#   Claude Code (JSON on stdin)
#   Gemini CLI (JSON on stdin + optional args: agent event)

STATUS_DIR="$HOME/.agent/session-monitor"
mkdir -p "$STATUS_DIR"

INPUT=$(cat)

# Extract basic info
AGENT="${1:-claude}"
EVENT="${2:-}"
SESSION_ID=""

if [ "$AGENT" = "claude" ]; then
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
  [ -z "$EVENT" ] && EVENT=$(printf '%s' "$INPUT" | jq -r '.hook_event_name // empty')
else
  # Gemini or other
  SESSION_ID=$(printf '%s' "$INPUT" | jq -r '.session_id // empty')
  if [ -z "$SESSION_ID" ]; then
    # Fallback: use tmux pane id to identify session if no ID provided
    if [ -n "$TMUX_PANE" ]; then
      SESSION_ID="${AGENT}-${TMUX_PANE#%}"
    else
      SESSION_ID="${AGENT}-standalone"
    fi
  fi
fi

[ -z "$SESSION_ID" ] && exit 0
STATUS_FILE="$STATUS_DIR/$SESSION_ID.json"

# SessionEnd: clean up
if [ "$EVENT" = "SessionEnd" ]; then
  rm -f "$STATUS_FILE"
  exit 0
fi

# Map event to state
case "$EVENT" in
  # Running states
  SessionStart|UserPromptSubmit|PreToolUse|PostToolUse|BeforeAgent|AfterTool)
    STATE="running"
    ;;
  # Prompting/Waiting states
  Stop|AfterAgent)
    STATE="waiting"
    ;;
  # Conditional states
  BeforeTool)
    TOOL=$(printf '%s' "$INPUT" | jq -r '.tool_name // empty')
    if [ "$TOOL" = "ask_user" ]; then
      STATE="waiting"
    else
      STATE="running"
    fi
    ;;
  Notification)
    MATCHER=$(printf '%s' "$INPUT" | jq -r '.notification_type // empty')
    case "$MATCHER" in
      ToolPermission|permission_prompt) STATE="permission" ;;
      idle_prompt)                      STATE="idle" ;;
      *)                                STATE="waiting" ;;
    esac
    ;;
  *)
    # Default to running for start events, waiting for others
    if [[ "$EVENT" == *"Start"* ]]; then
      STATE="running"
    else
      STATE="waiting"
    fi
    ;;
esac

CWD=$(printf '%s' "$INPUT" | jq -r '.cwd // empty')
[ -z "$CWD" ] && CWD="$PWD"
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
  --arg agent "$AGENT" \
  --argjson updated "$(date +%s)" \
  '{state:$state,cwd:$cwd,project:$project,
    tmux_pane:$pane,tmux_session:$ts,
    tmux_window:$tw,tmux_window_name:$twn,
    agent:$agent,
    updated:$updated}' \
  > "$TMP_FILE" \
  && mv "$TMP_FILE" "$STATUS_FILE"

# Deliver inbox messages when session is waiting for input (Claude only for now)
if [ "$AGENT" = "claude" ] && { [ "$STATE" = "waiting" ] || [ "$STATE" = "idle" ]; }; then
  INBOX_FILE="$HOME/.claude/inbox/$SESSION_ID.md"
  if [ -f "$INBOX_FILE" ]; then
    DELIVER="$HOME/code/seabbs/dotfiles/scripts/claude-inbox-deliver.sh"
    [ -x "$DELIVER" ] && "$DELIVER" "$SESSION_ID" &
  fi
fi

# Hooks expect JSON on stdout
echo "{}"
exit 0
