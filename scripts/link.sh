#!/bin/bash
# Create symlinks from dotfiles repo to their expected locations.
# Safe to re-run: uses ln -sf to overwrite existing links.

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"

link() {
  local src="$DOTFILES/$1"
  local dst="$2"
  mkdir -p "$(dirname "$dst")"
  ln -sfn "$src" "$dst"
  echo "  $dst -> $src"
}

echo "Linking dotfiles from $DOTFILES"

# Shell
link "shell/.zshrc"              "$HOME/.zshrc"
link "shell/ai-cli-aliases.zsh"  "$HOME/.config/zsh/ai-cli-aliases.zsh"
link "shell/taskwarrior.zsh"     "$HOME/.config/zsh/taskwarrior.zsh"

# Neovim
link "nvim"                      "$HOME/.config/nvim"

# Tmux
link "tmux/tmux.conf"            "$HOME/.tmux.conf"

# Tmuxinator
link "tmuxinator/project.yml"    "$HOME/.config/tmuxinator/project.yml"

# R
link "R/.Rprofile"               "$HOME/.Rprofile"

# Julia
link "julia/startup.jl"          "$HOME/.julia/config/startup.jl"

# Git
link "git/ignore"                "$HOME/.config/git/ignore"
link "git/config"                "$HOME/.config/git/config"

# Ghostty
link "ghostty/config"            "$HOME/.config/ghostty/config"

# AeroSpace
link "aerospace/aerospace.toml"  "$HOME/.config/aerospace/aerospace.toml"

# Bat
link "bat/config"                "$HOME/.config/bat/config"

# GitHub CLI
link "gh/config.yml"             "$HOME/.config/gh/config.yml"
link "gh/dash.yml"               "$HOME/.config/gh-dash/config.yml"

# Gemini CLI
link ".gemini/settings.json"     "$HOME/.gemini/settings.json"
link ".gemini/GEMINI.md"         "$HOME/.gemini/GEMINI.md"
link ".gemini/commands"          "$HOME/.gemini/commands"

# Link skills library if it exists
if [ -d "$HOME/code/seabbs/skills" ]; then
  ln -sfn "$HOME/code/seabbs/skills" "$HOME/.gemini/skills"
  echo "  $HOME/.gemini/skills -> $HOME/code/seabbs/skills"
fi

# Television (stock cable channels managed by tv update-channels)
link "tv/config.toml"               "$HOME/.config/television/config.toml"
link "tv/cable/all-files.toml"      "$HOME/.config/television/cable/all-files.toml"

# Taskwarrior (binary is keg-only; `task` on PATH stays go-task)
link "task/taskrc"               "$HOME/.config/task/taskrc"
if command -v brew >/dev/null 2>&1 && brew list task >/dev/null 2>&1; then
  # Shim so tools shelling out to `task` (e.g. taskwarrior-tui) hit Taskwarrior
  mkdir -p "$HOME/.local/share/tw-shim"
  ln -sfn "$(brew --prefix task)/bin/task" "$HOME/.local/share/tw-shim/task"
  echo "  $HOME/.local/share/tw-shim/task -> $(brew --prefix task)/bin/task"
  # Make sure go-task keeps ownership of the `task` command
  if brew list go-task >/dev/null 2>&1 &&
     ! readlink "$(brew --prefix)/bin/task" 2>/dev/null | grep -q '/go-task/'; then
    brew unlink task >/dev/null 2>&1 || true
    brew link --overwrite go-task >/dev/null 2>&1 || true
    echo "  restored go-task as 'task'"
  fi
fi

# launchd agents (macOS)
if [ "$(uname -s)" = "Darwin" ]; then
  for plist in "$DOTFILES"/launchd/*.plist; do
    [ -f "$plist" ] || continue
    link "launchd/$(basename "$plist")" \
      "$HOME/Library/LaunchAgents/$(basename "$plist")"
  done
fi

# Claude Code (delegates to submodule's own link script)
"$DOTFILES/claude/link.sh"

echo "Done."
