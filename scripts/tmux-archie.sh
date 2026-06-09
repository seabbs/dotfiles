#!/bin/bash
# Toggle the current tmux client between its previous session and a dedicated
# "archie" session holding a mosh connection to the agents hub. Lets you flip
# laptop (home) <-> archie like switching tmux sessions, without opening a new
# terminal window.
set -euo pipefail

# On archie itself there is nowhere to jump to; just go to the last session.
if [ "$(hostname -s)" = "archie" ]; then
  tmux switch-client -l
  exit 0
fi

current=$(tmux display-message -p '#{session_name}')
if [ "$current" = "archie" ]; then
  # Already on archie: jump back to wherever we came from.
  tmux switch-client -l
elif tmux has-session -t archie 2>/dev/null; then
  tmux switch-client -t archie
else
  # Create the archie session on demand, running mosh via a login shell so
  # it finds mosh on PATH; it auto-attaches archie's tmux "home" session.
  tmux new-session -d -s archie "/bin/zsh -lc 'mosh archie'"
  tmux switch-client -t archie
fi
