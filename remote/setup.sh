#!/bin/bash
# Setup for remote SSH-accessed Linux machines.
# Installs Homebrew (Linuxbrew) then all CLI tools and languages.
# GUI apps (mac/apps.sh) and launchd jobs are skipped.

bash brew/setup.sh
bash scripts/common-tools.sh
