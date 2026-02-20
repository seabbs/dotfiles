# dotfiles

Personal development environment configuration.

## Quick start

Mac:

```bash
bash mac/setup.sh
```

Remote Linux machine (via SSH):

```bash
bash remote/setup.sh
```

Symlinks only (if tools are already installed):

```bash
bash scripts/link.sh
```

## Structure

| Directory | Purpose |
|---|---|
| `bat/` | Bat (syntax-highlighted cat) configuration |
| `brew/` | Homebrew installation |
| `cli/` | CLI tools (gh, docker, claude-code, happy, etc.) |
| `gh/` | GitHub CLI and gh-dash configuration |
| `git/` | Git config (delta, gitignore) |
| `iterm2/` | iTerm2 profile and keybindings |
| `jobs/` | Scheduled jobs (launchd on Mac, cron on Linux) |
| `julia/` | Julia via juliaup, startup config |
| `mac/` | Mac-specific setup and GUI apps |
| `nvim/` | Neovim config (LazyVim-based) |
| `python/` | Python, uv |
| `R/` | R, radian, packages, .Rprofile |
| `remote/` | Remote Linux machine setup |
| `scripts/` | Shared scripts (symlinks, repo sync, Julia maintenance) |
| `shell/` | Zsh config and aliases |
| `tmux/` | Tmux configuration |
| `tmuxinator/` | Tmuxinator project templates |

## Symlinks

`scripts/link.sh` manages all symlinks.
It runs automatically during setup, or can be run standalone.

| Source | Target |
|---|---|
| `shell/.zshrc` | `~/.zshrc` |
| `shell/ai-cli-aliases.zsh` | `~/.config/zsh/ai-cli-aliases.zsh` |
| `nvim/` | `~/.config/nvim` |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `tmuxinator/project.yml` | `~/.config/tmuxinator/project.yml` |
| `R/.Rprofile` | `~/.Rprofile` |
| `julia/startup.jl` | `~/.julia/config/startup.jl` |
| `git/ignore` | `~/.config/git/ignore` |
| `git/config` | `~/.config/git/config` |
| `bat/config` | `~/.config/bat/config` |
| `gh/config.yml` | `~/.config/gh/config.yml` |
| `gh/dash.yml` | `~/.config/gh-dash/config.yml` |

## Scheduled jobs

Jobs are installed by `jobs/setup.sh` (runs automatically during setup).
On macOS, plists are generated at install time (no hardcoded paths in the repo).
On Linux, user crontab entries are created.

| Job | Schedule | Purpose |
|---|---|---|
| `sync-repos` | Daily 07:00 | Fetch and fast-forward all repos under `~/code` |
| `julia-maintenance` | Daily 06:30 | Update Julia via juliaup, precompile active projects |

Check status with `job-status` (alias available after sourcing `.zshrc`).
