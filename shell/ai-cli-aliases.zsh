# AI CLI Tool Configuration
# Set AGENT_CLI_PRIMARY_TOOL to your preferred primary AI CLI (e.g., 'claude', 'gemini')
# Defaults to 'claude' if not set.
: ${AGENT_CLI_PRIMARY_TOOL:=claude}

# Set AGENT_CLI_DEV_TOOL to your preferred development-focused AI CLI (e.g., 'happy', 'gemini')
# Defaults to 'happy' if not set.
: ${AGENT_CLI_DEV_TOOL:=happy}

# Root directory for code repositories, organised by GitHub org
# Defaults to ~/code if not set.
: ${CODE_DIR:=$HOME/code}

# Smart tmux-claude launcher
tc() {
  local command_name="$1"

  # Only shift if we have arguments to pass to claude
  if [[ -n "$command_name" ]]; then
    shift
  fi

  # Build session prefix from command name + repo/branch
  local session_prefix=""

  if [[ -n "$command_name" ]]; then
    session_prefix="${command_name}"
  fi

  if git rev-parse --git-dir > /dev/null 2>&1; then
    local repo=$(basename "$(git rev-parse --show-toplevel)")
    local branch=$(git branch --show-current 2>/dev/null || echo "detached")
    if [[ -n "$session_prefix" ]]; then
      session_prefix="${session_prefix}-${repo}-${branch}"
    else
      session_prefix="${repo}-${branch}"
    fi
  else
    # Not in a git repo, use directory name
    local dir_name=$(basename "$PWD")
    if [[ -n "$session_prefix" ]]; then
      session_prefix="${session_prefix}-${dir_name}"
    else
      session_prefix="${dir_name}"
    fi
  fi

  # Clean up session name (tmux doesn't like certain chars)
  session_prefix=$(echo "$session_prefix" | sed 's/[^a-zA-Z0-9_-]/_/g')

  # Find existing sessions with this exact prefix or numbered versions
  local -a existing_sessions
  while IFS= read -r session; do
    existing_sessions+=("$session")
  done < <(tmux list-sessions -F '#{session_name}' 2>/dev/null | grep -E "^${session_prefix}(-[0-9]+)?$" || true)

  if [[ ${#existing_sessions[@]} -eq 1 ]]; then
    # Exactly one session exists, attach to it
    echo "Attaching to existing session: ${existing_sessions[1]}"
    tmux attach-session -t "${existing_sessions[1]}"
  elif [[ ${#existing_sessions[@]} -eq 0 ]]; then
    # No sessions exist, create the first one
    local session_name="${session_prefix}"
    echo "Creating new session: ${session_name}"
    if [[ -n "$command_name" ]]; then
      tmux new-session -s "$session_name" "${AGENT_CLI_PRIMARY_TOOL}" "$command_name" "$@"
    else
      tmux new-session -s "$session_name" "${AGENT_CLI_PRIMARY_TOOL}"
    fi
  else
    # Multiple sessions exist, find next available number
    local max_num=0
    for session in "${existing_sessions[@]}"; do
      if [[ "$session" =~ ^${session_prefix}-([0-9]+)$ ]]; then
        local num="${BASH_REMATCH[1]}"
        (( num > max_num )) && max_num=$num
      elif [[ "$session" == "$session_prefix" ]]; then
        # The base session exists, so next one should be -1
        (( 0 > max_num )) && max_num=0
      fi
    done
    local new_num=$((max_num + 1))
    local session_name="${session_prefix}-${new_num}"
    echo "Creating new session: ${session_name}"
    if [[ -n "$command_name" ]]; then
      tmux new-session -s "$session_name" "${AGENT_CLI_PRIMARY_TOOL}" "$command_name" "$@"
    else
      tmux new-session -s "$session_name" "${AGENT_CLI_PRIMARY_TOOL}"
    fi
  fi
}

# Claude Code custom command aliases
# General model aliases
alias haiku='${AGENT_CLI_PRIMARY_TOOL} --model haiku'
alias sonnet='${AGENT_CLI_PRIMARY_TOOL} --model sonnet'

# Specialized command aliases (using tmux)
alias commit='tc commit --model haiku commit'
alias github-dashboard='tc github-dashboard github-dashboard'
alias improve-coverage='tc improve-coverage improve-coverage'
alias issue-reply='tc issue-reply issue-reply'
alias issue-summary='tc issue-summary issue-summary'
alias lint='tc lint --model sonnet lint'
alias literature-search='tc literature-search literature-search'
alias pr='tc pr --model sonnet pr'
alias preprint-search='tc preprint-search preprint-search'
alias review='tc review review'
alias scan-issues='tc scan-issues scan-issues'
alias test='tc test --model sonnet test'
alias uk-news='tc uk-news uk-news'
alias update-deps='tc update-deps --model sonnet update-deps'
alias docs='tc docs --model sonnet docs'
alias list-ai-cli-aliases='alias | grep "${AGENT_CLI_PRIMARY_TOOL}" | sort'

# Aliases with common arguments
alias pr-here='${AGENT_CLI_PRIMARY_TOOL} pr $(gh issue list --limit 1 --json number --jq ".[0].number")'
alias review-last='${AGENT_CLI_PRIMARY_TOOL} review $(git diff --name-only HEAD~1)'
alias scan-current='${AGENT_CLI_PRIMARY_TOOL} scan-issues .'
alias summarise-last='${AGENT_CLI_PRIMARY_TOOL} issue-summary $(gh issue list --limit 1 --json number --jq ".[0].number")'

# Daily work preparation system
alias daily='~/spaceship/daily-work-prep/view-daily-summary.sh'
alias daily-all='~/spaceship/daily-work-prep/view-daily-summary.sh all'
alias daily-run='~/spaceship/daily-work-prep/run-all-daily.sh'

# Claude workspace aliases
alias claude-spaceship='cd ~/spaceship && ${AGENT_CLI_PRIMARY_TOOL}'
alias spaceship='cd ~/spaceship'

# =============================================================================
# Gemini specific functions
# =============================================================================

# Start a gemini project session with tmuxinator
# Usage: gproj <project-name>
gproj() {
  AGENT_CLI_DEV_TOOL="gemini" proj "$@"
}

# Start a gemini agent session
# Usage: gagent [project] [worktree]
gagent() {
  AGENT_CLI_DEV_TOOL="gemini" agent "$@"
}

# Create a new worktree window for gemini agent session
# Usage: gagent-feat <branch-name> [base-branch]
gagent-feat() {
  AGENT_CLI_DEV_TOOL="gemini" agent-feat "$@"
}

# =============================================================================
# tmux workflow functions
# =============================================================================

# Start a project session with tmuxinator
# Usage: proj <project-name>
# Supports partial name matching (e.g., proj epi -> epinowcast)
proj() {
  local input="$1"
  local branch="$2"
  if [[ -z "$input" ]]; then
    echo "Usage: proj <project-name|.> [branch]"
    return 1
  fi

  # Resolve project name and root path
  local project_path
  local project
  local project_root
  if [[ "$input" == "." ]]; then
    project="home"
    project_root="$CODE_DIR"
  else
    project_path=$(_find_project "$input")
    if [[ $? -ne 0 ]]; then
      return 1
    fi
    project="${project_path##*/}"
    project_root="$CODE_DIR/$project_path"
  fi

  # Start session if it doesn't exist
  local needs_attach=false
  if tmux has-session -t "$project" 2>/dev/null; then
    needs_attach=true
  elif [[ -n "$branch" ]]; then
    # Start detached so we can add feature window first
    tmuxinator start project \
      "$project" "$project_root" --no-attach
    needs_attach=true
  else
    tmuxinator start project "$project" "$project_root"
    return
  fi

  # Create feature worktree window if branch specified
  if [[ -n "$branch" ]]; then
    local root="$project_root"
    local wt="$root/worktrees/$branch"
    if [[ ! -d "$wt" ]]; then
      mkdir -p "$root/worktrees"
      git -C "$root" worktree add \
        "worktrees/$branch" -b "$branch" main
    fi

    local repl="zsh"
    if [[ -f "$wt/Project.toml" ]]; then
      repl="julia --project=."
    elif [[ -f "$wt/DESCRIPTION" ]]; then
      repl="R"
    fi

    local t="$project:$branch"
    tmux new-window -t "$project" -n "$branch" -c "$wt"
    tmux select-pane -t "$t.0" -T "nvim"
    tmux send-keys -t "$t.0" "nvim ." Enter
    tmux split-window -t "$t" -h -c "$wt"
    tmux select-pane -t "$t.1" -T "happy:$branch"
    tmux send-keys -t "$t.1" \
      "${AGENT_CLI_DEV_TOOL}" Enter
    tmux split-window -t "$t.1" -v -c "$wt"
    tmux select-pane -t "$t.2" -T "repl"
    tmux send-keys -t "$t.2" "$repl" Enter
    tmux select-pane -t "$t.0"
    tmux select-window -t "$t"
  fi

  if $needs_attach; then
    tmux attach -t "$project"
  fi
}

# Create a new feature worktree as a window in the current session
# Usage: feat <branch-name> [base-branch]
feat() {
  local branch="$1"
  local base="${2:-main}"

  if [[ -z "$branch" ]]; then
    echo "Usage: feat <branch-name> [base-branch]"
    return 1
  fi

  # Must be in tmux
  if [[ -z "$TMUX" ]]; then
    echo "Error: Not in a tmux session"
    return 1
  fi

  # Get project root (navigate up to find .git)
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$root" ]]; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local worktree_path="$root/worktrees/$branch"

  # Create worktree if needed
  if [[ ! -d "$worktree_path" ]]; then
    mkdir -p "$root/worktrees"
    git -C "$root" worktree add "worktrees/$branch" -b "$branch" "$base"
  fi

  # Detect REPL type
  local repl="zsh"
  if [[ -f "$worktree_path/Project.toml" ]]; then
    repl="julia --project=."
  elif [[ -f "$worktree_path/DESCRIPTION" ]]; then
    repl="R"
  fi

  # Create new window with standard layout
  tmux new-window -n "$branch" -c "$worktree_path"

  # Pane 0: nvim (left)
  tmux select-pane -T "nvim"
  tmux send-keys "nvim ." Enter

  # Pane 1: happy (top-right)
  tmux split-window -h -c "$worktree_path"
  tmux select-pane -T "happy:$branch"
  tmux send-keys "${AGENT_CLI_DEV_TOOL}" Enter

  # Pane 2: REPL (bottom-right)
  tmux split-window -v -c "$worktree_path"
  tmux select-pane -T "repl"
  tmux send-keys "$repl" Enter

  # Return focus to nvim
  tmux select-pane -t 0
}

# Clean up a feature worktree and close its window
# Usage: feat-done <branch-name>
feat-done() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    echo "Usage: feat-done <branch-name>"
    return 1
  fi

  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$root" ]]; then
    echo "Error: Not in a git repository"
    return 1
  fi

  # Close tmux window if it exists
  tmux kill-window -t "$branch" 2>/dev/null

  # Remove worktree
  if [[ -d "$root/worktrees/$branch" ]]; then
    git -C "$root" worktree remove "worktrees/$branch"
    echo "Removed worktree: $branch"
  else
    echo "Worktree not found: $branch"
  fi
}

# List all feature worktrees
feat-list() {
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$root" ]]; then
    echo "Error: Not in a git repository"
    return 1
  fi

  git -C "$root" worktree list
}

# =============================================================================
# Project discovery
# =============================================================================

# Find a project by partial name match
# Searches ~/code/{org}/ subdirectories (two levels deep)
# Returns org/project path so $CODE_DIR/$result works
# Skips archive/ and worktree directories
# Usage: _find_project <partial-name>
_find_project() {
  local partial="$1"
  local code_dir="$CODE_DIR"

  # Empty input
  if [[ -z "$partial" ]]; then
    return 1
  fi

  # Support explicit org/project format
  if [[ "$partial" == */* && -d "$code_dir/$partial" ]]; then
    echo "$partial"
    return 0
  fi

  # Collect all org/project pairs, skipping archive
  local -a all_projects
  for org_dir in "$code_dir"/*/; do
    local org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    for proj_dir in "$org_dir"/*/; do
      [[ ! -d "$proj_dir" ]] && continue
      local proj=$(basename "$proj_dir")
      # Skip non-project directories
      [[ "$proj" == "worktrees" ]] && continue
      [[ "$proj" == worktree-* ]] && continue
      [[ "$proj" == .dev ]] && continue
      [[ "$proj" == .git ]] && continue
      [[ "$proj" == .* ]] && continue
      all_projects+=("$org/$proj")
    done
  done

  # Exact match on project name (ignoring org)
  local -a matches
  for entry in "${all_projects[@]}"; do
    local proj="${entry##*/}"
    if [[ "$proj" == "$partial" ]]; then
      matches+=("$entry")
    fi
  done

  # If no exact match, try partial (case-insensitive)
  if [[ ${#matches[@]} -eq 0 ]]; then
    for entry in "${all_projects[@]}"; do
      local proj="${entry##*/}"
      if [[ "${proj:l}" == "${partial:l}"* ]]; then
        matches+=("$entry")
      fi
    done
  fi

  if [[ ${#matches[@]} -eq 0 ]]; then
    echo "Error: No project matching '$partial'" >&2
    return 1
  elif [[ ${#matches[@]} -eq 1 ]]; then
    echo "${matches[1]}"
    return 0
  else
    echo "Error: Multiple projects match '$partial':" >&2
    printf "  %s\n" "${matches[@]}" >&2
    return 1
  fi
}

# List available projects from ~/code/{org}/ subdirs
# Usage: lsproj [filter]
lsproj() {
  local filter="$1"
  local code_dir="$CODE_DIR"

  echo "Available projects (by org):"
  echo "============================"

  for org_dir in "$code_dir"/*/; do
    local org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    local found=false
    for proj_dir in "$org_dir"/*/; do
      [[ ! -d "$proj_dir" ]] && continue
      local proj=$(basename "$proj_dir")
      [[ "$proj" == "worktrees" ]] && continue
      [[ "$proj" == worktree-* ]] && continue
      [[ "$proj" == .dev ]] && continue
      if [[ -z "$filter" ]] || \
         echo "$proj" | grep -qi "$filter"; then
        if ! $found; then
          echo "  $org/"
          found=true
        fi
        echo "    $proj"
      fi
    done
  done
}

# =============================================================================
# Agent session management
# =============================================================================

# Start a simple agent session (just Claude Code in tmux)
# Usage: agent [project] [worktree]
#   agent                    - use current project
#   agent <name>             - worktree in current repo OR ~/code/<name>
#   agent <project> <wt>     - create/use worktree in ~/code/<project>
# Supports partial name matching (e.g., agent epi -> epinowcast)
agent() {
  local input="$1"
  local worktree="$2"
  local work_dir=""
  local session_name=""
  local project=""

  if [[ -n "$input" && -n "$worktree" ]]; then
    # agent <project> <worktree> - go to project and create/use worktree
    local project_path
    project_path=$(_find_project "$input")
    if [[ $? -ne 0 ]]; then
      return 1
    fi
    project="${project_path##*/}"

    local project_dir="$CODE_DIR/$project_path"
    local worktree_path="$project_dir/worktrees/$worktree"
    if [[ ! -d "$worktree_path" ]]; then
      echo "Creating worktree: $worktree"
      mkdir -p "$project_dir/worktrees"
      git -C "$project_dir" worktree add "worktrees/$worktree" -b "$worktree" 2>/dev/null \
        || git -C "$project_dir" worktree add "worktrees/$worktree" "$worktree"
    fi

    session_name="agent-${project}-${worktree}"
    work_dir="$worktree_path"
  elif [[ -n "$input" ]]; then
    # agent <name> - check for worktree in current repo, else project
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [[ -n "$git_root" && -d "$git_root/worktrees/$input" ]]; then
      # Exact worktree match in current repo
      local repo_name=$(basename "$git_root")
      session_name="agent-${repo_name}-${input}"
      work_dir="$git_root/worktrees/$input"
    else
      # Try to find project by partial name
      local project_path
      project_path=$(_find_project "$input")
      if [[ $? -ne 0 ]]; then
        return 1
      fi
      project="${project_path##*/}"
      session_name="agent-${project}"
      work_dir="$CODE_DIR/$project_path"
    fi
  else
    # agent - use current project
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)

    if [[ -n "$git_root" ]]; then
      project=$(basename "$git_root")
    else
      project=$(basename "$PWD")
    fi
    session_name="agent-${project}"
    work_dir="${git_root:-$PWD}"
  fi

  # Check if session already exists
  if tmux has-session -t "$session_name" 2>/dev/null; then
    echo "Attaching to existing agent session: $session_name"
    tmux attach -t "$session_name"
  else
    echo "Creating agent session: $session_name"
    echo "Working directory: $work_dir"
    tmux new-session -s "$session_name" -c "$work_dir" "${AGENT_CLI_DEV_TOOL}"
  fi
}

# Create a new worktree window in agent session
# Usage: agent-feat <branch-name> [base-branch]
# Works from inside or outside tmux
agent-feat() {
  local branch="$1"
  local base="${2:-main}"

  if [[ -z "$branch" ]]; then
    echo "Usage: agent-feat <branch-name> [base-branch]"
    return 1
  fi

  # Get project root
  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$root" ]]; then
    echo "Error: Not in a git repository"
    return 1
  fi

  local project=$(basename "$root")
  local session_name="agent-${project}"
  local worktree_path="$root/worktrees/$branch"

  # Create worktree if needed
  if [[ ! -d "$worktree_path" ]]; then
    echo "Creating worktree: $branch"
    mkdir -p "$root/worktrees"
    git -C "$root" worktree add "worktrees/$branch" -b "$branch" "$base" 2>/dev/null \
      || git -C "$root" worktree add "worktrees/$branch" "$branch"
  fi

  if [[ -z "$TMUX" ]]; then
    # Not in tmux - create session if needed, add window, attach
    if ! tmux has-session -t "$session_name" 2>/dev/null; then
      echo "Creating agent session: $session_name"
      tmux new-session -d -s "$session_name" -c "$root" "${AGENT_CLI_DEV_TOOL}"
    fi

    # Add worktree window
    tmux new-window -t "$session_name" -n "$branch" -c "$worktree_path"
    tmux send-keys -t "$session_name:$branch" "${AGENT_CLI_DEV_TOOL}" Enter

    # Attach to session
    tmux attach -t "$session_name:$branch"
  else
    # In tmux - just add window to current session
    tmux new-window -n "$branch" -c "$worktree_path"
    tmux select-pane -T "happy:$branch"
    tmux send-keys "${AGENT_CLI_DEV_TOOL}" Enter
    echo "Created agent window: $branch"
  fi
}

# Clean up agent worktree window
# Usage: agent-feat-done <branch-name>
agent-feat-done() {
  local branch="$1"

  if [[ -z "$branch" ]]; then
    echo "Usage: agent-feat-done <branch-name>"
    return 1
  fi

  local root
  root=$(git rev-parse --show-toplevel 2>/dev/null)
  if [[ -z "$root" ]]; then
    echo "Error: Not in a git repository"
    return 1
  fi

  # Close tmux window if it exists
  tmux kill-window -t "$branch" 2>/dev/null

  # Remove worktree
  if [[ -d "$root/worktrees/$branch" ]]; then
    git -C "$root" worktree remove "worktrees/$branch"
    echo "Removed worktree: $branch"
  else
    echo "Worktree not found: $branch"
  fi
}

# Convert current agent session to full project layout
# Usage: agent-to-proj (run from within an agent session)
agent-to-proj() {
  # Must be in tmux
  if [[ -z "$TMUX" ]]; then
    echo "Error: Not in a tmux session"
    return 1
  fi

  local session_name
  session_name=$(tmux display-message -p '#{session_name}')

  # Check if this is an agent session
  if [[ ! "$session_name" =~ ^agent- ]]; then
    echo "Error: Not in an agent session (expected agent-* prefix)"
    return 1
  fi

  # Extract project name and find its path
  local project="${session_name#agent-}"
  local work_dir
  local project_path
  project_path=$(_find_project "$project" 2>/dev/null)
  if [[ $? -eq 0 ]]; then
    work_dir="$CODE_DIR/$project_path"
  else
    work_dir="$PWD"
  fi

  # Detect REPL type
  local repl="zsh"
  if [[ -f "$work_dir/Project.toml" ]]; then
    repl="julia --project=."
  elif [[ -f "$work_dir/DESCRIPTION" ]]; then
    repl="R"
  fi

  # Rename current pane
  tmux select-pane -T "happy:main"

  # Add nvim pane to the left
  tmux split-window -hb -c "$work_dir"
  tmux select-pane -T "nvim"
  tmux send-keys "nvim ." Enter

  # Add REPL pane below happy
  tmux select-pane -t 1  # Go back to happy pane
  tmux split-window -v -c "$work_dir"
  tmux select-pane -T "repl"
  tmux send-keys "$repl" Enter

  # Resize to match project layout (50% left, 25%/25% right)
  tmux select-layout main-vertical

  # Focus nvim
  tmux select-pane -t 0

  # Optionally rename session to remove agent- prefix
  echo "Converted to project layout. Rename session with: tmux rename-session $project"
}

# List active project sessions (non-agent sessions)
# List windows for a session, showing feature worktrees
# Usage: _show_session_windows <session-name>
_show_session_windows() {
  local session="$1"
  local windows
  windows=$(tmux list-windows -t "$session" \
    -F '#{window_index}:#{window_name}' 2>/dev/null)
  echo "$windows" | while IFS= read -r win; do
    echo "    $win"
  done
}

projects() {
  echo "Active project sessions:"
  echo "========================"
  local sessions
  sessions=$(tmux list-sessions -F '#{session_name}' \
    2>/dev/null | grep -v "^agent-" | sort)
  if [[ -z "$sessions" ]]; then
    echo "  (none)"
    return 0
  fi
  echo "$sessions" | while IFS= read -r s; do
    echo "  $s"
    _show_session_windows "$s"
  done
}

# List active agent sessions
agents() {
  echo "Active agent sessions:"
  echo "======================"
  local sessions
  sessions=$(tmux list-sessions -F '#{session_name}' \
    2>/dev/null | grep "^agent-" | sort)
  if [[ -z "$sessions" ]]; then
    echo "  (none)"
    return 0
  fi
  echo "$sessions" | while IFS= read -r s; do
    echo "  $s"
    _show_session_windows "$s"
  done
}

# Combined session manager
# Usage: mtmux [projects|agents|all]
mtmux() {
  local filter="${1:-all}"

  echo "tmux sessions"
  echo "============="
  echo ""

  case "$filter" in
    projects|p)
      projects
      ;;
    agents|a)
      agents
      ;;
    all|*)
      local all_sessions
      all_sessions=$(tmux list-sessions \
        -F '#{session_name}' 2>/dev/null | sort)

      if [[ -z "$all_sessions" ]]; then
        echo "No active sessions"
        return 0
      fi

      local proj_sessions
      proj_sessions=$(echo "$all_sessions" \
        | grep -v "^agent-")
      local agent_sessions
      agent_sessions=$(echo "$all_sessions" \
        | grep "^agent-")

      echo "Projects:"
      if [[ -z "$proj_sessions" ]]; then
        echo "  (none)"
      else
        echo "$proj_sessions" | while IFS= read -r s; do
          echo "  $s"
          _show_session_windows "$s"
        done
      fi
      echo ""
      echo "Agents:"
      if [[ -z "$agent_sessions" ]]; then
        echo "  (none)"
      else
        echo "$agent_sessions" | while IFS= read -r s; do
          echo "  $s"
          _show_session_windows "$s"
        done
      fi
      ;;
  esac

  echo ""
  echo "Commands: proj <name> [branch],"
  echo "  agent [name] [worktree], agent-to-proj"
}