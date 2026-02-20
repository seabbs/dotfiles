#!/bin/bash

brew install python
brew install pipenv
brew install poetry

if [[ "$(uname)" == "Darwin" ]]; then
  brew install --cask pycharm-ce
fi

echo 'alias python=python3' >> ~/.zshrc
echo 'alias pip=pip3' >> ~/.zshrc
