#!/bin/bash
# Cross-machine agent-session finder. Lists agent sessions on this machine and
# on archie (via agent-sessions.sh --list), fuzzy-pick one, and jump: switch
# that machine's tmux to the session and, for an archie pick from the mac,
# focus (or open) the archie ghostty window. From archie it lists archie only.
# C-a all / C-h home / C-r archie filter by host.
set -euo pipefail
AS=/opt/homebrew/bin/aerospace
GH=/Applications/Ghostty.app/Contents/MacOS/ghostty
self=$(hostname -s)
A="$HOME/code/seabbs/dotfiles/scripts/agent-sessions.sh"
RA='~/code/seabbs/dotfiles/scripts/agent-sessions.sh'

list() {  # $1 = host filter: all | home | archie
  local filter="${1:-all}"
  local local_label=home; [ "$self" = "archie" ] && local_label=archie
  if [ "$filter" = "all" ] || [ "$filter" = "$local_label" ]; then
    "$A" --list 2>/dev/null | sed "s/^/[$local_label] /"
  fi
  if [ "$self" != "archie" ] && { [ "$filter" = "all" ] || [ "$filter" = "archie" ]; }; then
    ssh archie "$RA --list" 2>/dev/null | sed 's/^/[archie] /'
  fi
}

if [ "${1:-}" = "--list" ]; then list "${2:-all}"; exit 0; fi

sel=$(list all | sed '/^$/d' | fzf \
  --delimiter=$'\t' --with-nth=1..4 \
  --prompt='all> ' --reverse --border-label ' agents (home + archie) ' \
  --header 'C-a all  C-h home  C-r archie' \
  --bind "ctrl-a:change-prompt(all> )+reload($0 --list all)" \
  --bind "ctrl-h:change-prompt(home> )+reload($0 --list home)" \
  --bind "ctrl-r:change-prompt(archie> )+reload($0 --list archie)") || exit 0

machine=home; printf '%s' "$sel" | grep -q '^\[archie\]' && machine=archie
sid=$(printf '%s' "$sel" | awk -F'\t' '{print $NF}')
[ -z "$sid" ] && exit 0

if [ "$machine" = "archie" ] && [ "$self" != "archie" ]; then
  ssh archie "$RA --switch '$sid'" 2>/dev/null || true
  win=$("$AS" list-windows --all 2>/dev/null \
    | grep -i ghostty | grep -i archie | head -1 | cut -d'|' -f1 | tr -d ' ')
  if [ -n "${win:-}" ]; then
    "$AS" focus --window-id "$win"
  else
    "$GH" -e bash -c 'export PATH="/opt/homebrew/bin:$PATH"; mosh archie'
  fi
else
  "$A" --switch "$sid"
fi
