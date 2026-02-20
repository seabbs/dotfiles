#!/bin/bash
# Update Julia via juliaup and precompile active projects.
# "Active" means the repo was modified within the last 30 days.
# Safe to run from cron or interactively.

CODE_DIR="$HOME/code"
STALE_DAYS=30
LOG_DIR="$HOME/.local/share/julia-maintenance"
LOG_FILE="$LOG_DIR/last-run.log"
mkdir -p "$LOG_DIR"

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

log() {
  printf "%-50s %s\n" "$1" "$2" >> "$LOG_FILE"
  $INTERACTIVE && printf "%-50s %s\n" "$1" "$2"
}

: > "$LOG_FILE"
log "julia-maintenance" "$(date '+%Y-%m-%d %H:%M:%S')"

# Update juliaup channels
if command -v juliaup &>/dev/null; then
  juliaup update >> "$LOG_FILE" 2>&1
  log "juliaup" "updated"
else
  log "juliaup" "not found, skipping update"
fi

JULIA="julia"
if ! command -v "$JULIA" &>/dev/null; then
  log "julia" "not found, aborting"
  exit 1
fi

log "julia" "$($JULIA --version 2>&1)"

# Precompile default environment (startup.jl packages)
log "@v#.# (default env)" "precompiling..."
$JULIA -e 'using Pkg; Pkg.precompile()' >> "$LOG_FILE" 2>&1
log "@v#.# (default env)" "done"

# Find active Julia projects and precompile them
precompiled=0
skipped=0

while IFS= read -r toml; do
  dir=$(dirname "$toml")
  name=${dir#"$CODE_DIR"/}

  # Skip archived repos
  case "$name" in archive/*) skipped=$((skipped + 1)); continue;; esac

  # Skip stale repos (no file modified in last N days)
  recent=$(find "$dir" -maxdepth 2 -name "*.jl" \
    -newer "$dir/Project.toml" -o \
    -name "Project.toml" -mtime "-${STALE_DAYS}" \
    2>/dev/null | head -1)
  if [ -z "$recent" ]; then
    # Check if the Project.toml itself was modified recently
    if ! find "$dir/Project.toml" -mtime "-${STALE_DAYS}" \
        -print -quit 2>/dev/null | grep -q .; then
      log "$name" "skipped (stale)"
      skipped=$((skipped + 1))
      continue
    fi
  fi

  log "$name" "precompiling..."
  $JULIA --project="$dir" \
    -e 'using Pkg; Pkg.instantiate(); Pkg.precompile()' \
    >> "$LOG_FILE" 2>&1
  log "$name" "done"
  precompiled=$((precompiled + 1))
done < <(find "$CODE_DIR" -maxdepth 4 -name "Project.toml" \
  -not -path "*/archive/*" \
  -not -path "*/.julia/*" \
  -not -path "*/.git/*" \
  2>/dev/null | sort)

log "---" ""
log "done" "$precompiled precompiled, $skipped skipped"
log "finished" "$(date '+%Y-%m-%d %H:%M:%S')"
