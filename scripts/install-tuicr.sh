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
#
# Pass --update to upgrade an existing install. Without it the script returns
# early when tuicr already runs, which is what cli/setup.sh wants (fast, no
# network) but means a plain re-run never picks up a new release.
set -euo pipefail

usage() {
  cat >&2 <<EOF
usage: $(basename "$0") [--update]

  (no args)  install tuicr, or repair a broken install; leaves a working
             install alone
  --update   upgrade an existing install to the latest release
EOF
  exit 2
}

UPDATE=0
if [ "$#" -gt 1 ]; then
  usage
elif [ "$#" -eq 1 ]; then
  if [ "$1" = "--update" ]; then
    UPDATE=1
  else
    usage
  fi
fi

# `hash -r` first: after an install or uninstall the shell's command cache can
# still point at a path that has just moved or gone.
works() {
  hash -r
  command -v tuicr >/dev/null 2>&1 && tuicr --version >/dev/null 2>&1
}

if works && [ "$UPDATE" -eq 0 ]; then
  echo "tuicr already working: $(tuicr --version)"
  echo "Re-run with --update to upgrade to the latest release."
  exit 0
fi

if [ "$UPDATE" -eq 1 ] && works; then
  before="$(tuicr --version)"
  echo "Updating tuicr (currently $before)..."
  # Upgrade in place via whichever installer owns the binary. The brew branch is
  # only reached when brew exists and has tuicr, so cargo-only boxes stay quiet.
  upgraded=1
  if command -v brew >/dev/null 2>&1 &&
     brew list --versions tuicr >/dev/null 2>&1; then
    brew upgrade tuicr || upgraded=0
  elif command -v cargo >/dev/null 2>&1; then
    # --force because cargo skips the install when the version is unchanged.
    cargo install tuicr --locked --force || upgraded=0
  else
    echo "  Neither brew nor cargo found; cannot update." >&2
    exit 1
  fi

  if works; then
    after="$(tuicr --version)"
    # Report the failure rather than the version. Saying "already on the latest"
    # after a failed upgrade would claim we checked when we did not.
    if [ "$upgraded" -eq 0 ]; then
      echo "Upgrade failed. Still on $before, which may not be current." >&2
      exit 1
    fi
    if [ "$before" = "$after" ]; then
      echo "Already on the latest release: $after"
    else
      echo "Updated: $before -> $after"
    fi
    exit 0
  fi
  echo "tuicr stopped working after the update; repairing..." >&2
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
