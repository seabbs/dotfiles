#!/bin/bash
# Cross-machine tmux window finder. Lists windows on this machine and on archie,
# fuzzy-pick one, and jump to it: switch that machine's tmux to the window and,
# for an archie pick from the mac, focus (or open) the archie ghostty window.
# Run inside a tmux display-popup. From archie it lists archie windows only.
# C-a all / C-h home / C-r archie filter by host.
set -euo pipefail
AS=/opt/homebrew/bin/aerospace
GH=/Applications/Ghostty.app/Contents/MacOS/ghostty
self=$(hostname -s)
fmt='#{session_name}:#{window_index} #{window_name} #{pane_current_path}'

list() {  # $1 = host filter: all | home | archie
  local filter="${1:-all}"
  local local_label=home; [ "$self" = "archie" ] && local_label=archie
  if [ "$filter" = "all" ] || [ "$filter" = "$local_label" ]; then
    tmux list-windows -a -F "$fmt" 2>/dev/null | sed "s/^/[$local_label] /"
  fi
  if [ "$self" != "archie" ] && { [ "$filter" = "all" ] || [ "$filter" = "archie" ]; }; then
    ssh archie "tmux list-windows -a -F '$fmt'" 2>/dev/null | sed 's/^/[archie] /'
  fi
}

# --list mode used by fzf reloads.
if [ "${1:-}" = "--list" ]; then list "${2:-all}"; exit 0; fi

sel=$(list all | sed '/^$/d' | fzf \
  --prompt='all> ' --reverse --border-label ' windows (home + archie) ' \
  --header 'C-a all  C-h home  C-r archie' \
  --bind "ctrl-a:change-prompt(all> )+reload($0 --list all)" \
  --bind "ctrl-h:change-prompt(home> )+reload($0 --list home)" \
  --bind "ctrl-r:change-prompt(archie> )+reload($0 --list archie)") || exit 0

machine=$(printf '%s' "$sel" | sed -E 's/^\[([^]]+)\].*/\1/')
target=$(printf '%s' "$sel" | awk '{print $2}')   # session:index
session=${target%:*}

if [ "$machine" = "archie" ] && [ "$self" != "archie" ]; then
  ssh archie "tmux switch-client -t '$session' \\; select-window -t '$target'" \
    2>/dev/null || true
  win=$("$AS" list-windows --all 2>/dev/null \
    | grep -i ghostty | grep -i archie | head -1 | cut -d'|' -f1 | tr -d ' ')
  if [ -n "${win:-}" ]; then
    "$AS" focus --window-id "$win"
  else
    "$GH" -e bash -c 'export PATH="/opt/homebrew/bin:$PATH"; mosh archie'
  fi
else
  tmux switch-client -t "$session" \; select-window -t "$target"
fi
