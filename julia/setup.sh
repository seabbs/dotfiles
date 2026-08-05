#!/bin/bash

# Install juliaup (manages Julia versions)
if ! command -v juliaup &>/dev/null; then
  curl -fsSL https://install.julialang.org | sh -s -- -y
fi

juliaup add release
juliaup default release

# Install global dev packages
julia julia/setup-packages.jl

# Install JuliaC as a standalone app in a temp env.
# Not in registry so must be dev'd from GitHub first.
# Installs the juliac binary to ~/.julia/bin.
#
# Usage:
#   juliac --output-exe myapp --bundle build --trim=safe --experimental .
#   juliac --output-lib mylib.dylib --trim=safe --experimental .
julia -e '
  using Pkg
  Pkg.activate(; temp=true)
  Pkg.develop(url="https://github.com/JuliaLang/JuliaC.jl")
  Pkg.Apps.add("JuliaC")
'

# Install Runic as a standalone app. Runic is the Julia formatter used
# across EpiAware (replacing JuliaFormatter); it has no style config and
# a single version to pin, so it lives outside the default environment.
# Pkg.Apps.add drops the `runic` binary into ~/.julia/bin, which is
# already on PATH (shell/.zshrc). Needs Julia 1.12+. conform.nvim picks
# it up for format-on-save (nvim/lua/plugins/formatters.lua). See #76.
julia -e 'using Pkg; Pkg.Apps.add("Runic")'

# Add Julia env vars to zshrc (idempotent)
grep -qF 'JULIA_NUM_THREADS' ~/.zshrc \
  || echo 'export JULIA_NUM_THREADS=auto' >> ~/.zshrc
grep -qF 'JULIA_PROJECT' ~/.zshrc \
  || echo 'export JULIA_PROJECT=@.' >> ~/.zshrc
