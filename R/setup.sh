#!/bin/bash

bash python/setup.sh

if [[ "$(uname)" == "Darwin" ]]; then
  brew install --cask r
else
  brew install r
  # brew R's Makeconf expects a specific distro gcc (e.g. gcc-12) that
  # matches the system assembler. brew's own gcc is too new for older
  # binutils (its asm fails to assemble), so install the matching distro
  # compilers from apt instead.
  makeconf="$(brew --prefix r)/lib/R/etc/Makeconf"
  want=$(grep -oE '^CC = gcc-[0-9]+' "$makeconf" | grep -oE '[0-9]+$')
  if [[ -n "$want" ]] && ! command -v "gcc-${want}" >/dev/null; then
    sudo apt-get install -y \
      "gcc-${want}" "g++-${want}" "gfortran-${want}"
  fi
fi

# radian via uv: brew Python is PEP 668 externally-managed, so pip is blocked
uv tool install radian

Rscript R/packages.R

# Add R alias to zshrc (idempotent)
grep -qF 'alias R=radian' ~/.zshrc \
  || echo 'alias R=radian' >> ~/.zshrc
