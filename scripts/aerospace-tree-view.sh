#!/usr/bin/env bash
# Show workspace tree view
export PATH="/opt/homebrew/bin:$PATH"
echo "=== Workspaces ==="
for ws in $(aerospace list-workspaces --all); do
  windows=$(aerospace list-windows --workspace "$ws" \
    --format '%{app-name}: %{window-title}' 2>/dev/null)
  if [ -n "$windows" ]; then
    echo ""
    echo "[$ws]"
    echo "$windows" | sed 's/^/  /'
  fi
done
echo ""
read -n1 -p "Press any key to close"
