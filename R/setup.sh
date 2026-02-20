#!/bin/bash

bash python/setup.sh

if [[ "$(uname)" == "Darwin" ]]; then
  brew install --cask r
else
  brew install r
fi

pip3 install radian

Rscript R/packages.R
