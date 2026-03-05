#!/usr/bin/env bash
# Move focused window to first empty workspace and follow it
export PATH="/opt/homebrew/bin:$PATH"
used=$(aerospace list-workspaces --monitor focused --non-empty)
for ws in 1 2 3 4 5 6 7 8 9; do
  if ! echo "$used" | grep -qx "$ws"; then
    aerospace move-node-to-workspace "$ws"
    aerospace workspace "$ws"
    break
  fi
done
