#!/usr/bin/env bash
# setup.sh — build the image a cloud agent session starts from.
#
# Run once when the environment image is built, so a waking session finds
# Julia and R already there. It is idempotent, so it can also be run as a
# bootstrap in a session that started from a plain image, at the cost of a
# few minutes.
#
# It installs tools, never project dependencies. Each repo resolves its own
# from Project.toml or DESCRIPTION. What is worth baking in is the part that
# is identical every time and slow: the toolchains, and the General registry
# clone that every Julia resolve would otherwise fetch.
#
# No credentials here. This repo is public. The bot's token reaches the
# session as GH_TOKEN from the environment's secret store.

set -euo pipefail

log() { printf '%s  %s\n' "$(date -u +%H:%M:%S)" "$*"; }
have() { command -v "$1" >/dev/null 2>&1; }

SUDO=""
[ "$(id -u)" -eq 0 ] || SUDO="sudo"

log "apt packages"
export DEBIAN_FRONTEND=noninteractive
$SUDO apt-get update -qq
$SUDO apt-get install -y -qq --no-install-recommends \
  build-essential ca-certificates curl git jq gnupg \
  libcurl4-openssl-dev libssl-dev libxml2-dev libgit2-dev \
  pandoc >/dev/null

# gh: the agent does everything through it, so a missing gh is a dead run.
if ! have gh; then
  log "gh"
  curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
    | $SUDO dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
      status=none
  echo "deb [signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
    | $SUDO tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq gh >/dev/null
fi

# R from the CRAN apt repo, with r2u so package installs are binaries
# rather than compiles. A source install of the devtools stack takes
# tens of minutes; this is the difference between a usable image and one
# that spends its session compiling.
if ! have R; then
  log "R"
  $SUDO install -d -m 0755 /etc/apt/keyrings
  curl -fsSL https://eddelbuettel.github.io/r2u/assets/dirk_eddelbuettel_key.asc \
    | $SUDO tee /etc/apt/keyrings/cranapt_key.asc >/dev/null
  . /etc/os-release
  echo "deb [signed-by=/etc/apt/keyrings/cranapt_key.asc] \
https://r2u.stat.illinois.edu/ubuntu ${UBUNTU_CODENAME:-noble} main" \
    | $SUDO tee /etc/apt/sources.list.d/cranapt.list >/dev/null
  $SUDO apt-get update -qq
  $SUDO apt-get install -y -qq --no-install-recommends r-base-core r-base-dev \
    >/dev/null
fi

# The tools a review or a fix needs, not the dependencies of any one
# package. Binary installs via r2u where it is available.
log "R tooling"
$SUDO apt-get install -y -qq --no-install-recommends \
  r-cran-devtools r-cran-testthat r-cran-roxygen2 r-cran-lintr \
  r-cran-styler r-cran-remotes >/dev/null 2>&1 \
  || Rscript -e 'install.packages(c("devtools","testthat","roxygen2","lintr",
       "styler","remotes"), repos="https://cloud.r-project.org")' >/dev/null

# juliaup rather than a tarball, so the version can move without rebuilding
# the image by hand.
if ! have julia; then
  log "juliaup"
  curl -fsSL https://install.julialang.org \
    | sh -s -- --yes --default-channel release >/dev/null
fi
export PATH="$HOME/.juliaup/bin:$PATH"

# Clone the General registry now. Every Julia resolve in every repo needs
# it, and fetching it per session is the slowest part of a Julia task.
log "julia registry"
julia --startup-file=no -e '
  using Pkg
  isempty(Pkg.Registry.reachable_registries()) && Pkg.Registry.add("General")
  Pkg.add(["Revise", "TestItemRunner"])
  Pkg.precompile()' >/dev/null 2>&1 || log "julia registry step failed"

log "versions"
{ git --version; gh --version | head -1; jq --version
  R --version | head -1; julia --version; } 2>&1 | sed 's/^/  /'
log "done"
