#!/bin/bash

# Install juliaup (manages Julia versions)
if ! command -v juliaup &>/dev/null; then
  curl -fsSL https://install.julialang.org | sh -s -- -y
fi

juliaup add release
juliaup default release

# Install global dev packages
julia julia/packages.jl

echo 'export JULIA_NUM_THREADS=auto' >> ~/.zshrc
