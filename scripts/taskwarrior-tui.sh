#!/usr/bin/env bash
# Launch taskwarrior-tui with `task` shimmed to Taskwarrior.
# PATH normally resolves `task` to go-task; the shim dir makes it Taskwarrior
# just for this process tree, so the TUI's internal `task` calls work.
set -euo pipefail

export TASKRC="${TASKRC:-$HOME/.config/task/taskrc}"
SHIM_DIR="$HOME/.local/share/tw-shim"

if [ ! -x "$SHIM_DIR/task" ]; then
  echo "Taskwarrior shim missing at $SHIM_DIR/task" >&2
  echo "Run scripts/link.sh to create it." >&2
  exit 1
fi

exec env PATH="$SHIM_DIR:$PATH" taskwarrior-tui "$@"
