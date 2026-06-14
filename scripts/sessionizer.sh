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
#   Ctrl-a  show all (sessions + projects + extras)
#   Ctrl-s  show active sessions only
#   Ctrl-p  show projects only
#   Ctrl-w  show worktrees across all repos
#   Ctrl-e  show extra roots only (home, notes, …)
#   Ctrl-d  kill selected session
#   Enter   switch to / create session
#           (unmatched query → session at $HOME)

CODE_DIR="${CODE_DIR:-$HOME/code}"

# Extra roots outside $CODE_DIR. Each entry is `name → path`;
# `name` becomes the tmux session name when picked.
declare -A EXTRA_ROOTS=(
  [home]="$HOME"
  [notes]="$HOME/Library/CloudStorage/GoogleDrive-s.e.abbott12@gmail.com/My Drive/cloud/apps/obsidian/notes"
)

# Remote hub hosts to span (space-separated ssh aliases), overridable via env.
HUB_HOSTS="${HUB_HOSTS:-archie}"
# Host scope for cross-machine listing: all | home | <hub host>. Cycled with
# C-r in the picker, reset to "all" on each launch.
HOST_STATE="$HOME/.cache/sessionizer-host"
mkdir -p "$HOME/.cache" 2>/dev/null
dbg() { [ -n "${SESSIONIZER_DEBUG:-}" ] && \
  echo "$(date '+%T') $*" >> /tmp/sessionizer-debug.log; }
host_scope() { cat "$HOST_STATE" 2>/dev/null || echo all; }
self_host() { hostname -s; }
# Hub hosts other than the current machine.
remote_hubs() {
  local h
  for h in $HUB_HOSTS; do [[ "$h" != "$(self_host)" ]] && echo "$h"; done
}
# Label for the current machine's own sessions: "home" on the mac, otherwise
# the hub's own name (so on archie its sessions read [archie], not [home]).
local_label() {
  local l="home" h
  for h in $HUB_HOSTS; do [[ "$h" == "$(self_host)" ]] && l="$h"; done
  echo "$l"
}

# Active sessions merged across home + hub hosts, most-recently-active first
# and deduped by name (the host is shown when picking a window in step 2).
# Respects the current host scope.
list_sessions() {
  local scope h; scope="$(host_scope)"
  local fmt='#{session_activity}|#{session_name}|#{@hub}'
  {
    # Local block first (current machine ranks first), each block ordered by
    # last activity; dedup keeps the local copy. @hub connection sessions (the
    # nested mosh sessions) are excluded — they are gateways, not work.
    [[ "$scope" == "all" || "$scope" == "home" ]] && tmux list-sessions \
      -F "$fmt" 2>/dev/null | awk -F'|' '$3!="1"' | sort -rn -t'|' -k1
    for h in $(remote_hubs); do
      [[ "$scope" == "all" || "$scope" == "$h" ]] && ssh "$h" \
        "tmux list-sessions -F '$fmt'" 2>/dev/null \
        | awk -F'|' '$3!="1"' | sort -rn -t'|' -k1
    done
  } | awk -F'|' 'NF && $2 && !seen[$2]++ {print "[active] " $2}'
}

list_projects() {
  local dirs=() org_dir org proj_dir proj
  for org_dir in "$CODE_DIR"/*/; do
    org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    for proj_dir in "$org_dir"*/; do
      [[ -d "$proj_dir" ]] || continue
      proj=$(basename "$proj_dir")
      [[ "$proj" == "worktrees" || "$proj" == worktree-* || "$proj" == .* ]] \
        && continue
      dirs+=("$proj_dir")
    done
  done
  [[ ${#dirs[@]} -gt 0 ]] || return 0
  # Order by last modified (most-recent first); ls -t works on mac and linux.
  ls -dt "${dirs[@]}" 2>/dev/null | sed "s|^$CODE_DIR/||; s|/\$||"
}

list_worktrees() {
  for org_dir in "$CODE_DIR"/*/; do
    org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    for proj_dir in "$org_dir"/*/; do
      [[ ! -d "$proj_dir" ]] && continue
      proj=$(basename "$proj_dir")
      [[ "$proj" == "worktrees" ]] && continue
      [[ "$proj" == worktree-* ]] && continue
      [[ "$proj" == .* ]] && continue
      local wt_dir="$proj_dir/worktrees"
      [[ ! -d "$wt_dir" ]] && continue
      for branch_dir in "$wt_dir"/*/; do
        [[ ! -d "$branch_dir" ]] && continue
        branch=$(basename "$branch_dir")
        echo "$org/$proj :: $branch"
      done
    done
  done
}

list_extras() {
  for name in "${!EXTRA_ROOTS[@]}"; do
    [[ -d "${EXTRA_ROOTS[$name]}" ]] && echo "[dir] $name"
  done | sort
}

list_all() {
  list_sessions
  echo "────────────"
  list_extras
  list_projects
}

list_windows() {
  local session="$1" scope h llbl; scope="$(host_scope)"; llbl="$(local_label)"
  # Tag each window with its machine, then sort all of them together by last
  # activity (global recency, not grouped by host).
  {
    [[ "$scope" == "all" || "$scope" == "$llbl" || "$scope" == "home" ]] && \
      tmux list-windows -t "=$session" \
        -F "#{window_activity}|[$llbl] #{window_index}:#{window_name}" 2>/dev/null
    for h in $(remote_hubs); do
      [[ "$scope" == "all" || "$scope" == "$h" ]] && ssh "$h" \
        "tmux list-windows -t '=$session' \
           -F '#{window_activity}|[$h] #{window_index}:#{window_name}'" \
        2>/dev/null
    done
  } | sort -rn -t'|' -k1 | cut -d'|' -f2-
}

# Mark a local session as a dormant hub gateway: @hub for listing/exclusion,
# plus per-session options so the outer tmux passes everything through and
# hides its status bar whenever this session is viewed.
flag_hub() {
  tmux set-option -t "$1" @hub 1
  tmux set-option -t "$1" prefix None
  tmux set-option -t "$1" key-table off
  tmux set-option -t "$1" status off
}

# Create a session on a hub host (if missing) and jump into its nested mosh
# session here. $1=hub  $2=session name  $3=working dir on the hub (e.g. ~).
create_hub_session() {
  local hub="$1" sname="$2" dir="$3" repo="${4:-}"
  dbg "create_hub_session hub=$hub sname=$sname dir=$dir repo=$repo"
  # Clone the repo on demand if it is not on the hub yet (gh credential helper
  # on the hub covers private repos).
  if [[ -n "$repo" ]]; then
    ssh "$hub" \
      "[ -d $dir ] || git clone https://github.com/$repo.git $dir" \
      2>/dev/null || true
  fi
  ssh "$hub" \
    "tmux has-session -t '=$sname' 2>/dev/null \
       || tmuxinator start project '$sname' '$dir' --no-attach" \
    2>/dev/null || true
  if tmux has-session -t "=$hub" 2>/dev/null; then
    ssh "$hub" "tmux switch-client -t '=$sname'" 2>/dev/null || true
  else
    tmux new-session -d -s "$hub" \
      "/bin/zsh -lc 'mosh $hub -- tmux attach -t $sname'"
    flag_hub "$hub"
  fi
  tmux switch-client -t "=$hub"
}

# The hub host currently filtered to (empty unless C-r is on a specific hub).
hub_scope() {
  local scope; scope="$(host_scope)"; local h
  for h in $(remote_hubs); do [ "$scope" = "$h" ] && { echo "$h"; return; }; done
}

# Handle flags for fzf reload
case "${1:-}" in
  --list-all)      list_all; exit 0 ;;
  --list-sessions) list_sessions; exit 0 ;;
  --list-projects)   list_projects; exit 0 ;;
  --list-worktrees)  list_worktrees; exit 0 ;;
  --list-extras)     list_extras; exit 0 ;;
  --cycle-host)
    cur="$(host_scope)"
    order=(all home $(remote_hubs))
    n=all
    for i in "${!order[@]}"; do
      [[ "${order[$i]}" == "$cur" ]] && \
        n="${order[$(( (i + 1) % ${#order[@]} ))]}" && break
    done
    echo "$n" > "$HOST_STATE"
    reload="${2:---list-all}"
    printf 'change-prompt(%s ❯ )+reload(%s %s)' "$n" "$0" "$reload"
    exit 0
    ;;
  --list-windows)    list_windows "$2"; exit 0 ;;
  --kill-session)
    tmux kill-session -t "=$2" 2>/dev/null
    for _h in $(remote_hubs); do
      ssh "$_h" "tmux kill-session -t '=$2'" 2>/dev/null
    done
    exit 0
    ;;
  --kill-window)
    session="$2"
    win_ref="$3"
    win_index="${win_ref%%:*}"
    win_name="${win_ref#*:}"
    # Get project root to check for worktree
    root=$(
      tmux display-message -t "=$session:1" \
        -p '#{pane_current_path}' 2>/dev/null
    )
    root=$(
      git -C "$root" worktree list 2>/dev/null \
        | awk 'NR==1 {print $1}' \
        || echo "$root"
    )
    # If worktree exists, use feat-done to clean up
    if [[ -d "$root/worktrees/$win_name" ]]; then
      zsh -ic "cd $root && feat-done $win_name" \
        2>/dev/null
    else
      tmux kill-window -t "=$session:$win_index" \
        2>/dev/null
    fi
    exit 0
    ;;
  --link-session)
    session="$2"
    # Create a grouped session with a unique name
    linked="${session}-$$"
    tmux new-session -d -t "=$session" -s "$linked"
    tmux switch-client -t "=$linked"
    exit 0
    ;;
esac

# A fresh launch spans all hosts.
echo all > "$HOST_STATE"

# Step 1: pick a session or project
result=$(list_all | fzf \
  --no-sort \
  --border-label ' sessions ' \
  --prompt '  ' \
  --header \
    'C-a all  C-s sessions  C-r host  C-p projects  C-w worktrees  C-e extras  C-d kill' \
  --print-query \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-a:change-prompt(  )+reload($0 --list-all)" \
  --bind "ctrl-s:change-prompt(  )+reload($0 --list-sessions)" \
  --bind "ctrl-r:transform($0 --cycle-host)" \
  --bind "ctrl-p:change-prompt(  )+reload($0 --list-projects)" \
  --bind "ctrl-w:change-prompt(  )+reload($0 --list-worktrees)" \
  --bind "ctrl-e:change-prompt(  )+reload($0 --list-extras)" \
  --bind "ctrl-d:execute-silent($0 --kill-session {2..})+reload($0 --list-all)" \
)
fzf_status=$?

# Cancelled with Esc / Ctrl-C
[[ $fzf_status -eq 130 ]] && exit 0

query=$(echo "$result" | sed -n '1p')
selected=$(echo "$result" | sed -n '2p')

# Nothing typed and nothing picked
[[ -z "$selected" && -z "$query" ]] && exit 0
[[ "$selected" == "────────────" ]] && exit 0

# Unmatched query: ad-hoc session named after the query. If filtered to a hub,
# create it there; otherwise locally at $HOME.
if [[ -z "$selected" && -n "$query" ]]; then
  session=$(echo "$query" | tr -c 'A-Za-z0-9_-' '-' | sed 's/^-*//;s/-*$//')
  [[ -z "$session" ]] && exit 0
  hub="$(hub_scope)"
  dbg "unmatched query=$query session=$session scope=$(host_scope) hub=$hub"
  if [[ -n "$hub" ]]; then
    create_hub_session "$hub" "$session" '~'
    exit 0
  fi
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project "$session" "$HOME" --no-attach
  fi
  tmux switch-client -t "=$session"
  exit 0
fi

# Resolve session name
if [[ "$selected" == "[active] "* ]]; then
  session="${selected#\[active\] }"

elif [[ "$selected" == "[dir] "* ]]; then
  session="${selected#\[dir\] }"
  project_root="${EXTRA_ROOTS[$session]}"
  if [[ -z "$project_root" || ! -d "$project_root" ]]; then
    exit 0
  fi
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi

elif [[ "$selected" == *" :: "* ]]; then
  # Worktree selection: org/repo :: branch
  local_project="${selected%% :: *}"
  branch="${selected##* :: }"
  project="${local_project##*/}"
  project_root="$CODE_DIR/$local_project"
  worktree_path="$project_root/worktrees/$branch"
  session="$project"

  # Ensure tmux session exists for the repo
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi

  # Check if window for this branch already exists
  existing_win=$(
    tmux list-windows -t "=$session" \
      -F '#{window_index}:#{window_name}' 2>/dev/null \
      | while IFS= read -r line; do
          [[ "${line#*:}" == "$branch" ]] && echo "$line" \
            && break
        done
  )

  if [[ -n "$existing_win" ]]; then
    win_index="${existing_win%%:*}"
    tmux switch-client -t "=$session"
    tmux select-window -t "=$session:$win_index"
  else
    # Create window with feat layout at worktree path
    repl="zsh"
    if [[ -f "$worktree_path/Project.toml" ]]; then
      repl="julia --project=."
    elif [[ -f "$worktree_path/DESCRIPTION" ]]; then
      repl="R"
    fi

    tmux new-window -t "=$session" -n "$branch" \
      -c "$worktree_path"
    tmux select-pane -T "nvim"
    tmux send-keys "nvim ." Enter
    tmux split-window -h -c "$worktree_path"
    tmux select-pane -T "ai:$branch"
    tmux send-keys "${AGENT_CLI_DEV_TOOL:-claude}" Enter
    tmux split-window -v -c "$worktree_path"
    tmux select-pane -T "repl"
    tmux send-keys "$repl" Enter
    tmux select-pane -t 0
    tmux switch-client -t "=$session"
  fi
  exit 0

else
  # Project path: create session if needed. If filtered to a hub, create it
  # there (same repo path under the hub's ~/code) and jump in.
  project="${selected##*/}"
  project_root="$CODE_DIR/$selected"
  session="$project"

  hub="$(hub_scope)"
  dbg "project selected=$selected session=$session scope=$(host_scope) hub=$hub"
  if [[ -n "$hub" ]]; then
    create_hub_session "$hub" "$session" "~/code/$selected" "$selected"
    exit 0
  fi
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi
fi

# Step 2: pick a window or type a new name
# --print-query outputs query on line 1, match on line 2
result=$(list_windows "$session" | fzf \
  --no-sort \
  --border-label " $session " \
  --prompt '  ' \
  --header 'Enter=select  C-r host  C-d=kill  C-l=linked view  Type=new' \
  --print-query \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-r:transform($0 --cycle-host \"--list-windows $session\")" \
  --bind "ctrl-d:execute-silent($0 --kill-window $session {2})+reload($0 --list-windows $session)" \
  --bind "ctrl-l:execute-silent($0 --link-session $session)+abort" \
)

query=$(echo "$result" | sed -n '1p')
match=$(echo "$result" | sed -n '2p')

# Escape with no input
[[ -z "$query" && -z "$match" ]] && exit 0

# Helper: resolve project root from session (main repo, not a worktree)
get_project_root() {
  local root
  root=$(
    tmux display-message -t "=$session:1" \
      -p '#{pane_current_path}' 2>/dev/null
  )
  git -C "$root" worktree list 2>/dev/null \
    | awk 'NR==1 {print $1}' \
    || echo "$root"
}

if [[ -n "$match" ]]; then
  # Matched an existing window: route by its host tag ([home]/[hub]).
  host_tag="${match%%] *}"; host_tag="${host_tag#[}"
  match="${match#\[*\] }"
  win_index="${match%%:*}"
  if [[ "$host_tag" == "$(local_label)" ]]; then
    tmux switch-client -t "=$session"
    tmux select-window -t "=$session:$win_index"
  else
    # Remote hub: switch to its nested mosh session here (created on demand,
    # flagged @hub for auto-passthrough). It lives inside this tmux.
    if tmux has-session -t "=$host_tag" 2>/dev/null; then
      # Existing connection: drive its attached client to the chosen window.
      ssh "$host_tag" \
        "tmux switch-client -t '=$session' \; select-window -t '=$session:$win_index'" \
        2>/dev/null || true
    else
      # First time: pre-select the target window on the host, then attach that
      # session directly via mosh (bypassing the home auto-attach) so we land
      # on the exact window, not the host's home session.
      ssh "$host_tag" "tmux select-window -t '=$session:$win_index'" \
        2>/dev/null || true
      tmux new-session -d -s "$host_tag" \
        "/bin/zsh -lc 'mosh $host_tag -- tmux attach -t $session'"
      flag_hub "$host_tag"
    fi
    tmux switch-client -t "=$host_tag"
  fi
else
  # No match: ask what kind of window to create
  win_type=$(printf "feature branch\nbare terminal" \
    | fzf \
      --no-sort \
      --border-label " new: $query " \
      --prompt '  ' \
      --header 'What kind of window?' \
  )

  [[ -z "$win_type" ]] && exit 0
  project_root=$(get_project_root)
  tmux switch-client -t "=$session"

  if [[ "$win_type" == "bare terminal" ]]; then
    tmux new-window -t "=$session" -n "$query" \
      -c "$project_root"
  else
    # Run feat in a temporary window that sources
    # the shell config, runs feat, then closes itself.
    # feat creates its own window with the full layout
    # so this runner window is just a launcher.
    tmux new-window -t "=$session" \
      -n "_launcher" -c "$project_root" \
      "zsh -ic 'feat $query; exit'"
  fi
fi
