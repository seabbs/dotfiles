#!/bin/bash
# Install pi and its declared packages, then link config.
# Run standalone or via scripts/common-tools.sh.

set -euo pipefail

echo "Setting up pi..."

# Install the pi CLI globally (idempotent).
if ! command -v pi >/dev/null 2>&1; then
  npm install -g @earendil-works/pi-coding-agent
else
  echo "  pi already installed: $(pi --version 2>/dev/null || echo 'unknown')"
fi

# Install the packages declared in pi/settings.json into ~/.pi/agent.
# --no-approve is safe here: settings.json is our own tracked config, and
# defaultProjectTrust is handled at the agent level, not by `pi install`.
if [ -f "$(dirname "$0")/settings.json" ]; then
  echo "  installing declared packages (pi-web-access, pi-subagents,"
  echo "  @juicesharp/rpiv-todo, @aliou/pi-guardrails)..."
  pi install --no-approve 2>/dev/null \
    || echo "  Warning: some packages failed to install (run 'pi list' to check)"
fi

# Settings are symlinked by scripts/link.sh; packages still need installing.
echo "Done. Run '/guardrails:onboarding' on first pi start to configure safety."

echo ""
echo "NOTE: auth is machine-local. Store your OpenRouter key with:"
echo "  pi --login   # then select OpenRouter"
