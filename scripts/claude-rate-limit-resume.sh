#!/bin/bash
# claude-rate-limit-resume.sh
# Scan all Claude tmux panes for the weekly/session rate-limit
# screen. When found, dismiss the /rate-limit-options menu with
# Escape, then either deliver a queued inbox message for that
# session or send a generic "resume" nudge.
#
# Intended to run on a cron (e.g. every 10 min). Idempotent and
# safe to run repeatedly — only acts when the rate-limit text
# is currently displayed.

set -u

INBOX_DIR="$HOME/.claude/inbox"
STATUS_DIR="$HOME/.agent/session-monitor"
DELIVER="$HOME/code/seabbs/dotfiles/scripts/claude-inbox-deliver.sh"
LOG="$HOME/.claude/rate-limit-resume.log"

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# Patterns that mark a Claude pane stuck on the rate-limit
# selector. All three must match the recent tail of the pane
# to distinguish the live menu from transient text in logs or
# conversation history.
RATE_LIMIT_RE="(weekly limit|session limit).*resets"
MENU_OPT_RE="❯ 1\. Stop and wait for limit to reset"
MENU_CONFIRM_RE="Enter to confirm · Esc to cancel"
# Extracts the reset clock time, e.g. "8am", "1pm", "7:50pm".
RESET_TIME_RE="resets ([0-9]{1,2}(:[0-9]{2})?(am|pm))"

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
  # Only look at the current visible screen, not scrollback —
  # the menu must be live, not buried in earlier output.
  local content
  content=$(tmux capture-pane -t "$pane" -p 2>/dev/null) \
    || return 0

  # All three patterns must be on the visible screen:
  # the limit notice, the highlighted menu option, and the
  # menu confirmation prompt. Together they only co-occur on
  # the live /rate-limit-options selector.
  if ! echo "$content" | grep -Eq "$RATE_LIMIT_RE"; then
    return 0
  fi
  if ! echo "$content" | grep -q "$MENU_OPT_RE"; then
    return 0
  fi
  if ! echo "$content" | grep -q "$MENU_CONFIRM_RE"; then
    return 0
  fi

  # Re-verify menu still showing after Escape attempts below.
  local MENU_RE="$MENU_OPT_RE"

  # Only act once the displayed reset time has actually passed,
  # otherwise the next API call re-hits the limit immediately.
  local reset_raw
  reset_raw=$(echo "$content" \
    | grep -Eo "$RESET_TIME_RE" | tail -1 \
    | sed -E 's/^resets //')
  if [ -n "$reset_raw" ] && ! reset_passed "$reset_raw"; then
    log "Pane $pane rate-limited until $reset_raw — waiting"
    return 0
  fi

  log "Rate-limited pane $pane — dismissing menu (reset: ${reset_raw:-unknown})"
  tmux send-keys -t "$pane" Escape
  sleep 1
  tmux send-keys -t "$pane" Escape
  sleep 1

  # Confirm the menu is gone before injecting text. If still
  # present, bail and try next run.
  content=$(tmux capture-pane -t "$pane" -p 2>/dev/null)
  if echo "$content" | grep -q "$MENU_RE"; then
    log "Pane $pane menu still showing after Escape; skipping"
    return 0
  fi

  local sid inbox_file
  sid=$(session_id_for_pane "$pane")
  inbox_file="$INBOX_DIR/$sid.md"

  if [ -n "$sid" ] && [ -f "$inbox_file" ]; then
    log "Pane $pane — delivering queued inbox $sid"
    "$DELIVER" "$sid"
    return 0
  fi

  log "Pane $pane — sending generic resume"
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
