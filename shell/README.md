# Shell configuration

## ai-cli-aliases.zsh

Tmux workflow functions for Claude Code development.

**Session management:**
- `agent [project] [worktree]` - Start agent session (just happy)
- `proj <name>` - Start full project session (nvim + happy + repl)
- `agent-to-proj` - Convert agent session to full project layout

Both `agent` and `proj` support partial name matching:
- `agent epi` matches `epinowcast` if unique
- `proj dots` matches `dotfiles` if unique
- Shows options if multiple matches found

**Worktree management:**
- `agent-feat <branch> [base]` - Add worktree window to agent session
- `agent-feat-done <branch>` - Clean up worktree window
- `feat <branch> [base]` - Add worktree window to project session
- `feat-done <branch>` - Clean up worktree
- `feat-list` - List worktrees

**Session listing:**
- `mtmux` - List all sessions
- `projects` - List project sessions
- `agents` - List agent sessions
- `lsproj [filter]` - List available projects in ~/code

**Claude shortcuts:**
- `tc [command]` - Smart tmux-claude launcher
- `commit`, `review`, `lint`, `test`, `pr`, etc.

## Setup

Symlink is managed by `scripts/link.sh` (runs automatically during setup).
The `.zshrc` sources `ai-cli-aliases.zsh` from `~/.config/zsh/`.
