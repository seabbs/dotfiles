#!/usr/bin/env bash
# Toggle a comms app between workspace S and the focused workspace.
# Usage: aerospace-scratchpad.sh <bundle-id> <app-name>

BUNDLE_ID="$1"
APP_NAME="$2"

ws=$(aerospace list-workspaces --focused)

# Check if app is on the current workspace — hide it
current_id=$(
  aerospace list-windows --workspace "$ws" \
    --format '%{window-id}|%{app-bundle-id}' \
  | grep -F "$BUNDLE_ID" \
  | head -1 \
  | cut -d'|' -f1 || true
)

if [ -n "$current_id" ]; then
  aerospace move-node-to-workspace S --window-id "$current_id"
  exit 0
fi

# Check if app is on workspace S — show it
scratch_id=$(
  aerospace list-windows --workspace S \
    --format '%{window-id}|%{app-bundle-id}' \
  | grep -F "$BUNDLE_ID" \
  | head -1 \
  | cut -d'|' -f1 || true
)

if [ -n "$scratch_id" ]; then
  aerospace move-node-to-workspace "$ws" \
    --window-id "$scratch_id"
  aerospace focus --window-id "$scratch_id"
  exit 0
fi

# App not running — launch it, then pull it to current workspace
open -a "$APP_NAME"
for i in 1 2 3 4 5; do
  sleep 0.5
  new_id=$(
    aerospace list-windows --all \
      --format '%{window-id}|%{app-bundle-id}' \
    | grep -F "$BUNDLE_ID" \
    | head -1 \
    | cut -d'|' -f1 || true
  )
  if [ -n "$new_id" ]; then
    aerospace move-node-to-workspace "$ws" \
      --window-id "$new_id"
    aerospace focus --window-id "$new_id"
    break
  fi
done
