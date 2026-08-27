#!/bin/bash
# bot-common.sh — shared machinery for the agent bots (review-bot, and the
# summon bot when it lands). Sourced, not executed.
#
# The bots follow one architecture, and this file is where it lives:
#
#   - deterministic gates in bash, model calls only for judgement
#   - the model runs inside bwrap with a fake home, so a prompt injection
#     in whatever it is reading cannot reach ~/.ssh, ~/.config/gh or ~/code
#   - the privileged action (posting, pushing) is done by the script after
#     the model has exited, so no credential is ever in the model's reach
#   - every decision is appended to a log that is never truncated, so
#     "what has this thing been doing" is answerable after the fact
#
# Usage:
#   BOT_NAME=review-bot
#   . "$(dirname "$0")/bot-common.sh"

# --------------------------------------------------------------- paths

: "${BOT_NAME:?bot-common.sh needs BOT_NAME set before sourcing}"

STATE_DIR="$HOME/.local/share/$BOT_NAME"
CACHE_DIR="$HOME/.cache/$BOT_NAME"
# Wiped per run, for "what happened just now".
LOG_FILE="$STATE_DIR/last-run.log"
# Appended forever (rotated by size), for "what has it been doing".
AUDIT_LOG="$STATE_DIR/activity.log"
SANDBOX_HOME="$CACHE_DIR/sandbox-home"
mkdir -p "$STATE_DIR" "$CACHE_DIR"

AUDIT_MAX_BYTES="${BOT_AUDIT_MAX_BYTES:-5242880}"   # 5 MiB, then rotate
CACHE_MAX_MB="${BOT_CACHE_MAX_MB:-500}"             # prune clones past this
CACHE_MAX_AGE_DAYS="${BOT_CACHE_MAX_AGE_DAYS:-14}"

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

# --------------------------------------------------------------- logging

# The terminal copy goes to stderr: log is called from inside command
# substitutions, and on stdout it would be captured as their value.
log() {
  local stamp
  stamp="$(date '+%Y-%m-%d %H:%M:%S')"
  printf '%s %s\n' "$stamp" "$*" >> "$LOG_FILE"
  printf '%s %s\n' "$stamp" "$*" >> "$AUDIT_LOG"
  $INTERACTIVE && echo "$*" >&2
  return 0
}

rotate_logs() {
  local size
  for f in "$AUDIT_LOG"; do
    [ -f "$f" ] || continue
    size="$(wc -c < "$f" | tr -d ' ')"
    if [ "${size:-0}" -gt "$AUDIT_MAX_BYTES" ]; then
      mv "$f" "$f.1"
      log "rotated $(basename "$f") at $size bytes"
    fi
  done
}

# ------------------------------------------------------------ timestamps

# GNU date takes -d, BSD date does not. Every conversion goes through
# these two so the difference is handled in one place: keeping separate
# copies in sync by hand is how the lookback window silently broke on
# macOS.
iso_to_epoch() {
  date -u -d "$1" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s 2>/dev/null \
    || echo 0
}

epoch_to_iso() {
  date -u -d "@$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null \
    || date -u -r "$1" +%Y-%m-%dT%H:%M:%SZ 2>/dev/null
}

now_iso() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# ------------------------------------------------------------- sandbox

# A copy of the Claude credential and nothing else. Refreshed every run
# because the OAuth token rotates.
prepare_sandbox() {
  local creds="$HOME/.claude/.credentials.json"
  mkdir -p "$SANDBOX_HOME/.claude"
  chmod 700 "$SANDBOX_HOME" "$SANDBOX_HOME/.claude"
  [ -f "$creds" ] && install -m 600 "$creds" "$SANDBOX_HOME/.claude/"
  return 0
}

# Emit a NUL-separated bwrap invocation to prefix a claude call with.
#
# What this does and does not protect: a tmpfs over $HOME hides
# everything under it, which is where the credentials live (~/.ssh,
# ~/.config/gh, ~/.config/review-bot) along with ~/code and ~/.cache.
# The rest of the filesystem stays readable read-only, so this is not a
# claim that the model sees nothing outside its workspace; it is a claim
# that it cannot reach anything of yours.
#
#   $1  workspace path, bound writable (git needs to refresh its index)
#   $2… extra paths, bound read-only
sandbox_prefix() {
  local work="$1"; shift
  local -a extra=()
  local p
  for p in "$@"; do
    [ -e "$p" ] && extra+=(--ro-bind "$p" "$p")
  done
  printf '%s\0' bwrap \
    --ro-bind / / --dev-bind /dev /dev --proc /proc --tmpfs /tmp \
    --bind "$SANDBOX_HOME" "$HOME" \
    --bind "$work" "$work" \
    "${extra[@]}" \
    --unshare-pid --unshare-ipc --unshare-uts --die-with-parent \
    --chdir "$work" --
}

# Claude writes transcripts, shell snapshots and backups into whatever it
# is given as a home, so the fake home grows with every run. None of it
# is wanted after the run that produced it.
prune_sandbox_home() {
  local d
  for d in projects sessions session-env shell-snapshots backups \
    statsig todos; do
    rm -rf "$SANDBOX_HOME/.claude/$d" 2>/dev/null
  done
  rm -rf "$SANDBOX_HOME/.cache" 2>/dev/null
  return 0
}

# Cached clones are worth keeping between runs and not worth keeping
# forever. Drop the ones nothing has touched recently, then the oldest
# ones if the total is still over budget.
prune_repo_cache() {
  local root="$1" size before
  [ -d "$root" ] || return 0
  before="$(du -sm "$root" 2>/dev/null | cut -f1)"

  while IFS= read -r d; do
    [ -n "$d" ] || continue
    rm -rf "$d"
    log "pruned stale clone $(basename "$d")"
  done < <(find "$root" -mindepth 2 -maxdepth 2 -type d \
    -mtime "+$CACHE_MAX_AGE_DAYS" 2>/dev/null)

  size="$(du -sm "$root" 2>/dev/null | cut -f1)"
  while [ "${size:-0}" -gt "$CACHE_MAX_MB" ]; do
    local oldest
    oldest="$(find "$root" -mindepth 2 -maxdepth 2 -type d -printf '%T@ %p\n' \
      2>/dev/null | sort -n | head -1 | cut -d' ' -f2-)"
    [ -n "$oldest" ] || break
    rm -rf "$oldest"
    log "pruned $(basename "$oldest") to stay under ${CACHE_MAX_MB}MB"
    size="$(du -sm "$root" 2>/dev/null | cut -f1)"
  done

  [ "${before:-0}" != "${size:-0}" ] \
    && log "clone cache ${before}MB -> ${size}MB"
  return 0
}
