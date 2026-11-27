#!/bin/bash
# Checks that pr-context.sh shows a PR and an issue correctly, and that
# the parts only a PR has stay out of an issue.
#
# No bats/shellspec harness exists for these scripts, so this stubs `gh`
# with fixtures for one PR (101), one issue (93) and a number that does
# not resolve (404). Verifies:
#
#   1. a PR shows its state, branches, body, conversation and files.
#   2. a failing check is named and a passing one is not. The point of
#      the line is what to go and look at.
#   3. an unresolved thread is marked UNRESOLVED and a resolved one is
#      not, since that is the difference between work left and work done.
#   4. an issue renders, with its labels, and without the branch, check,
#      thread, review and file sections a PR has.
#   5. --json passes the object through with its real type.
#   6. junk, nothing, and a number that does not resolve all fail, and
#      say so rather than printing an empty report.
#
# Usage: test-pr-context.sh [path-to-scripts-dir]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/pc-test.XXXXXX")"
[ -n "${PC_TEST_KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cp "$HERE/stub-gh-pr-context" "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
export PC_TEST_CALLS="$WORK/calls.log"
export PATH="$WORK/bin:$PATH"
: > "$PC_TEST_CALLS"

S="$SRC_SCRIPTS/pr-context.sh"
[ -x "$S" ] || { echo "FAIL: $S is not executable"; exit 1; }

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }
has()   { grep -q -- "$2" <<< "$1"; }
hasnt() { ! grep -q -- "$2" <<< "$1"; }

pr="$($S seabbs/dotfiles#101 2>&1)"

has "$pr" "feat/x → main" && has "$pr" "+412 −0" \
  && pass "a PR shows its branches and size" \
  || bad "the PR header is missing branches or size"

has "$pr" "A comment." && has "$pr" "The body." \
  && pass "a PR shows its body and conversation" \
  || bad "the PR body or conversation is missing"

if has "$pr" "tests FAILURE" && hasnt "$pr" "lint SUCCESS"; then
  pass "a failing check is named, a passing one is not"
else
  bad "check filtering is wrong"
fi

if has "$pr" "scripts/a.sh:12  UNRESOLVED" \
  && has "$pr" "scripts/b.sh:3  resolved"; then
  pass "threads are marked resolved or not"
else
  bad "thread resolution is not shown correctly"
fi

has "$pr" "REVIEW THREADS (1 open of 2)" \
  && pass "open threads are counted" \
  || bad "the open thread count is wrong"

issue="$($S seabbs/dotfiles#93 2>&1)"

has "$issue" "#93  OPEN  issue" && has "$issue" "\[enhancement\]" \
  && pass "an issue is labelled as one, with its labels" \
  || bad "the issue header is wrong"

if hasnt "$issue" "REVIEW THREADS" && hasnt "$issue" "FILES" \
  && hasnt "$issue" "CHECKS" && hasnt "$issue" "→"; then
  pass "an issue leaves out the sections only a PR has"
else
  bad "a PR-only section appeared on an issue"
fi

[ "$($S --json seabbs/dotfiles#101 | jq -r .__typename)" = "PullRequest" ] \
  && [ "$($S --json seabbs/dotfiles#93 | jq -r .__typename)" = "Issue" ] \
  && pass "--json passes the object through with its real type" \
  || bad "--json returned the wrong type"

$S junk >/dev/null 2>&1; [ $? -eq 2 ] \
  && pass "junk exits 2" || bad "junk did not exit 2"
$S >/dev/null 2>&1; [ $? -eq 2 ] \
  && pass "no argument exits 2" || bad "no argument did not exit 2"

out="$($S seabbs/dotfiles#404 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && has "$out" "could not read"; then
  pass "a number that does not resolve fails, and says so"
else
  bad "an unresolvable number did not fail cleanly (rc=$rc)"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "all pr-context checks passed"
else
  echo "pr-context checks FAILED"
fi
exit "$fail"
