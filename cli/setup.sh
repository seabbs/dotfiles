#!/bin/bash

if [[ "$(uname)" == "Darwin" ]]; then
  brew install --cask docker
else
  brew install docker
fi
brew install pre-commit
brew install gh
brew install azure-cli
brew install pandoc
brew install mosh
# Ensure brew's node provides npm before global installs (a fresh Linux box
# has no usable system node, and system npm would need sudo).
brew install node
npm install -g @anthropic-ai/claude-code
npm install -g happy-coder
brew install act
brew install glow
brew install git-delta
brew install jj    # Jujutsu — colocated-git VCS for incremental review
brew install hunk  # review-first terminal diff viewer (jj/git-aware)
brew install bat
brew install hyperfine
brew install direnv

# QMD (tobilu/qmd) — on-device hybrid search engine for markdown/docs.
# Requires Homebrew sqlite for its FTS5 + sqlite-vec extensions on macOS.
# --allow-scripts lets better-sqlite3, node-llama-cpp and tree-sitter grammars
# compile their native addons; without it npm 10+ silently skips them and
# qmd fails at runtime.
brew install sqlite
npm install -g @tobilu/qmd \
  --allow-scripts=better-sqlite3,node-llama-cpp,tree-sitter-go,tree-sitter-python,tree-sitter-rust,tree-sitter-typescript,tree-sitter-javascript
