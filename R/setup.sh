#!/bin/bash

bash python/setup.sh

if [[ "$(uname)" == "Darwin" ]]; then
  brew install --cask r
else
  brew install r
  # Linuxbrew's R Makeconf can hardcode a gcc version that differs from the
  # gcc Homebrew actually installed, which breaks package compilation. Alias
  # the expected compiler names to the installed gcc so R can build packages.
  makeconf="$(brew --prefix r)/lib/R/etc/Makeconf"
  want=$(grep -oE '^CC = gcc-[0-9]+' "$makeconf" | grep -oE '[0-9]+$')
  have=$(ls "$(brew --prefix)"/bin/gcc-* 2>/dev/null \
    | grep -oE '[0-9]+$' | sort -n | tail -1)
  if [[ -n "$want" && -n "$have" && "$want" != "$have" ]]; then
    for v in gcc g++ gfortran; do
      ln -sf "$(brew --prefix)/bin/${v}-${have}" \
        "$(brew --prefix)/bin/${v}-${want}"
    done
    echo "Aliased gcc-${want} -> gcc-${have} for R package compilation"
  fi
fi

# radian via uv: brew Python is PEP 668 externally-managed, so pip is blocked
uv tool install radian

Rscript R/packages.R

# Add R alias to zshrc (idempotent)
grep -qF 'alias R=radian' ~/.zshrc \
  || echo 'alias R=radian' >> ~/.zshrc
