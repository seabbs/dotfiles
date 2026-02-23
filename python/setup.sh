#!/bin/bash

brew install python
brew install uv

# Add Python aliases to zshrc (idempotent)
grep -qF 'alias python=python3' ~/.zshrc \
  || echo 'alias python=python3' >> ~/.zshrc
grep -qF 'alias pip=pip3' ~/.zshrc \
  || echo 'alias pip=pip3' >> ~/.zshrc
