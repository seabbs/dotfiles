#!/bin/bash
# Setup for remote SSH-accessed Linux machines.
# Installs Homebrew (Linuxbrew) then all CLI tools and languages.
# GUI apps (mac/apps.sh) and launchd jobs are skipped.

bash brew/setup.sh

# On older distros the system glibc can be older than Homebrew's bottles
# expect (e.g. Ubuntu 22.04 ships 2.35 but the node/R bottles need 2.38),
# which makes those binaries fail to run. Install Homebrew's own glibc first
# so its bottles link against a new-enough copy.
eval "$(/home/linuxbrew/.linuxbrew/bin/brew shellenv)"
sysglibc=$(ldd --version 2>/dev/null | awk 'NR==1{print $NF}')
if [[ -n "$sysglibc" ]] &&
   [[ "$(printf '%s\n2.38\n' "$sysglibc" | sort -V | head -1)" != "2.38" ]]; then
  echo "System glibc $sysglibc < 2.38; installing Homebrew glibc"
  brew install glibc
fi

bash scripts/common-tools.sh
