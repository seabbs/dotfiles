#!/usr/bin/env bash
# Toggle a comms app between workspace S and the focused workspace.
# Moves ALL windows for the bundle ID, not just the first.
# Usage: aerospace-scratchpad.sh <bundle-id> <app-name>

BUNDLE_ID="$1"
APP_NAME="$2"

ws=$(aerospace list-workspaces --focused)

# Get all window IDs for this app on the current workspace
current_ids=$(
  aerospace list-windows --workspace "$ws" \
    --format '%{window-id}|%{app-bundle-id}' \
  | grep -F "$BUNDLE_ID" \
  | cut -d'|' -f1 || true
)

if [ -n "$current_ids" ]; then
  while IFS= read -r id; do
    aerospace move-node-to-workspace S --window-id "$id"
  done <<< "$current_ids"
  exit 0
fi

# Get all window IDs for this app on workspace S
scratch_ids=$(
  aerospace list-windows --workspace S \
    --format '%{window-id}|%{app-bundle-id}' \
  | grep -F "$BUNDLE_ID" \
  | cut -d'|' -f1 || true
)

if [ -n "$scratch_ids" ]; then
  first=true
  while IFS= read -r id; do
    aerospace move-node-to-workspace "$ws" \
      --window-id "$id"
    if $first; then
      aerospace focus --window-id "$id"
      first=false
    fi
  done <<< "$scratch_ids"
  exit 0
fi

# Get all stray windows on other workspaces — pull them in
stray_ids=$(
  aerospace list-windows --all \
    --format '%{window-id}|%{app-bundle-id}|%{workspace}' \
  | grep -F "$BUNDLE_ID" \
  | grep -v "|${ws}$" \
  | grep -v "|S$" \
  | cut -d'|' -f1 || true
)

if [ -n "$stray_ids" ]; then
  first=true
  while IFS= read -r id; do
    aerospace move-node-to-workspace "$ws" \
      --window-id "$id"
    if $first; then
      aerospace focus --window-id "$id"
      first=false
    fi
  done <<< "$stray_ids"
  exit 0
fi

# App not running — launch it, then pull all windows
open -a "$APP_NAME"
for i in 1 2 3 4 5; do
  sleep 0.5
  new_ids=$(
    aerospace list-windows --all \
      --format '%{window-id}|%{app-bundle-id}' \
    | grep -F "$BUNDLE_ID" \
    | cut -d'|' -f1 || true
  )
  if [ -n "$new_ids" ]; then
    first=true
    while IFS= read -r id; do
      aerospace move-node-to-workspace "$ws" \
        --window-id "$id"
      if $first; then
        aerospace focus --window-id "$id"
        first=false
      fi
    done <<< "$new_ids"
    break
  fi
done
