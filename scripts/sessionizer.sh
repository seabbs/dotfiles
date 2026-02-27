#!/bin/bash
# tmux session switcher / project launcher
# Uses fzf to pick from active sessions + project dirs,
# then switches or creates via tmuxinator.
#
# Designed to run inside a tmux display-popup.
# Keybindings inside the picker:
#   Ctrl-a  show all (sessions + projects)
#   Ctrl-s  show active sessions only
#   Ctrl-p  show projects only
#   Ctrl-d  kill selected session
#   Enter   switch to / create session

CODE_DIR="${CODE_DIR:-$HOME/code}"
AGENT_CLI_DEV_TOOL="${AGENT_CLI_DEV_TOOL:-happy}"

list_sessions() {
  tmux list-sessions -F '#{session_name}' 2>/dev/null \
    | while read -r s; do
      echo "[active] $s"
    done
}

list_projects() {
  for org_dir in "$CODE_DIR"/*/; do
    org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    for proj_dir in "$org_dir"/*/; do
      [[ ! -d "$proj_dir" ]] && continue
      proj=$(basename "$proj_dir")
      [[ "$proj" == "worktrees" ]] && continue
      [[ "$proj" == worktree-* ]] && continue
      [[ "$proj" == .* ]] && continue
      echo "$org/$proj"
    done
  done
}

list_all() {
  list_sessions
  echo "────────────"
  list_projects
}

# Handle --list-* flags for fzf reload
case "${1:-}" in
  --list-all)      list_all; exit 0 ;;
  --list-sessions) list_sessions; exit 0 ;;
  --list-projects) list_projects; exit 0 ;;
esac

selected=$(list_all | fzf \
  --no-sort --border-label ' sessions ' \
  --prompt '  ' \
  --header 'C-a all  C-s sessions  C-p projects  C-d kill' \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-a:change-prompt(  )+reload($0 --list-all)" \
  --bind "ctrl-s:change-prompt(  )+reload($0 --list-sessions)" \
  --bind "ctrl-p:change-prompt(  )+reload($0 --list-projects)" \
  --bind "ctrl-d:execute-silent(tmux kill-session -t {2..} 2>/dev/null)+reload($0 --list-all)" \
)

[[ -z "$selected" ]] && exit 0
[[ "$selected" == "────────────" ]] && exit 0

if [[ "$selected" == "[active] "* ]]; then
  # Switch to existing session
  session="${selected#\[active\] }"
  tmux switch-client -t "=$session"
else
  # Create new project session from org/project path
  project="${selected##*/}"
  project_root="$CODE_DIR/$selected"

  if tmux has-session -t "=$project" 2>/dev/null; then
    tmux switch-client -t "=$project"
  else
    tmuxinator start project \
      "$project" "$project_root" --no-attach
    tmux switch-client -t "=$project"
  fi
fi
