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
npm install -g @anthropic-ai/claude-code
npm install -g happy-coder
brew install act
brew install glow
brew install git-delta
brew install bat
brew install hyperfine
brew install direnv
