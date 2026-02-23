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

# Bat
link "bat/config"                "$HOME/.config/bat/config"

# GitHub CLI
link "gh/config.yml"             "$HOME/.config/gh/config.yml"
link "gh/dash.yml"               "$HOME/.config/gh-dash/config.yml"

# Claude Code
link "claude/CLAUDE.md"            "$HOME/.claude/CLAUDE.md"
link "claude/commands"             "$HOME/.claude/commands"
link "claude/settings.json"        "$HOME/.claude/settings.json"
link "claude/settings.local.json"  "$HOME/.claude/settings.local.json"
link "claude/setup.sh"             "$HOME/.claude/setup.sh"

echo "Done."
