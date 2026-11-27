#!/bin/bash
# Checks that triage.sh puts the right things at the top and keeps the
# noise out of the way.
#
# No bats/shellspec harness exists for these scripts, so this stubs `gh`
# and a `gh-notify.sh` beside a copy of triage.sh, which resolves both
# from its own directory. Verifies:
#
#   1. asks come first. They are the only rows nobody else will chase.
#   2. a dependency bump is moved under its own heading rather than
#      sitting in the queue. They outnumber real review requests here by
#      about four to one, so leaving them in hides everything else.
#   3. a review request from a person stays in the queue, with their name.
#   4. an item already listed is not listed again further down.
#   5. a ci_activity notification becomes a CI row.
#   6. each row carries the repo, number and thread an action needs.
#
# Usage: test-triage.sh [path-to-scripts-dir]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/tr-test.XXXXXX")"
[ -n "${TR_TEST_KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin" "$WORK/scripts"
cp "$HERE/stub-gh-triage" "$WORK/bin/gh"
cp "$SRC_SCRIPTS/triage.sh" "$WORK/scripts/triage.sh"
chmod +x "$WORK/bin/gh" "$WORK/scripts/triage.sh"

# The notify half is stubbed rather than run: its own behaviour has its
# own test, and what matters here is what triage does with the answer.
cat > "$WORK/scripts/gh-notify.sh" <<'NOTIFY'
#!/bin/bash
printf 'ask\tseabbs-bot\tmention\t%s\t1276\t%s\t111\n' \
  "seabbs/bdbv-hub-modelling" "Fine-tuning question"
printf 'keep\t%s\tci_activity\t%s\t77\t%s\t222\n' \
  "github-actions[bot]" "EpiAware/Foo.jl" "AD workflow failed"
printf 'muted\tseabbs-bot\tmention\tseabbs/other\t9\tpure noise\t333\n'
NOTIFY
chmod +x "$WORK/scripts/gh-notify.sh"

export TR_TEST_CALLS="$WORK/calls.log"
export PATH="$WORK/bin:$PATH"
: > "$TR_TEST_CALLS"

out="$("$WORK/scripts/triage.sh" --list 2>/dev/null)"
disp="$(cut -d$'\t' -f1 <<< "$out")"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

line_of() { grep -n -- "$1" <<< "$disp" | head -1 | cut -d: -f1; }

[ "$(sed -n '1p' <<< "$disp" | cut -c1-3)" = "ASK" ] \
  && pass "asks come first" || bad "the first row is not an ask"

if grep -q "^BUMP .*dependabot" <<< "$disp"; then
  pass "a dependency bump is labelled as one"
else
  bad "the dependabot PR was not marked BUMP"
fi

if [ "$(line_of 'BUMP')" -gt "$(line_of 'REV  kaitejohnson')" ]; then
  pass "bumps sit below the real review requests"
else
  bad "a bump outranked a person's review request"
fi

grep -q "REV  kaitejohnson .*A person asks for review" <<< "$disp" \
  && pass "a person's review request keeps their name" \
  || bad "the human review request is missing or unnamed"

if [ "$(grep -c "1276\|Already an ask\|Fine-tuning question" <<< "$disp")" \
  -eq 1 ]; then
  pass "an item already listed is not listed again"
else
  bad "a duplicate row appeared for an item already listed"
fi

# 13 chars wide, so the actor shows as github-action
grep -q "^CI   github-action" <<< "$disp" \
  && pass "a ci_activity notification becomes a CI row" \
  || bad "the CI notification did not become a row"

grep -q "pure noise" <<< "$disp" \
  && bad "a muted row leaked into the list" \
  || pass "muted rows stay out"

askrow="$(grep -m1 '^ASK' <<< "$out")"
IFS=$'\t' read -r _ type repo number thread <<< "$askrow"
if [ "$repo" = "seabbs/bdbv-hub-modelling" ] && [ "$number" = "1276" ] \
  && [ "$thread" = "111" ] && [ "$type" = "pr" ]; then
  pass "rows carry the repo, number and thread an action needs"
else
  bad "row fields wrong: type=$type repo=$repo n=$number thread=$thread"
fi

echo
if [ "$fail" -eq 0 ]; then
  echo "all triage checks passed"
else
  echo "triage checks FAILED"
fi
exit "$fail"
