#!/bin/bash
# Reap REPL processes nobody is using any more.
#
# Long-lived Julia and R sessions (AgentREPL servers, bare REPLs left in
# tmux panes) hold their heap for as long as they live. A handful of them
# idling for a week can take a third of the machine's memory, which shows
# up as swap thrash and stalled builds rather than as an obvious culprit.
#
# Idleness is measured by CPU time standing still between runs, not by
# process age. A REPL started a month ago but used this morning is active
# and is kept. A REPL started a month ago and untouched since is reaped.
# That needs the job to run daily so the idle streak can accumulate.
#
# Nothing is reaped on the first run, since there is no prior sample to
# compare against. That is deliberate.
#
# Opting a process out, any one of:
#   - put a glob for its command line in ~/.config/repl-gc/keep
#   - include the string REPL_GC_KEEP in its command line
#   - set REPL_GC_KEEP=1 in its environment (Linux only)
#
# Defaults to a dry run. Pass --apply to actually reap.
#
# When run interactively, prints all results.
# When run by cron (no tty), only logs.

STALE_DAYS=2
LOG_DIR="$HOME/.local/share/repl-gc"
LOG_FILE="$LOG_DIR/last-run.log"
LOCK_FILE="$LOG_DIR/lock"
STATE_FILE="$LOG_DIR/state"
KEEP_FILE="$HOME/.config/repl-gc/keep"
mkdir -p "$LOG_DIR"

# One run at a time. Overlapping runs would each take their own CPU sample
# and disagree about what is idle.
# flock isn't part of macOS by default (`brew install flock`, done by
# cli/setup.sh) -- fail loudly rather than let a missing binary make
# `flock -n 9` exit 127, indistinguishable from "lock held".
command -v flock >/dev/null 2>&1 || {
  echo "flock not found -- run 'brew install flock' (see cli/setup.sh)" >&2
  exit 1
}
exec 9>"$LOCK_FILE"
flock -n 9 || exit 0

APPLY=false
# comm names to consider. Rscript execs R, so it shows up as R too.
MATCH="^(julia|R|Rscript)$"

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --dry-run) APPLY=false; shift ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --match) MATCH="$2"; shift 2 ;;
    -h|--help)
      echo "usage: repl-gc.sh [--apply] [--stale-days N] [--match REGEX]"
      echo
      echo "Reaps Julia/R REPLs whose CPU time has not moved for N days."
      echo "Opt out via ~/.config/repl-gc/keep, a REPL_GC_KEEP marker in"
      echo "the command line, or REPL_GC_KEEP=1 in the environment."
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

log() {
  printf '%s\n' "$1" >> "$LOG_FILE"
  $INTERACTIVE && printf '%s\n' "$1"
  return 0
}

logf() {
  printf '%-46s %s\n' "$1" "$2" >> "$LOG_FILE"
  $INTERACTIVE && printf '%-46s %s\n' "$1" "$2"
  return 0
}

: > "$LOG_FILE"
log "repl-gc $(date '+%Y-%m-%d %H:%M:%S')"
$APPLY || log "DRY RUN - pass --apply to reap"
log ""

NOW=$(date +%s)
STALE_SECS=$((STALE_DAYS * 86400))

# ps prints cputime as [[DD-]HH:]MM:SS. Normalise to seconds so it can be
# compared against the previous run's sample.
cputime_secs() {
  local t="$1"
  local days=0 acc=0 part
  local rest="$t"
  case "$rest" in
    *-*) days="${rest%%-*}"; rest="${rest#*-}" ;;
  esac
  local IFS=:
  for part in $rest; do
    part="${part#0}"
    acc=$((acc * 60 + ${part:-0}))
  done
  echo $((days * 86400 + acc))
}

# Keep patterns are globs matched against the whole command line.
KEEP_PATTERNS=()
if [ -r "$KEEP_FILE" ]; then
  while IFS= read -r line; do
    case "$line" in
      ''|\#*) continue ;;
    esac
    KEEP_PATTERNS+=("$line")
  done < "$KEEP_FILE"
  log "keep patterns: ${#KEEP_PATTERNS[@]} from $KEEP_FILE"
fi

is_kept() {
  local args="$1" pid="$2" pat
  case "$args" in
    *REPL_GC_KEEP*) return 0 ;;
  esac
  for pat in "${KEEP_PATTERNS[@]}"; do
    # Unquoted on purpose: keep entries are globs, not literals.
    # shellcheck disable=SC2254
    case "$args" in
      $pat) return 0 ;;
    esac
  done
  # Linux only. macOS will not let us read another process's environment,
  # so there the command line and keep file are the whole story.
  if [ -r "/proc/$pid/environ" ] &&
     tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null |
       grep -qx 'REPL_GC_KEEP=1'; then
    return 0
  fi
  return 1
}

# Previous run's samples, keyed by pid and start time so a recycled pid is
# never mistaken for the process that held it before.
declare -A PREV_CPU PREV_IDLE_SINCE
if [ -r "$STATE_FILE" ]; then
  while IFS='|' read -r key cpu idle_since; do
    [ -n "$key" ] || continue
    PREV_CPU["$key"]="$cpu"
    PREV_IDLE_SINCE["$key"]="$idle_since"
  done < "$STATE_FILE"
fi

NEW_STATE=$(mktemp)
reaped=0 kept_active=0 kept_optout=0 watching=0 freed_kb=0
REAP_PIDS=()

# stat first so a process that is currently running is skipped before we
# bother sampling it. lstart has spaces in it, so it goes last but one and
# args, which also has spaces, goes last and is taken whole.
while read -r pid stat_f rss comm cputime lstart_args; do
  [[ "$comm" =~ $MATCH ]] || continue

  # lstart is five whitespace-separated fields, then the command line.
  read -r l1 l2 l3 l4 l5 args <<< "$lstart_args"
  starttime="$l1$l2$l3$l4$l5"
  key="$pid:$starttime"
  short="${args:0:44}"

  # Currently on CPU. Whatever else is true, someone is using it.
  case "$stat_f" in
    R*|D*) kept_active=$((kept_active + 1)); continue ;;
  esac

  if is_kept "$args" "$pid"; then
    kept_optout=$((kept_optout + 1))
    logf "keep (opted out) $pid" "$short"
    continue
  fi

  cpu_now=$(cputime_secs "$cputime")
  prev_cpu="${PREV_CPU[$key]}"
  prev_idle="${PREV_IDLE_SINCE[$key]}"

  if [ -n "$prev_cpu" ] && [ "$cpu_now" = "$prev_cpu" ]; then
    idle_since="${prev_idle:-$NOW}"
  else
    # New to us, or it has burned CPU since the last sample. Either way the
    # idle streak starts now.
    idle_since="$NOW"
  fi

  idle_for=$((NOW - idle_since))
  idle_days=$((idle_for / 86400))

  if [ "$idle_for" -ge "$STALE_SECS" ]; then
    logf "reap ($idle_days d idle, $((rss / 1024)) MB) $pid" "$short"
    if $APPLY; then
      kill -TERM "$pid" 2>/dev/null
      REAP_PIDS+=("$pid")
    fi
    reaped=$((reaped + 1))
    freed_kb=$((freed_kb + rss))
    # Deliberately not carried into the new state: if it survives the reap
    # its streak restarts, so a process we failed to kill is not retried
    # blindly on the next run.
    continue
  fi

  printf '%s|%s|%s\n' "$key" "$cpu_now" "$idle_since" >> "$NEW_STATE"
  watching=$((watching + 1))
done < <(ps -eo pid=,stat=,rss=,comm=,cputime=,lstart=,args= 2>/dev/null)

# Give them a moment to go on their own terms, then insist. A Julia process
# with a large heap can take a few seconds to unwind.
if $APPLY && [ "${#REAP_PIDS[@]}" -gt 0 ]; then
  for _ in 1 2 3 4 5; do sleep 1; done
  for pid in "${REAP_PIDS[@]}"; do
    kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null
  done
fi

mv "$NEW_STATE" "$STATE_FILE"

log ""
logf "reaped" "$reaped ($((freed_kb / 1024)) MB)"
logf "kept, busy right now" "$kept_active"
logf "kept, opted out" "$kept_optout"
logf "watching for idleness" "$watching"
$APPLY || log "dry run - nothing was killed"
