#!/usr/bin/env bash
# Open a new Ghostty window and a new Arc window on the current workspace.
# Both tile automatically side by side.

osascript -e '
  tell application "Ghostty" to activate
  tell application "System Events"
    keystroke "n" using command down
  end tell
'

sleep 0.3

osascript -e '
  tell application "Arc" to activate
  tell application "System Events"
    keystroke "n" using command down
  end tell
'
