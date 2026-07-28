#!/usr/bin/env bash
# Install (or repair) tuicr — the code review TUI.
#
# The Homebrew tap ships prebuilt binaries, but the Linux ones are built
# against glibc 2.39 and will not run on older distros (archie is Ubuntu 22.04,
# glibc 2.35). So: install from the tap, check the binary actually runs, and
# fall back to building from source when it does not. tuicr is edition 2024,
# so a source build needs Rust >= 1.85.
#
# Idempotent: re-run to install or to repair a broken install.
set -euo pipefail

# `hash -r` first: after an install or uninstall the shell's command cache can
# still point at a path that has just moved or gone.
works() {
  hash -r
  command -v tuicr >/dev/null 2>&1 && tuicr --version >/dev/null 2>&1
}

if works; then
  echo "tuicr already working: $(tuicr --version)"
  exit 0
fi

echo "Installing tuicr from the Homebrew tap..."
brew install agavra/tap/tuicr || echo "  Warning: tap install failed"

if works; then
  echo "Done: $(tuicr --version)"
  exit 0
fi

echo "The prebuilt binary does not run here (usually glibc too old)."
echo "Falling back to a source build..."

if ! command -v cargo >/dev/null 2>&1; then
  echo "  cargo not found. Install Rust (https://rustup.rs) and re-run." >&2
  exit 1
fi

# edition 2024 needs Rust >= 1.85; nudge an old rustup toolchain forward.
if command -v rustup >/dev/null 2>&1; then
  rustup update stable || echo "  Warning: rustup update failed"
fi

brew uninstall tuicr 2>/dev/null || true
cargo install tuicr --locked

if works; then
  echo "Done: $(tuicr --version)"
else
  echo "tuicr still not runnable. Check that ~/.cargo/bin is on PATH." >&2
  exit 1
fi
