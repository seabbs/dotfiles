#!/bin/bash
# Install launchd jobs by symlinking plists into ~/Library/LaunchAgents
# and loading them.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
AGENTS_DIR="$HOME/Library/LaunchAgents"

mkdir -p "$AGENTS_DIR"
mkdir -p "$HOME/.local/share/sync-repos"

for plist in "$SCRIPT_DIR"/*.plist; do
  [ -f "$plist" ] || continue
  name=$(basename "$plist")
  target="$AGENTS_DIR/$name"
  label="${name%.plist}"

  # Unload if already loaded
  launchctl bootout "gui/$(id -u)/$label" 2>/dev/null

  # Symlink into LaunchAgents
  ln -sf "$plist" "$target"

  # Load
  launchctl bootstrap "gui/$(id -u)" "$target"
  echo "Loaded $label"
done
