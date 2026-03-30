#!/usr/bin/env bash
# Toggle a scratchpad app between workspace S and the
# focused workspace.
# Gathers ALL windows for the bundle ID across every
# workspace so nothing gets stranded.
# Usage: aerospace-scratchpad.sh <bundle-id> <app-name>

BUNDLE_ID="$1"
APP_NAME="$2"

ws=$(aerospace list-workspaces --focused)

# Collect every window for this app across all workspaces
all=$(
  aerospace list-windows --all \
    --format '%{window-id}|%{app-bundle-id}|%{workspace}' \
  | grep -F "$BUNDLE_ID" || true
)

# If app has no windows at all, launch it
if [ -z "$all" ]; then
  open -a "$APP_NAME"
  for i in 1 2 3 4 5; do
    sleep 0.5
    all=$(
      aerospace list-windows --all \
        --format '%{window-id}|%{app-bundle-id}|%{workspace}' \
      | grep -F "$BUNDLE_ID" || true
    )
    [ -n "$all" ] && break
  done
  # Move newly launched windows to current workspace
  if [ -n "$all" ]; then
    first=true
    while IFS='|' read -r id _ _; do
      aerospace move-node-to-workspace "$ws" \
        --window-id "$id"
      if $first; then
        aerospace focus --window-id "$id"
        first=false
      fi
    done <<< "$all"
  fi
  exit 0
fi

# Decide direction: if ANY window is on the current
# workspace, send ALL to S. Otherwise pull ALL here.
on_current=$(echo "$all" | grep "|${ws}$" || true)

if [ -n "$on_current" ]; then
  # Hide: move every window to S
  while IFS='|' read -r id _ _ws; do
    [ "$_ws" = "S" ] && continue
    aerospace move-node-to-workspace S \
      --window-id "$id"
  done <<< "$all"
else
  # Show: move every window to current workspace
  first=true
  while IFS='|' read -r id _ _ws; do
    [ "$_ws" = "$ws" ] && continue
    aerospace move-node-to-workspace "$ws" \
      --window-id "$id"
    if $first; then
      aerospace focus --window-id "$id"
      first=false
    fi
  done <<< "$all"
fi
