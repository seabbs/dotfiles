#!/bin/bash
# Remove git worktrees whose work is finished.
#
# A worktree is removed when it is clean and either its pull request has
# merged or closed, or it has no pull request and has not been touched
# for STALE_DAYS. Anything dirty, or on an open pull request, is kept.
#
# Defaults to a dry run. Pass --apply to actually remove.
#
# When run interactively, prints all results.
# When run by cron (no tty), only logs.

CODE_DIR="$HOME/code"
LOG_DIR="$HOME/.local/share/worktree-gc"
LOG_FILE="$LOG_DIR/last-run.log"
mkdir -p "$LOG_DIR"

APPLY=false
STALE_DAYS=30
ONLY_REPO=""
ONLY_ORG=""

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=true; shift ;;
    --dry-run) APPLY=false; shift ;;
    --stale-days) STALE_DAYS="$2"; shift 2 ;;
    --repo) ONLY_REPO="$2"; shift 2 ;;
    --org) ONLY_ORG="$2"; shift 2 ;;
    -h|--help)
      echo "usage: worktree-gc.sh [--apply] [--stale-days N]" \
        "[--org NAME] [--repo PATH]"
      exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

# Modification time in epoch seconds. BSD stat (macOS) and GNU stat (the
# Linux hub) spell this differently, and this job runs on both. Picked once
# rather than per worktree. Prints nothing if neither works, so callers must
# handle an empty result.
if stat -f %m . >/dev/null 2>&1; then
  mtime_of() { stat -f %m "$1" 2>/dev/null; }
else
  mtime_of() { stat -c %Y "$1" 2>/dev/null; }
fi

log() {
  printf '%s\n' "$1" >> "$LOG_FILE"
  $INTERACTIVE && printf '%s\n' "$1"
  return 0
}

logf() {
  printf '%-58s %s\n' "$1" "$2" >> "$LOG_FILE"
  $INTERACTIVE && printf '%-58s %s\n' "$1" "$2"
  return 0
}

: > "$LOG_FILE"
log "worktree-gc $(date '+%Y-%m-%d %H:%M:%S')"
$APPLY || log "DRY RUN - pass --apply to remove"
log ""

removed=0
kept_dirty=0
kept_open=0
kept_recent=0
kept_detached=0
kept_locked=0
pruned=0
reclaimed_kb=0

stale_secs=$((STALE_DAYS * 86400))
now=$(date +%s)

if [ -n "$ONLY_REPO" ]; then
  repos=("$ONLY_REPO")
else
  repos=()
  # Deliberately unquoted: quoting the default "*" makes it a literal
  # directory name rather than a glob, so the whole pattern matched nothing
  # and the script silently processed no repos at all. Org names have no
  # glob metacharacters, so an explicit --org still matches literally.
  org_glob="${ONLY_ORG:-*}"
  for gitdir in "$CODE_DIR"/$org_glob/*/.git; do
    [ -e "$gitdir" ] || continue
    repos+=("$(dirname "$gitdir")")
  done
fi

for repo in "${repos[@]}"; do
  git -C "$repo" rev-parse --git-dir >/dev/null 2>&1 || continue

  # Cheap check: skip repos with a single worktree.
  wt_count=$(git -C "$repo" worktree list --porcelain 2>/dev/null |
    grep -c '^worktree ')
  [ "${wt_count:-0}" -gt 1 ] || continue

  name=${repo#"$CODE_DIR"/}
  log "=== $name ($((wt_count - 1)) worktrees) ==="

  # owner/repo from the origin URL, so gh works without changing dir.
  origin=$(git -C "$repo" remote get-url origin 2>/dev/null)
  slug=$(printf '%s' "$origin" |
    sed -e 's|^git@github.com:||' \
        -e 's|^https://github.com/||' \
        -e 's|\.git$||')

  if [ -z "$slug" ]; then
    log "  skipped (no github origin)"
    log ""
    continue
  fi

  # Branch -> pull request state, fetched once per repo. If this query
  # fails every branch would look like "no PR", so bail out instead.
  if ! pr_raw=$(gh pr list -R "$slug" --state all --limit 1000 \
      --json headRefName,state \
      --jq '.[] | "\(.headRefName)\t\(.state)"' 2>/dev/null < /dev/null)
  then
    log "  skipped (could not read pull requests for $slug)"
    log ""
    continue
  fi

  declare -A pr_state=()
  while IFS=$'\t' read -r br st; do
    [ -n "$br" ] || continue
    # An open pull request wins over any earlier closed one.
    if [ "${pr_state[$br]}" != "OPEN" ]; then
      pr_state[$br]=$st
    fi
  done <<< "$pr_raw"

  # Parse worktrees into parallel path/branch lists.
  wt_path=""
  while IFS= read -r line; do
    case "$line" in
      worktree\ *)
        wt_path=${line#worktree }
        wt_branch=""
        wt_locked=false
        ;;
      branch\ refs/heads/*)
        wt_branch=${line#branch refs/heads/}
        ;;
      locked*)
        # Held by a live agent session; leave it alone.
        wt_locked=true
        ;;
      "")
        [ -n "$wt_path" ] || continue
        [ "${wt_path%/}" = "${repo%/}" ] && { wt_path=""; continue; }

        if [ ! -d "$wt_path" ]; then
          logf "  ${wt_path##*/}" "gone (prune)"
          pruned=$((pruned + 1))
          wt_path=""
          continue
        fi

        if $wt_locked; then
          logf "  ${wt_path##*/}" "keep (locked by a live session)"
          kept_locked=$((kept_locked + 1))
          wt_path=""
          continue
        fi

        if [ -z "$wt_branch" ]; then
          logf "  ${wt_path##*/}" "keep (detached HEAD)"
          kept_detached=$((kept_detached + 1))
          wt_path=""
          continue
        fi

        state=${pr_state[$wt_branch]:-NONE}
        dirty=$(git -C "$wt_path" status --porcelain 2>/dev/null | wc -l)
        # Treat an unreadable mtime as "just touched", so a stat failure
        # keeps the worktree rather than ageing it out.
        mtime=$(mtime_of "$wt_path")
        mtime=${mtime:-$now}
        age=$(( (now - mtime) / 86400 ))

        reason=""
        case "$state" in
          OPEN)
            logf "  ${wt_path##*/} [$wt_branch]" "keep (open PR)"
            kept_open=$((kept_open + 1))
            ;;
          MERGED|CLOSED)
            if [ "$dirty" -gt 0 ]; then
              logf "  ${wt_path##*/} [$wt_branch]" \
                "keep ($state, $dirty uncommitted)"
              kept_dirty=$((kept_dirty + 1))
            else
              reason="$state"
            fi
            ;;
          NONE)
            if [ "$dirty" -gt 0 ]; then
              logf "  ${wt_path##*/} [$wt_branch]" \
                "keep (no PR, $dirty uncommitted)"
              kept_dirty=$((kept_dirty + 1))
            elif [ $(( now - mtime )) -gt "$stale_secs" ]; then
              reason="no PR, ${age}d old"
            else
              logf "  ${wt_path##*/} [$wt_branch]" \
                "keep (no PR, ${age}d old)"
              kept_recent=$((kept_recent + 1))
            fi
            ;;
        esac

        if [ -n "$reason" ]; then
          size_kb=$(du -sk "$wt_path" 2>/dev/null | cut -f1)
          if $APPLY; then
            if git -C "$repo" worktree remove "$wt_path" 2>/dev/null; then
              logf "  ${wt_path##*/} [$wt_branch]" \
                "removed ($reason, $((size_kb / 1024))M)"
              removed=$((removed + 1))
              reclaimed_kb=$((reclaimed_kb + size_kb))
              [ "$state" = "MERGED" ] &&
                git -C "$repo" branch -D "$wt_branch" >/dev/null 2>&1
            else
              logf "  ${wt_path##*/} [$wt_branch]" "FAILED to remove"
            fi
          else
            logf "  ${wt_path##*/} [$wt_branch]" \
              "would remove ($reason, $((size_kb / 1024))M)"
            removed=$((removed + 1))
            reclaimed_kb=$((reclaimed_kb + size_kb))
          fi
        fi

        wt_path=""
        ;;
    esac
  done < <(git -C "$repo" worktree list --porcelain 2>/dev/null; echo)

  $APPLY && git -C "$repo" worktree prune 2>/dev/null
  unset pr_state
  log ""
done

log "---"
if $APPLY; then
  logf "removed" "$removed"
else
  logf "would remove" "$removed"
fi
logf "pruned (path gone)" "$pruned"
logf "kept (uncommitted changes)" "$kept_dirty"
logf "kept (open PR)" "$kept_open"
logf "kept (no PR, recent)" "$kept_recent"
logf "kept (detached HEAD)" "$kept_detached"
logf "kept (locked)" "$kept_locked"
logf "disk reclaimed" "$((reclaimed_kb / 1024)) MB"
logf "finished" "$(date '+%Y-%m-%d %H:%M:%S')"
