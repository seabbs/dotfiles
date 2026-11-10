#!/bin/bash
# Dry-run based check that review-bot.sh never refuses a PR for its size.
#
# No bats/shellspec harness exists for these scripts, so this stubs `gh`
# and runs review-bot.sh against an isolated $HOME. The checkout step fails
# against the stub, which is fine: the size decision is made before it.
# Verifies:
#
#   1. a PR far over MAX_DIFF is not declined and posts no refusal
#      comment. It gets a focused pass instead. A refusal used to repeat
#      on every poll (~276 comments on epinowcast/epinowcast#834).
#   2. a PR under MAX_DIFF gets a full pass, with no focused-pass scope.
#
# Usage: test-review-bot-size.sh [path-to-scripts-dir]
#   defaults to the scripts/ directory this file lives under.
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
STUB_GH="$HERE/stub-gh-review-bot"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rb-test.XXXXXX")"
[ -n "${RB_TEST_KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT

DOTFILES_COPY="$WORK/dotfiles"
mkdir -p "$DOTFILES_COPY/scripts"
cp "$SRC_SCRIPTS/review-bot.sh" "$DOTFILES_COPY/scripts/review-bot.sh"
cp "$SRC_SCRIPTS/bot-common.sh" "$DOTFILES_COPY/scripts/bot-common.sh"
cp "$SRC_SCRIPTS/review-bot-format.jq" "$SRC_SCRIPTS/review-bot-rounds.sh" \
  "$DOTFILES_COPY/scripts/"
chmod +x "$DOTFILES_COPY/scripts/review-bot.sh"
cat > "$DOTFILES_COPY/scripts/review-bot-token.sh" <<'EOF'
#!/bin/bash
echo "test-token-$1"
EOF
chmod +x "$DOTFILES_COPY/scripts/review-bot-token.sh"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

new_home() {
  local h="$WORK/home-$1"
  mkdir -p "$h/.local/bin"
  cp "$STUB_GH" "$h/.local/bin/gh"
  chmod +x "$h/.local/bin/gh"
  ln -s "$(command -v claude)" "$h/.local/bin/claude"
  echo "$h"
}

run_bot() {
  local home="$1"; shift
  HOME="$home" \
  RB_TEST_CALLS="$home/calls.log" \
  RB_TEST_COMMENTS="$home/comments.log" \
  REVIEW_BOT_KEY=dummy \
  REVIEW_BOT_MAX_DIFF=50 \
  REVIEW_BOT_SANDBOX=0 \
  "$@" \
  "$DOTFILES_COPY/scripts/review-bot.sh" --pr epinowcast/epinowcast#834 \
    > "$home/run.out" 2>&1 || true
}

comment_count() {
  [ -f "$1/comments.log" ] && wc -l < "$1/comments.log" | tr -d ' ' || echo 0
}
bot_log() { cat "$1/.local/share/review-bot/last-run.log" 2>/dev/null; }

echo "== scenario 1: a very large PR is reviewed, not refused =="
h1="$(new_home s1)"
run_bot "$h1" env RB_TEST_SHA=deadbeef RB_TEST_FILES_LINES=90000
if [ "$(comment_count "$h1")" = "0" ]; then
  pass "no refusal comment posted"
else
  bad "posted $(comment_count "$h1") comment(s) on an oversized PR"
fi
if bot_log "$h1" | grep -q 'focused pass on epinowcast/epinowcast#834'; then
  pass "oversized PR gets a focused pass"
else
  bad "oversized PR did not get a focused pass: $(bot_log "$h1")"
fi
if bot_log "$h1" | grep -q 'skip epinowcast/epinowcast#834.*cap'; then
  bad "oversized PR was skipped for size"
else
  pass "oversized PR not skipped for size"
fi

echo
echo "== scenario 2: a small PR gets a full pass =="
h2="$(new_home s2)"
run_bot "$h2" env RB_TEST_SHA=cafef00d RB_TEST_FILES_LINES=10
if bot_log "$h2" | grep -q 'reviewing epinowcast/epinowcast#834' &&
    ! bot_log "$h2" | grep -q 'focused pass'; then
  pass "small PR reviewed with a full pass"
else
  bad "small PR not given a full pass: $(bot_log "$h2")"
fi

echo
if [ "$fail" = "0" ]; then
  echo "ALL PASS"
else
  echo "SOME FAILED"
fi
exit "$fail"
