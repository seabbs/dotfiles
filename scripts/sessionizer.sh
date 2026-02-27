#!/bin/bash
# tmux session switcher / project launcher
# Uses fzf to pick from active sessions + project dirs,
# then switches or creates via tmuxinator.
#
# Two-step flow:
#   1. Pick a session or project
#   2. If session has multiple windows, pick a window
#      or create a new feature branch
#
# Keybindings in session picker:
#   Ctrl-a  show all (sessions + projects)
#   Ctrl-s  show active sessions only
#   Ctrl-p  show projects only
#   Ctrl-d  kill selected session
#   Enter   switch to / create session

CODE_DIR="${CODE_DIR:-$HOME/code}"

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

list_windows() {
  local session="$1"
  tmux list-windows -t "=$session" \
    -F '#{window_index}:#{window_name}' 2>/dev/null \
    | while read -r w; do
      echo "$w"
    done
  echo "────────────"
  echo "[+ new feature branch]"
  echo "[+ bare terminal]"
}

# Handle flags for fzf reload
case "${1:-}" in
  --list-all)      list_all; exit 0 ;;
  --list-sessions) list_sessions; exit 0 ;;
  --list-projects) list_projects; exit 0 ;;
  --list-windows)  list_windows "$2"; exit 0 ;;
esac

# Step 1: pick a session or project
selected=$(list_all | fzf \
  --no-sort \
  --border-label ' sessions ' \
  --prompt '  ' \
  --header \
    'C-a all  C-s sessions  C-p projects  C-d kill' \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-a:change-prompt(  )+reload($0 --list-all)" \
  --bind "ctrl-s:change-prompt(  )+reload($0 --list-sessions)" \
  --bind "ctrl-p:change-prompt(  )+reload($0 --list-projects)" \
  --bind "ctrl-d:execute-silent(tmux kill-session -t {2..} 2>/dev/null)+reload($0 --list-all)" \
)

[[ -z "$selected" ]] && exit 0
[[ "$selected" == "────────────" ]] && exit 0

# Resolve session name
if [[ "$selected" == "[active] "* ]]; then
  session="${selected#\[active\] }"
else
  # Project path: create session if needed
  project="${selected##*/}"
  project_root="$CODE_DIR/$selected"
  session="$project"

  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi
fi

# Step 2: pick a window or create a feature branch
win_selected=$(list_windows "$session" | fzf \
  --no-sort \
  --border-label " $session " \
  --prompt '  ' \
  --header 'Select window or create feature branch' \
  --bind 'tab:down,btab:up' \
)

[[ -z "$win_selected" ]] && exit 0
[[ "$win_selected" == "────────────" ]] && exit 0

if [[ "$win_selected" == "[+ bare terminal]" ]]; then
  # Get project root for the working directory
  project_root=$(
    tmux display-message -t "=$session:1" \
      -p '#{pane_current_path}' 2>/dev/null
  )
  project_root=$(
    git -C "$project_root" rev-parse --show-toplevel \
      2>/dev/null || echo "$project_root"
  )
  tmux switch-client -t "=$session"
  tmux new-window -t "=$session" -c "$project_root"
elif [[ "$win_selected" == "[+ new feature branch]" ]]; then
  # Prompt for branch name
  printf "Branch name: "
  read -r branch
  [[ -z "$branch" ]] && exit 0

  # Switch to session first, then create feature window
  tmux switch-client -t "=$session"

  # Get the project root from the session's first pane
  project_root=$(
    tmux display-message -t "=$session:1" \
      -p '#{pane_current_path}' 2>/dev/null
  )
  # Walk up to find git root
  project_root=$(
    git -C "$project_root" rev-parse --show-toplevel \
      2>/dev/null || echo "$project_root"
  )

  # Create worktree and window (inline feat logic)
  wt="$project_root/worktrees/$branch"
  if [[ ! -d "$wt" ]]; then
    mkdir -p "$project_root/worktrees"
    git -C "$project_root" worktree add \
      "worktrees/$branch" -b "$branch" main
  fi

  repl="zsh"
  if [[ -f "$wt/Project.toml" ]]; then
    repl="julia --project=."
  elif [[ -f "$wt/DESCRIPTION" ]]; then
    repl="R"
  fi

  t="$session:$branch"
  tmux new-window -t "=$session" -n "$branch" -c "$wt"
  tmux select-pane -t "$t.0" -T "nvim"
  tmux send-keys -t "$t.0" "nvim ." Enter
  tmux split-window -t "$t" -h -c "$wt"
  tmux select-pane -t "$t.1" -T "agent"
  tmux send-keys -t "$t.1" \
    "${AGENT_CLI_DEV_TOOL:-happy}" Enter
  tmux split-window -t "$t.1" -v -c "$wt"
  tmux select-pane -t "$t.2" -T "repl"
  tmux send-keys -t "$t.2" "$repl" Enter
  tmux select-pane -t "$t.0"
  tmux select-window -t "$t"
else
  # Switch to the selected window
  win_index="${win_selected%%:*}"
  tmux switch-client -t "=$session"
  tmux select-window -t "=$session:$win_index"
fi
