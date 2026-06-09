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
brew install bat
brew install hyperfine
brew install direnv
