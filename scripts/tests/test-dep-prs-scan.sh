#!/bin/bash
# Checks that dep-prs-scan.sh offers the worker exactly the dependency
# PRs that are worth an hour of its time, and nothing else.
#
# No bats/shellspec harness exists for these scripts, so this stubs `gh`
# with ten PRs, one per case. Verifies:
#
#   1. a red, settled, quiet dependabot PR is listed, with the failing
#      check named and the passing one left out.
#   2. a green PR is not listed. Nothing to fix, and merging is not the
#      bot's call.
#   3. a PR with a job still running is not listed. Diagnosing half a run
#      means reading a log that is about to change.
#   4. github-actions only counts as a dependency bot when the title says
#      CompatHelper. That account opens plenty else.
#   5. a no-bot label keeps a PR out.
#   6. a branch pushed five minutes ago is left alone.
#   7. two of the bot's own commits is enough; a third attempt is the
#      same hour spent again.
#   8. a draft is not listed.
#   9. an owner outside the allowlist is not listed, even though the
#      search returned it.
#  10. the attempt cap still holds when GitHub cannot resolve the commit
#      email to a login, which is the case where counting on login alone
#      would retry the same PR every run.
#  11. a gh that cannot search fails loudly. An empty array and exit 0
#      would read as "no dependency bumps" rather than as an error.
#  12. the output is a single JSON array, so the worker can read it.
#
# Usage: test-dep-prs-scan.sh [path-to-scripts-dir]
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/dp-test.XXXXXX")"
[ -n "${DP_TEST_KEEP:-}" ] || trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
cp "$HERE/stub-gh-dep-prs" "$WORK/bin/gh"
chmod +x "$WORK/bin/gh"
export DP_TEST_CALLS="$WORK/calls.log"
export PATH="$WORK/bin:$PATH"
: > "$DP_TEST_CALLS"

S="$SRC_SCRIPTS/dep-prs-scan.sh"
[ -x "$S" ] || { echo "FAIL: $S is not executable"; exit 1; }

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

out="$($S 2>/dev/null)"
listed() { jq -e --arg r "$1" 'any(.[]; .repo == $r)' <<< "$out" >/dev/null; }

if jq -e 'type == "array"' <<< "$out" >/dev/null 2>&1; then
  pass "the output is a JSON array"
else
  bad "the output is not a JSON array: $out"
fi

if listed seabbs/alpha; then
  pass "a red, settled, quiet dependabot PR is listed"
else
  bad "the one PR worth working on was not listed"
fi

names="$(jq -r '.[] | select(.repo == "seabbs/alpha")
                    | .failing[].name' <<< "$out")"
if [ "$names" = "test" ]; then
  pass "the failing check is named and the passing one is not"
else
  bad "failing checks are wrong: $names"
fi

listed seabbs/beta \
  && bad "a green PR was listed" \
  || pass "a green PR is not listed"

listed seabbs/gamma \
  && bad "a PR with CI still running was listed" \
  || pass "a PR with CI still running is not listed"

listed seabbs/delta \
  && bad "a non-CompatHelper github-actions PR was listed" \
  || pass "github-actions only counts with a CompatHelper title"

if listed seabbs/epsilon; then
  pass "a CompatHelper PR is listed"
else
  bad "a CompatHelper PR was not listed"
fi

listed seabbs/zeta \
  && bad "a no-bot PR was listed" \
  || pass "a no-bot label keeps a PR out"

listed seabbs/eta \
  && bad "a branch pushed five minutes ago was listed" \
  || pass "a freshly pushed branch is left alone"

listed seabbs/theta \
  && bad "a PR already tried twice was listed" \
  || pass "two attempts is enough"

listed seabbs/iota \
  && bad "a draft was listed" \
  || pass "a draft is not listed"

listed seabbs/lambda \
  && bad "a PR tried twice without a resolvable login was listed" \
  || pass "the attempt cap holds without a resolvable login"

listed outside/kappa \
  && bad "a PR outside the allowed owners was listed" \
  || pass "an owner outside the allowlist is ignored"

# The search must be scoped in the query, not only filtered afterwards.
if grep -q "archived:false" "$DP_TEST_CALLS"; then
  pass "archived repositories are excluded in the search"
else
  bad "the search does not exclude archived repositories"
fi

# A PR filtered on author or label must not cost a second round trip.
if grep -q "seabbs/delta" "$DP_TEST_CALLS" \
   || grep -q "seabbs/zeta" "$DP_TEST_CALLS"; then
  bad "a PR ruled out by the listing was fetched anyway"
else
  pass "PRs ruled out by the listing are not fetched"
fi

if out2="$(DP_STUB_SEARCH_FAILS=1 $S 2>/dev/null)"; then
  bad "a failing search exited 0: $out2"
elif [ -n "$out2" ]; then
  bad "a failing search still printed something: $out2"
else
  pass "a failing search fails loudly rather than printing no work"
fi

[ "$fail" -eq 0 ] && echo "all dep-prs-scan tests passed"
exit "$fail"
