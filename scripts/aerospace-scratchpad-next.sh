#!/usr/bin/env bash
# Cycle the next comms app window from S to the focused workspace.

BUNDLES=(
  net.whatsapp.WhatsApp
  org.whispersystems.signal-desktop
  com.apple.MobileSMS
  com.tinyspeck.slackmacgap
  com.microsoft.teams2
  com.microsoft.Outlook
)

pattern=$(printf '%s\n' "${BUNDLES[@]}" | paste -sd'|' -)

id=$(
  aerospace list-windows --workspace S \
    --format '%{window-id}|%{app-bundle-id}' \
  | grep -E "$pattern" \
  | head -1 \
  | cut -d'|' -f1 || true
)

if [ -n "$id" ]; then
  ws=$(aerospace list-workspaces --focused)
  aerospace move-node-to-workspace "$ws" --window-id "$id"
  aerospace focus --window-id "$id"
fi
