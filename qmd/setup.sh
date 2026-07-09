#!/bin/bash
# Bootstrap qmd config directory. The qmd CLI itself is installed in
# cli/setup.sh (npm global). This just makes sure the config dir exists so
# the symlinked index.yml lands somewhere qmd will read it.
set -euo pipefail

mkdir -p "$HOME/.config/qmd"
echo "qmd config dir ready: $HOME/.config/qmd"