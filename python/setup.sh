#!/bin/bash

brew install python
brew install uv

# Add Python aliases to zshrc (idempotent)
grep -qF 'alias python=python3' ~/.zshrc \
  || echo 'alias python=python3' >> ~/.zshrc
grep -qF 'alias pip=pip3' ~/.zshrc \
  || echo 'alias pip=pip3' >> ~/.zshrc

# Dedicated python host for neovim. molten-nvim is a remote plugin and
# needs pynvim in the interpreter nvim uses; homebrew's python is
# externally managed and refuses pip installs. nvim/lua/config/options.lua
# points vim.g.python3_host_prog here.
if [ ! -x "$HOME/.local/share/nvim-venv/bin/python" ]; then
  uv venv "$HOME/.local/share/nvim-venv" --python 3.12
fi
uv pip install --python "$HOME/.local/share/nvim-venv/bin/python" \
  pynvim jupyter_client cairosvg pnglatex plotly kaleido pyperclip \
  nbformat pillow
