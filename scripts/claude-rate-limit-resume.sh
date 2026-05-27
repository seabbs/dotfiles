#!/bin/bash
# claude-rate-limit-resume.sh
# Scan all Claude tmux panes for the weekly/session rate-limit
# notice. When found and the reset time has passed, optionally
# dismiss the legacy /rate-limit-options menu, then deliver a
# queued inbox message for that session or send a generic
# "resume" nudge.
#
# Intended to run on a cron (e.g. every 10 min). Idempotent and
# safe to run repeatedly — only acts when the rate-limit notice
# is currently in the visible tail of the pane (not buried in
# earlier conversation) and the input box is empty.

set -u

INBOX_DIR="$HOME/.claude/inbox"
STATUS_DIR="$HOME/.agent/session-monitor"
DELIVER="$HOME/code/seabbs/dotfiles/scripts/claude-inbox-deliver.sh"
LOG="$HOME/.claude/rate-limit-resume.log"
COOLDOWN_DIR="$HOME/.claude/rate-limit-cooldown"
COOLDOWN_SECS=1800  # 30 minutes

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Structural detection — chosen to survive future wording changes.
#
# The Claude CLI renders a limit notice as a tool-result line
# prefixed with the U+23BF glyph "⎿" (turned dash). Normal
# assistant chat never uses this prefix, so requiring it filters
# out historical references like "I'll retry when the limit
# resets at 6pm." that appear in conversation text.
#
# A stuck-pane signature is then:
#   <tool-result-prefix> ... limit ... <clock-time>
# on a single line, with the clock time interpreted as the reset
# target.
TOOL_RESULT_PREFIX_RE='^[[:space:]]*⎿'
CLOCK_RE='[0-9]{1,2}(:[0-9]{2})?(am|pm|AM|PM)'
LIMIT_KEYWORD_RE='[Ll]imit'
# Optional reset-verb hint, used only to disambiguate when the
# notice contains more than one clock time. Not required for
# detection — wording changes here won't break the script.
RESET_PHRASE_RE="(reset(s|[[:space:]]+at)?|resume[sd]?|available[[:space:]]+(again|at)|try[[:space:]]+again[[:space:]]+(at|in)|back[[:space:]]+at|until)[^0-9]{0,15}${CLOCK_RE}"

# Legacy menu (older CLI versions). Optional — dismissed if
# present, but no longer required for detection.
MENU_OPT_RE="❯ 1\. Stop and wait for limit to reset"
MENU_CONFIRM_RE="Enter to confirm · Esc to cancel"

# How many lines of the pane's visible tail to scan. Stops us
# re-acting on panes that already resumed — the notice scrolls
# out of the recent area.
TAIL_LINES=5

# Returns 0 if the reset time string (e.g. "1pm") is in the
# past relative to current Europe/London time. Returns 1 if
# still in the future (within next 12h) so we should wait.
reset_passed() {
  local raw="$1"  # e.g. "1pm" or "7:50pm"
  local hh mm ampm now_min reset_min
  if [[ "$raw" =~ ^([0-9]{1,2})(:([0-9]{2}))?(am|pm)$ ]]; then
    hh="${BASH_REMATCH[1]}"
    mm="${BASH_REMATCH[3]:-0}"
    ampm="${BASH_REMATCH[4]}"
  else
    return 0  # unparseable — fail open, attempt resume
  fi
  # Normalise to 24h
  hh=$((10#$hh))
  mm=$((10#$mm))
  [ "$ampm" = "pm" ] && [ "$hh" -lt 12 ] && hh=$((hh + 12))
  [ "$ampm" = "am" ] && [ "$hh" -eq 12 ] && hh=0
  reset_min=$((hh * 60 + mm))
  now_min=$(TZ=Europe/London date +"%-H * 60 + %-M")
  now_min=$((now_min))
  # Tolerate up to 30 min clock drift: treat reset as passed
  # if we're within 30 min after it OR clearly past it later
  # in the day. If "now" is before reset, still in the future.
  if [ "$now_min" -ge "$reset_min" ]; then
    return 0
  fi
  return 1
}

session_id_for_pane() {
  local pane="$1"
  [ -d "$STATUS_DIR" ] || return 1
  grep -l "\"tmux_pane\": *\"$pane\"" \
    "$STATUS_DIR"/*.json 2>/dev/null \
    | head -1 | xargs -I{} basename {} .json
}

resume_pane() {
  local pane="$1"
  local content tail
  content=$(tmux capture-pane -t "$pane" -p 2>/dev/null) \
    || return 0
  tail=$(echo "$content" | tail -"$TAIL_LINES")

  # Per-pane cooldown. If we poked this pane recently, skip —
  # Claude is either still processing or just re-hit a fresh
  # limit, and re-poking won't help.
  local cooldown_file="$COOLDOWN_DIR/${pane#%}"
  if [ -f "$cooldown_file" ]; then
    local last_poke now age
    last_poke=$(stat -f %m "$cooldown_file" 2>/dev/null || \
      stat -c %Y "$cooldown_file" 2>/dev/null)
    now=$(date +%s)
    age=$((now - last_poke))
    if [ "$age" -lt "$COOLDOWN_SECS" ]; then
      return 0
    fi
  fi

  # Detection: a tool-result line in the visible tail that
  # mentions "limit" and contains a clock time. Both signals on
  # one ⎿-prefixed line is the structural signature of Claude's
  # inline limit notice. Filters out chat references and old
  # notices that scrolled past.
  local notice_line
  notice_line=$(echo "$tail" \
    | grep -E "$TOOL_RESULT_PREFIX_RE" \
    | grep -E "$LIMIT_KEYWORD_RE" \
    | grep -Ei "$CLOCK_RE" \
    | tail -1)
  if [ -z "$notice_line" ]; then
    return 0
  fi

  # Extract the clock time. Prefer one following a reset-style
  # verb (handles lines that mention multiple times); fall back
  # to the last clock on the notice line.
  local reset_raw
  reset_raw=$(echo "$notice_line" \
    | grep -Eio "$RESET_PHRASE_RE" | tail -1 \
    | grep -Eo "$CLOCK_RE" | tail -1)
  if [ -z "$reset_raw" ]; then
    reset_raw=$(echo "$notice_line" \
      | grep -Eo "$CLOCK_RE" | tail -1)
  fi
  reset_raw=$(echo "$reset_raw" | tr '[:upper:]' '[:lower:]')
  if [ -n "$reset_raw" ] && ! reset_passed "$reset_raw"; then
    log "Pane $pane rate-limited until $reset_raw — waiting"
    return 0
  fi

  # If the legacy menu is showing, dismiss it. New CLI versions
  # don't show a menu, so absence is fine.
  if echo "$content" | grep -q "$MENU_OPT_RE" \
     && echo "$content" | grep -q "$MENU_CONFIRM_RE"; then
    log "Pane $pane — dismissing legacy menu"
    tmux send-keys -t "$pane" Escape
    sleep 1
    tmux send-keys -t "$pane" Escape
    sleep 1
    content=$(tmux capture-pane -t "$pane" -p 2>/dev/null)
    if echo "$content" | grep -q "$MENU_OPT_RE"; then
      log "Pane $pane menu still showing after Escape; skipping"
      return 0
    fi
  fi

  # Inspect the input box. The Claude CLI renders it at the
  # bottom as "❯ <text>" — last "❯ " line in the capture.
  local last_input input_text
  last_input=$(echo "$content" \
    | awk '/^❯/{l=$0} END{print l}')
  input_text=$(echo "$last_input" \
    | sed -E 's/^❯[[:space:]]*//; s/[[:space:]]+$//')

  # Mark cooldown before poking so failures still suppress re-fires.
  mkdir -p "$COOLDOWN_DIR"
  touch "$cooldown_file"

  if [ -n "$input_text" ]; then
    # User left a queued message — just submit it.
    log "Pane $pane — submitting queued input (reset: ${reset_raw:-unknown})"
    tmux send-keys -t "$pane" Enter
    return 0
  fi

  local sid inbox_file
  sid=$(session_id_for_pane "$pane")
  inbox_file="$INBOX_DIR/$sid.md"

  if [ -n "$sid" ] && [ -f "$inbox_file" ]; then
    log "Pane $pane — delivering queued inbox $sid (reset: ${reset_raw:-unknown})"
    "$DELIVER" "$sid"
    return 0
  fi

  log "Pane $pane — sending generic resume (reset: ${reset_raw:-unknown})"
  local msg="Rate limit has reset. Please resume where you left off and report status before continuing."
  tmux send-keys -t "$pane" -l "$msg"
  tmux send-keys -t "$pane" Enter
}

mkdir -p "$(dirname "$LOG")"

# Iterate every pane in every tmux session. Cheap; tmux pane
# count is small.
tmux list-panes -a -F '#{pane_id}' 2>/dev/null | while read -r p; do
  resume_pane "$p" || true
done

exit 0
