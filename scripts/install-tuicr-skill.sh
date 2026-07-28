#!/usr/bin/env bash
# Install the tuicr skill for Claude Code into ~/.claude/skills/tuicr.
#
# The skill lets an agent open tuicr in a tmux split, then read the comments
# back with `tuicr review comments`. It lives in the tuicr repo rather than in
# the released binary, so fetch it instead of vendoring a copy that goes stale.
# Idempotent: re-run to update. Pi gets the same integration from the
# `npm:pi-tuicr` package declared in pi/settings.json.
set -euo pipefail

RAW="https://raw.githubusercontent.com/agavra/tuicr/main/skills/tuicr"
DEST="$HOME/.claude/skills/tuicr"
FILES=(SKILL.md tuicr-wrapper.sh tuicr-wrapper-zellij.sh)

echo "Installing the tuicr Claude Code skill into $DEST..."
mkdir -p "$DEST"

for file in "${FILES[@]}"; do
  tmp="$(mktemp)"
  if curl -fsSL "$RAW/$file" -o "$tmp"; then
    # mktemp is 0600; set the mode explicitly rather than inheriting it.
    chmod 644 "$tmp"
    mv "$tmp" "$DEST/$file"
    echo "  $file"
  else
    rm -f "$tmp"
    echo "  Warning: failed to fetch $file (leaving any existing copy)" >&2
  fi
done

# The skill invokes the wrappers directly.
chmod 755 "$DEST"/tuicr-wrapper*.sh 2>/dev/null || true

echo "Done. Restart Claude Code to pick up the skill."
