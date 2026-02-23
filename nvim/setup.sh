#!/bin/bash

brew install neovim
brew install ripgrep
brew install fd
brew install fzf
brew install lazygit
brew install tree-sitter
brew install tree-sitter-cli
brew install lua
brew install luarocks
brew install node

# Set default editor in zshrc (idempotent)
grep -qF 'export EDITOR=' ~/.zshrc \
  || echo 'export EDITOR="nvim"' >> ~/.zshrc
