#!/usr/bin/env bash
# Move all comms app windows from the focused workspace to S.

BUNDLES=(
  net.whatsapp.WhatsApp
  org.whispersystems.signal-desktop
  com.apple.MobileSMS
  com.tinyspeck.slackmacgap
  com.microsoft.teams2
  com.microsoft.Outlook
)

pattern=$(printf '%s\n' "${BUNDLES[@]}" | paste -sd'|' -)

aerospace list-windows --workspace focused \
  --format '%{window-id}|%{app-bundle-id}' \
| grep -E "$pattern" \
| cut -d'|' -f1 \
| while read -r id; do
    aerospace move-node-to-workspace S --window-id "$id"
  done

exit 0
