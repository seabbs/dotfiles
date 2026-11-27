#!/usr/bin/env bash
# Open files for the user: in the nvim already running in this tmux
# session if there is one, otherwise in a new tmux split.
#
# Usage: open-in-nvim.sh [--split] [--no-focus] FILE[:LINE] ...
#   --split     always open a new tmux split
#   --no-focus  open in the running nvim without switching to its pane
#
# nvim publishes its server address on its tmux pane as @nvim_server
# (nvim/lua/config/autocmds.lua), and util/remote_open.lua picks an
# editing window so files never land in a terminal window.
set -euo pipefail

split=false
focus=true
files=()
while [ $# -gt 0 ]; do
  case "$1" in
    --split) split=true ;;
    --no-focus) focus=false ;;
    -h | --help) sed -n '2,8p' "$0"; exit 0 ;;
    *) files+=("$1") ;;
  esac
  shift
done

[ -n "${TMUX:-}" ] || { echo "open-in-nvim: not inside tmux" >&2; exit 1; }
[ "${#files[@]}" -gt 0 ] || { echo "open-in-nvim: no files given" >&2; exit 1; }

paths=()
lines=()
for f in "${files[@]}"; do
  line=0
  if [[ "$f" =~ ^(.*):([0-9]+)$ ]] && [ ! -e "$f" ]; then
    f="${BASH_REMATCH[1]}"
    line="${BASH_REMATCH[2]}"
  fi
  [ -e "$f" ] || { echo "open-in-nvim: no such file: $f" >&2; exit 1; }
  paths+=("$(cd "$(dirname "$f")" && pwd)/$(basename "$f")")
  lines+=("$line")
done

# A live nvim in this session, preferring the current window.
pane=""
sock=""
if ! $split; then
  while read -r id active server; do
    [ -n "${server:-}" ] && [ -S "$server" ] || continue
    if [ -z "$pane" ] || [ "$active" = 1 ]; then
      pane="$id"
      sock="$server"
    fi
    [ "$active" = 1 ] && break
  done < <(tmux list-panes -s -F '#{pane_id} #{window_active} #{@nvim_server}')
fi

if [ -n "$sock" ]; then
  for i in "${!paths[@]}"; do
    p="${paths[$i]//\'/\'\'}"
    nvim --server "$sock" --remote-expr \
      "v:lua.require'util.remote_open'.open('$p', ${lines[$i]})" >/dev/null
  done
  if $focus; then
    tmux select-window -t "$pane"
    tmux select-pane -t "$pane"
  fi
  exit 0
fi

first="${lines[0]}"
[ "$first" -gt 0 ] || first=1
cmd="nvim +$first"
for p in "${paths[@]}"; do
  cmd+=" $(printf '%q' "$p")"
done
tmux split-window -h -c "$(dirname "${paths[0]}")" "$cmd"
