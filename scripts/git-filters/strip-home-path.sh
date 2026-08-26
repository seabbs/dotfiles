#!/bin/bash
# Git clean filter for shell/.zshrc: juliaup rewrites its managed block
# with this machine's literal $HOME (e.g. /Users/<you> or /home/<you>),
# which would otherwise leak the local username into a public repo.
# Substitute the literal path back to $HOME before it reaches git.
set -euo pipefail
sed "s|${HOME}|\$HOME|g"
