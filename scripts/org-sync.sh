#!/bin/bash
# Keep ~/code/<org>/ matching the GitHub org.
#
# Clones repos that exist in the org but not locally, fast-forwards the
# default branch of the ones that do, and reports clones whose repo has
# been renamed or that no longer belong to the org.
#
# Never deletes anything. Renames and orphans are reported only.
#
# When run interactively, prints all results.
# When run by cron (no tty), only logs.

CODE_DIR="$HOME/code"
LOG_DIR="$HOME/.local/share/org-sync"
LOG_FILE="$LOG_DIR/last-run.log"
mkdir -p "$LOG_DIR"

# Only orgs where every repo is wanted locally. Orgs cloned selectively
# (epiforecasts, JuliaEpi, ...) must be named explicitly, otherwise a
# nightly run would drag down a hundred repos nobody asked for.
DEFAULT_ORGS=(EpiAware)
DRY_RUN=false
MAX_CLONES=25
ORGS=()

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --max-clones) MAX_CLONES="$2"; shift 2 ;;
    -h|--help)
      echo "usage: org-sync.sh [--dry-run] [--max-clones N] [ORG ...]"
      exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 1 ;;
    *) ORGS+=("$1"); shift ;;
  esac
done

[ ${#ORGS[@]} -eq 0 ] && ORGS=("${DEFAULT_ORGS[@]}")

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

log() {
  printf '%s\n' "$1" >> "$LOG_FILE"
  $INTERACTIVE && printf '%s\n' "$1"
  return 0
}

logf() {
  printf '%-42s %s\n' "$1" "$2" >> "$LOG_FILE"
  $INTERACTIVE && printf '%-42s %s\n' "$1" "$2"
  return 0
}

: > "$LOG_FILE"
log "org-sync $(date '+%Y-%m-%d %H:%M:%S')"
$DRY_RUN && log "DRY RUN - nothing will be cloned"
log ""

cloned=0
updated=0
skipped=0
empty=0
renamed=0
orphaned=0

# Fast-forward a clone's default branch without disturbing the checkout.
# Mirrors the logic in sync-repos.sh.
update_default_branch() {
  local dir=$1 label=$2 branch current

  branch=$(git -C "$dir" symbolic-ref refs/remotes/origin/HEAD 2>/dev/null |
    sed 's@^refs/remotes/origin/@@')
  branch=${branch:-main}

  git -C "$dir" fetch origin --quiet 2>/dev/null

  current=$(git -C "$dir" branch --show-current 2>/dev/null)
  current=${current:-detached HEAD}
  if [ "$current" = "$branch" ]; then
    if git -C "$dir" pull --ff-only --quiet 2>/dev/null; then
      logf "  $label" "ok (pulled $branch)"
      updated=$((updated + 1))
    else
      logf "  $label" "skipped (dirty or diverged)"
      skipped=$((skipped + 1))
    fi
  else
    if git -C "$dir" fetch origin "$branch:$branch" --quiet 2>/dev/null; then
      logf "  $label" "ok ($branch updated, on $current)"
      updated=$((updated + 1))
    else
      logf "  $label" "skipped ($branch not fast-forwardable)"
      skipped=$((skipped + 1))
    fi
  fi
}

for org in "${ORGS[@]}"; do
  log "=== $org ==="
  org_dir="$CODE_DIR/$org"

  # Pipe separated, not tab: a repo with no default branch leaves the
  # middle field empty, and read collapses runs of whitespace delimiters.
  if ! remote_list=$(gh repo list "$org" --limit 200 --no-archived \
      --json name,isPrivate,defaultBranchRef \
      --jq '.[] | "\(.name)|\(.defaultBranchRef.name // "")|\(.isPrivate)"' \
      2>/dev/null < /dev/null) || [ -z "$remote_list" ]
  then
    log "  skipped (could not list repos)"
    log ""
    continue
  fi

  # Guard against pointing this at an org that is cloned selectively.
  want=$(grep -c '|' <<< "$remote_list")
  have=$(find "$org_dir" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)
  if [ "$((want - have))" -gt "$MAX_CLONES" ]; then
    log "  skipped: $((want - have)) missing (limit $MAX_CLONES)"
    log "  this org looks like it is cloned selectively; to take all of"
    log "  it anyway, re-run with --max-clones $((want - have))"
    log ""
    continue
  fi

  mkdir -p "$org_dir"

  # Map every local clone to the org repo its origin points at, so a
  # renamed repo is matched by URL rather than by directory name.
  declare -A local_by_name=()
  declare -A local_dirs=()
  for dir in "$org_dir"/*/ "$org_dir"/.*/; do
    dir=${dir%/}
    [ -d "$dir" ] || continue
    base=${dir##*/}
    [ "$base" = "." ] || [ "$base" = ".." ] && continue
    if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
      local_dirs[$base]="nogit"
      continue
    fi
    url=$(git -C "$dir" remote get-url origin 2>/dev/null)
    slug=$(printf '%s' "$url" |
      sed -e 's|^git@github.com:||' \
          -e 's|^https://github.com/||' \
          -e 's|\.git$||')
    local_dirs[$base]=$slug
    [ "${slug%%/*}" = "$org" ] && local_by_name[${slug#*/}]=$base
  done

  # Clone what is missing, update what is present.
  declare -A seen_dirs=()
  while IFS='|' read -r name branch private; do
    [ -n "$name" ] || continue

    if [ -z "$branch" ]; then
      logf "  $name" "empty (skipped)"
      empty=$((empty + 1))
      continue
    fi

    dir=${local_by_name[$name]:-}
    if [ -n "$dir" ]; then
      seen_dirs[$dir]=1
      # A repo whose name starts with a dot is cloned as dot-<name>, so
      # it is not hidden at the org root. That is not a rename.
      if [ "$dir" != "$name" ] && [ "$dir" != "dot-${name#.}" ]; then
        logf "  $dir" "renamed -> $name"
        renamed=$((renamed + 1))
        [ -n "${local_dirs[$name]:-}" ] &&
          logf "    " "correctly named clone already exists"
      fi
      update_default_branch "$org_dir/$dir" "$name"
      continue
    fi

    # Never create a hidden directory at the org root.
    target=$name
    [ "${name#.}" != "$name" ] && target="dot-${name#.}"

    vis="public"
    [ "$private" = "true" ] && vis="private"
    if $DRY_RUN; then
      logf "  $name" "would clone ($vis)"
      cloned=$((cloned + 1))
    elif gh repo clone "$org/$name" "$org_dir/$target" -- --quiet \
        2>/dev/null; then
      logf "  $name" "cloned ($vis)"
      seen_dirs[$target]=1
      cloned=$((cloned + 1))
    else
      logf "  $name" "clone FAILED"
      skipped=$((skipped + 1))
    fi
  done <<< "$remote_list"

  # Anything local that the org did not account for.
  for base in "${!local_dirs[@]}"; do
    [ -n "${seen_dirs[$base]:-}" ] && continue
    if [ "${local_dirs[$base]}" = "nogit" ]; then
      logf "  $base" "orphan (not a git repo)"
    else
      logf "  $base" "orphan (origin ${local_dirs[$base]})"
    fi
    orphaned=$((orphaned + 1))
  done

  unset local_by_name local_dirs seen_dirs
  log ""
done

log "---"
if $DRY_RUN; then
  logf "would clone" "$cloned"
else
  logf "cloned" "$cloned"
fi
logf "updated" "$updated"
logf "skipped" "$skipped"
logf "empty (not cloned)" "$empty"
logf "renamed (action needed)" "$renamed"
logf "orphaned (action needed)" "$orphaned"
logf "finished" "$(date '+%Y-%m-%d %H:%M:%S')"
