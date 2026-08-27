#!/bin/bash
# Git clean filter for pi/settings.json: pi bumps lastChangelogVersion on
# almost every run, which otherwise shows up as a no-op diff. Pin it to a
# constant so only real config edits (theme, model, packages, ...) show.
set -euo pipefail
exec jq '.lastChangelogVersion = "0.0.0"'
