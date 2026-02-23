#!/bin/bash

bash python/setup.sh

if [[ "$(uname)" == "Darwin" ]]; then
  brew install --cask r
else
  brew install r
fi

pip3 install radian

Rscript R/packages.R

# Add R alias to zshrc (idempotent)
grep -qF 'alias R=radian' ~/.zshrc \
  || echo 'alias R=radian' >> ~/.zshrc
