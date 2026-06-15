#!/usr/bin/env bash
# Fuzzy search REPL history via television and send
# the selected command to the calling tmux pane.
# Detects R/Julia/Python from the running process.

pane_pid=$(tmux display-message -p '#{pane_pid}')
pane_cmd=$(ps -o comm= -p "$pane_pid" 2>/dev/null)

# Walk child processes to find the actual REPL
child_cmd=$(
  ps -o comm= --ppid "$pane_pid" 2>/dev/null \
    || pgrep -laP "$pane_pid" 2>/dev/null
)

detect() {
  echo "$pane_cmd $child_cmd" | tr '[:upper:]' '[:lower:]'
}

repl=$(detect)

if echo "$repl" | grep -q "radian\|r --slave\| R "; then
  channel="r-history"
elif echo "$repl" | grep -q "julia"; then
  channel="julia-history"
elif echo "$repl" | grep -q "python\|ipython"; then
  channel="zsh-history"
else
  channel="zsh-history"
fi

selected=$(tv "$channel")

if [ -n "$selected" ]; then
  tmux send-keys "$selected"
fi
