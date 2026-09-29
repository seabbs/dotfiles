#!/bin/bash
# Dry-run based check for review-bot.sh's size-skip notice ledger.
#
# No bats/shellspec harness exists for these scripts, so this stubs `gh`
# (real git/jq/claude, though claude is never actually invoked: the
# skip-for-size path returns before a checkout is attempted) and runs
# review-bot.sh against an isolated $HOME. Verifies:
#
#   1. a size-skip notice is posted once and not re-announced on the
#      next poll for the same head SHA -- the epinowcast/epinowcast#834
#      spam bug (~276 repeated "Not reviewing this one" comments over
#      29 hours, one per ~5 minute poll, from 2026-09-28)
#   2. a --dry-run poll does not itself persist a notice -- the
#      seabbs-review-bot finding on PR #90 (discussion_r4092030497):
#      record_notice() ran unconditionally, so a dry run could suppress
#      a later live run without ever telling the PR anything
#   3. once the head SHA changes and the PR is back under the cap, it
#      is evaluated again rather than staying suppressed
#
# Usage: test-review-bot-skip-ledger.sh [path-to-scripts-dir]
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
  REVIEW_BOT_HARD_MAX_DIFF=100 \
  REVIEW_BOT_MAX_DIFF=50 \
  REVIEW_BOT_SANDBOX=0 \
  "$@" \
  "$DOTFILES_COPY/scripts/review-bot.sh" --pr epinowcast/epinowcast#834 \
    > "$home/run.out" 2>&1 || true
}

comment_count() {
  [ -f "$1/comments.log" ] && wc -l < "$1/comments.log" | tr -d ' ' || echo 0
}
notice_file() { echo "$1/.local/share/review-bot/notices/epinowcast_epinowcast#834"; }
bot_log() { cat "$1/.local/share/review-bot/last-run.log" 2>/dev/null; }

echo "== scenario 1: skip announced once, not on next poll =="
h1="$(new_home s1)"
run_bot "$h1" env RB_TEST_SHA=deadbeef
n1="$(comment_count "$h1")"
if [ "$n1" = "1" ]; then
  pass "first poll posts the skip notice once"
else
  bad "first poll posted $n1 comments, expected 1"
fi
if [ -f "$(notice_file "$h1")" ]; then
  pass "notice recorded after a live post"
else
  bad "no notice file after a live post"
fi

run_bot "$h1" env RB_TEST_SHA=deadbeef
n2="$(comment_count "$h1")"
if [ "$n2" = "1" ]; then
  pass "second poll, same head: no repeat comment"
else
  bad "second poll posted again, comments.log now has $n2 lines"
fi

echo
echo "== scenario 2: --dry-run does not persist a notice =="
h2="$(new_home s2)"
HOME="$h2" RB_TEST_CALLS="$h2/calls.log" RB_TEST_COMMENTS="$h2/comments.log" \
  RB_TEST_SHA=deadbeef REVIEW_BOT_HARD_MAX_DIFF=100 REVIEW_BOT_MAX_DIFF=50 \
  REVIEW_BOT_SANDBOX=0 \
  "$DOTFILES_COPY/scripts/review-bot.sh" --pr epinowcast/epinowcast#834 \
  --dry-run > "$h2/run.out" 2>&1 || true
if [ -f "$(notice_file "$h2")" ]; then
  bad "a --dry-run poll persisted a notice (the PR #90 finding)"
else
  pass "a --dry-run poll left no notice behind"
fi
dn="$(comment_count "$h2")"
if [ "${dn:-0}" = "0" ]; then
  pass "dry run posted no comment"
else
  bad "dry run posted a comment"
fi

echo
echo "== scenario 3: new head SHA under the cap is evaluated again =="
h3="$(new_home s3)"
run_bot "$h3" env RB_TEST_SHA=deadbeef RB_TEST_FILES_LINES=9000
[ "$(comment_count "$h3")" = "1" ] || bad "setup: first poll did not skip"

run_bot "$h3" env RB_TEST_SHA=cafef00d RB_TEST_FILES_LINES=10
if bot_log "$h3" | grep -q 'reviewing epinowcast/epinowcast#834'; then
  pass "PR pushed narrower (new SHA, under cap) is picked up again"
else
  bad "PR pushed narrower stayed suppressed: $(bot_log "$h3")"
fi

echo
if [ "$fail" = "0" ]; then
  echo "ALL PASS"
else
  echo "SOME FAILED"
fi
exit "$fail"
