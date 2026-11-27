#!/bin/bash
# Checks the round helpers in scripts/review-bot-rounds.sh: which round a
# review is, the prompt text each round gets, and that past findings are
# handed back so the bot does not repeat them.
#
# Usage: test-review-bot-rounds.sh [path-to-scripts-dir]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
# shellcheck source=SCRIPTDIR/../review-bot-rounds.sh
. "$SRC_SCRIPTS/review-bot-rounds.sh"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rb-rounds.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }
is() { if [ "$2" = "$3" ]; then pass "$1"; else bad "$1: got '$3'"; fi; }
has() {
  if grep -qF -- "$2" <<< "$3"; then pass "$1"; else bad "$1: $3"; fi
}
lacks() {
  if grep -qF -- "$2" <<< "$3"; then bad "$1: $3"; else pass "$1"; fi
}

echo "== review_round =="
hist="$WORK/history.tsv"
is "first review is round 1" 1 "$(review_round "$hist" o/r#1)"
printf 't\to/r#1\taaa\tx\t0\t0\nt\to/r#2\tbbb\tx\t0\t0\n' > "$hist"
printf 't\to/r#1\tccc\tx\t0\t0\n' >> "$hist"
is "counts only this PR" 3 "$(review_round "$hist" o/r#1)"
is "other PR" 2 "$(review_round "$hist" o/r#2)"

echo
echo "== round_scope =="
full=base..head
out="$(round_scope 1 "" "$full")"
has "round 1 reads the full diff" "git diff $full" "$out"
lacks "round 1 no step back" "step back" "$out"
out="$(round_scope 2 aaa "$full")"
lacks "round 2 still full" "since your last pass" "$out"
out="$(round_scope 3 aaa "$full")"
has "round 3 is diff only" "git diff aaa..head" "$out"
has "round 3 keeps full diff for context" "git diff $full" "$out"
out="$(round_scope 3 "" "$full")"
lacks "no last sha falls back to full" "since your last pass" "$out"
out="$(round_scope 4 aaa "$full")"
has "round 4 asks to step back" "step back" "$out"
out="$(REVIEW_BOT_STEP_BACK_AFTER=5 round_scope 4 aaa "$full")"
lacks "step back threshold is configurable" "step back" "$out"

echo
echo "== prior_findings =="
posted="$WORK/posted"
mkdir -p "$posted"
echo '{"review": {"summary": "s", "comments": [
  {"path": "R/a.R", "line": 3, "severity": "issue",
   "title": "Guard the empty case.", "body": "long why"},
  {"path": "R/b.R", "line": 9, "severity": "note", "body": "Old shape."}]}}' \
  > "$posted/o_r-1-aaaaaaaa.json"
echo '{"review": {"summary": "s", "comments": [
  {"path": "R/z.R", "line": 1, "title": "Other PR.", "body": "x"}]}}' \
  > "$posted/o_r-12-bbbbbbbb.json"
out="$(prior_findings "$posted" o/r 1)"
has "lists titled finding" "R/a.R:3 Guard the empty case." "$out"
has "falls back to body" "R/b.R:9 Old shape." "$out"
lacks "ignores other PRs" "Other PR." "$out"
is "nothing for a new PR" "" "$(prior_findings "$posted" o/r 5)"

echo
if [ "$fail" = "0" ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
