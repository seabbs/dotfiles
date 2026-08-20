#!/usr/bin/env bash
# Launches gh dash from the mac (mac's gh auth), scoped to whichever repo is
# actually on screen. In a hub session the invoking pane is the mosh gateway,
# whose own cwd is fixed at wherever the gateway was first opened (usually
# dotfiles) and has nothing to do with the archie repo being viewed. Resolve
# archie's real current pane path over ssh instead, and translate it back to
# the equivalent ~/code/<org>/<repo> path on the mac (same layout on both
# hosts) so gh-dash's smartFilteringAtLaunch scopes to the right repo.
set -uo pipefail

GHD_CLIENT=$(tmux display-message -p '#{client_tty}')
export GHD_CLIENT

hub=$(tmux display-message -p '#{@hub}')
session=$(tmux display-message -p '#{session_name}')
dir="$HOME"

if [ "$hub" = "1" ]; then
  remote_path=$(ssh -o ConnectTimeout=3 -o BatchMode=yes "$session" '
    c=$(tmux list-clients -F "#{client_activity} #{client_name}" 2>/dev/null \
      | sort -rn | head -1 | cut -d" " -f2-)
    [ -n "$c" ] && tmux display-message -c "$c" -p "#{pane_current_path}"
  ' 2>/dev/null)
  rel="${remote_path#*/code/}"
  if [ -n "$remote_path" ] && [ "$rel" != "$remote_path" ] \
      && [ -d "$HOME/code/$rel" ]; then
    dir="$HOME/code/$rel"
  fi
else
  dir=$(tmux display-message -p '#{pane_current_path}')
fi

cd "$dir" 2>/dev/null || cd "$HOME"

GH_TOKEN=$(gh auth token --user seabbs)
export GH_TOKEN
exec gh dash
