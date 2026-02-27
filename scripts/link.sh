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

# Ghostty
link "ghostty/config"            "$HOME/.config/ghostty/config"

# Bat
link "bat/config"                "$HOME/.config/bat/config"

# GitHub CLI
link "gh/config.yml"             "$HOME/.config/gh/config.yml"
link "gh/dash.yml"               "$HOME/.config/gh-dash/config.yml"

# Claude Code (delegates to submodule's own link script)
"$DOTFILES/claude/link.sh"

echo "Done."
