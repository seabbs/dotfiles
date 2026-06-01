#!/bin/bash
# claude-rate-limit-resume.sh
# Resume Claude tmux sessions that are stuck on a usage limit.
#
# Detection is driven by the session transcript, not the pane text.
# Claude persists every usage-limit hit as a 429 api-error entry in
# its JSONL, carrying an explicit timezone and reset clock. A helper
# (claude-rate-limit-analyze.py) reads that to decide whether the
# session is currently stuck and, if so, when the limit resets. This
# survives CLI wording changes, distinguishes real caps from
# server-side throttling and policy refusals, and reads the timezone
# rather than guessing.
#
# The pane is only touched once the reset has passed. Any blocking
# "out of usage" menu (Stop and wait / Add funds / Upgrade) is
# dismissed with Escape — never confirmed with Enter — so we can
# never accidentally buy extra usage or change the plan.
#
# Liveness comes from tmux: we iterate live panes only, so abandoned
# sessions whose transcripts end on a 429 are never resurrected.
#
# Intended to run on a timer (launchd, every 10 min). Idempotent.

set -u

INBOX_DIR="$HOME/.claude/inbox"
STATUS_DIR="$HOME/.agent/session-monitor"
PROJECTS_DIR="$HOME/.claude/projects"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ANALYZER="$SCRIPT_DIR/claude-rate-limit-analyze.py"
DELIVER="$SCRIPT_DIR/claude-inbox-deliver.sh"
LOG="$HOME/.claude/rate-limit-resume.log"
COOLDOWN_DIR="$HOME/.claude/rate-limit-cooldown"
COOLDOWN_SECS=1800  # 30 minutes between pokes of the same pane

log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" >> "$LOG"; }

# A blocking selection menu / confirmation is showing. We dismiss
# these with Escape and never press Enter, because the out-of-usage
# menu's options include "Add funds" and "Upgrade your plan".
MENU_RE='Esc to cancel|Stop and wait for limit|Add funds'
MENU_RE="$MENU_RE|Upgrade your plan|out of extra usage"

# Map a tmux pane to its session-monitor record. Filename == Claude
# sessionId. If a pane id has been reused, prefer the newest record.
monitor_for_pane() {
  local pane="$1"
  [ -d "$STATUS_DIR" ] || return 1
  grep -l "\"tmux_pane\": *\"$pane\"" "$STATUS_DIR"/*.json 2>/dev/null \
    | xargs -r ls -t 2>/dev/null | head -1
}

# Locate a session's transcript by sessionId across all project dirs.
jsonl_for_session() {
  local sid="$1"
  ls -t "$PROJECTS_DIR"/*/"$sid".jsonl 2>/dev/null | head -1
}

# Send the resume nudge: submit any queued input, else deliver a
# pending inbox message, else a generic "carry on" prompt.
nudge() {
  local pane="$1" sid="$2" content="$3" reset_human="$4"
  local last_input input_text
  last_input=$(echo "$content" | awk '/^❯/{l=$0} END{print l}')
  input_text=$(echo "$last_input" \
    | sed -E 's/^❯[[:space:]]*//; s/[[:space:]]+$//')

  if [ -n "$input_text" ]; then
    log "Pane $pane — submitting queued input (reset: $reset_human)"
    tmux send-keys -t "$pane" Enter
    return 0
  fi

  local inbox_file="$INBOX_DIR/$sid.md"
  if [ -n "$sid" ] && [ -f "$inbox_file" ]; then
    log "Pane $pane — delivering queued inbox $sid (reset: $reset_human)"
    "$DELIVER" "$sid"
    return 0
  fi

  log "Pane $pane — sending generic resume (reset: $reset_human)"
  local msg="Rate limit has reset. Please resume where you left off "
  msg+="and report status before continuing."
  tmux send-keys -t "$pane" -l "$msg"
  tmux send-keys -t "$pane" Enter
}

process_pane() {
  local pane="$1"

  local monitor sid jsonl
  monitor=$(monitor_for_pane "$pane") || return 0
  [ -n "$monitor" ] || return 0
  sid=$(basename "$monitor" .json)
  jsonl=$(jsonl_for_session "$sid")
  [ -n "$jsonl" ] || return 0

  # Transcript-driven verdict.
  local verdict
  verdict=$(python3 "$ANALYZER" "$jsonl" 2>/dev/null) || return 0
  local stuck
  stuck=$(echo "$verdict" | jq -r '.stuck // false')
  [ "$stuck" = "true" ] || return 0

  local limit_type reset_epoch reset_human now
  limit_type=$(echo "$verdict" | jq -r '.limit_type // "generic"')
  reset_epoch=$(echo "$verdict" | jq -r '.reset_epoch // empty')
  reset_human=$(echo "$verdict" | jq -r '.reset_human // "unknown"')
  now=$(date +%s)

  # Monthly cap has no reset time and won't clear soon — leave it for
  # a human rather than poking uselessly.
  if [ "$limit_type" = "monthly" ]; then
    log "Pane $pane — monthly usage cap, needs manual action; skipping"
    return 0
  fi

  if [ -z "$reset_epoch" ]; then
    log "Pane $pane — $limit_type limit but no reset time parsed; skipping"
    return 0
  fi

  if [ "$now" -lt "$reset_epoch" ]; then
    log "Pane $pane — $limit_type limit, waiting until $reset_human"
    return 0
  fi

  # Per-pane cooldown: avoid re-poking a pane we just nudged (it may
  # be mid-turn, or have re-hit a fresh limit). Marked before acting
  # so a failed poke still suppresses immediate retries.
  local cooldown_file="$COOLDOWN_DIR/${pane#%}"
  if [ -f "$cooldown_file" ]; then
    local last_poke age
    last_poke=$(stat -f %m "$cooldown_file" 2>/dev/null \
      || stat -c %Y "$cooldown_file" 2>/dev/null)
    age=$((now - last_poke))
    if [ "$age" -lt "$COOLDOWN_SECS" ]; then
      return 0
    fi
  fi

  local content
  content=$(tmux capture-pane -t "$pane" -p 2>/dev/null) || return 0

  # Money-safe menu handling: if a blocking selection/confirmation is
  # showing, dismiss it with Escape. Never confirm with Enter.
  if echo "$content" | grep -qE "$MENU_RE"; then
    log "Pane $pane — dismissing out-of-usage menu with Escape"
    tmux send-keys -t "$pane" Escape
    sleep 1
    tmux send-keys -t "$pane" Escape
    sleep 1
    content=$(tmux capture-pane -t "$pane" -p 2>/dev/null) || return 0
    if echo "$content" | grep -qE "$MENU_RE"; then
      log "Pane $pane — menu still showing after Escape; skipping"
      return 0
    fi
  fi

  mkdir -p "$COOLDOWN_DIR"
  touch "$cooldown_file"
  nudge "$pane" "$sid" "$content" "$reset_human"
}

mkdir -p "$(dirname "$LOG")"

# RL_ONLY_PANE restricts processing to a single pane id (testing /
# targeted use). Default: every pane in every session.
if [ -n "${RL_ONLY_PANE:-}" ]; then
  process_pane "$RL_ONLY_PANE" || true
else
  tmux list-panes -a -F '#{pane_id}' 2>/dev/null | while read -r p; do
    process_pane "$p" || true
  done
fi

exit 0
