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

  # R packages with C/C++ (tidyverse's ragg, igraph behind targets, the epi
  # stack, ...) compile from source on Linux and link against system image /
  # graph / web libraries. Install their -dev headers from apt.
  sudo apt-get install -y \
    libcurl4-openssl-dev libssl-dev libxml2-dev zlib1g-dev \
    libfontconfig1-dev libfreetype-dev libharfbuzz-dev libfribidi-dev \
    libpng-dev libtiff-dev libjpeg-dev libwebp-dev libglpk-dev

  # ...but brew R uses brew's OWN dynamic loader, which only resolves
  # libraries brew knows about. Some system libs (freetype, png) come in as
  # brew deps and load fine; others do not, so a package compiles and links
  # yet fails to dlopen at load time, e.g.
  #   ragg   -> libtiff.so.5 -> libwebp.so.7  cannot open shared object file
  #   igraph -> libglpk.so.40                 cannot open shared object file
  # Installing these in brew puts them on brew R's loader path and fixes it.
  brew install libtiff webp jpeg-turbo little-cms2 glpk
fi

# radian via uv: brew Python is PEP 668 externally-managed, so pip is blocked
uv tool install radian

Rscript R/packages.R

# Add R alias to zshrc (idempotent)
grep -qF 'alias R=radian' ~/.zshrc \
  || echo 'alias R=radian' >> ~/.zshrc
