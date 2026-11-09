#!/bin/bash
# Check review-bot.sh --tidy: the bot resolves and hides its own review
# threads once seabbs-bot has answered them, and hides a whole review once
# nothing in it is open. A stubbed `gh` serves a GraphQL fixture and logs
# the mutations, so nothing touches GitHub.
#
# Usage: test-review-bot-tidy.sh [path-to-scripts-dir]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/rb-tidy.XXXXXX")"
trap 'rm -rf "$WORK"' EXIT

DF="$WORK/dotfiles"
mkdir -p "$DF/scripts"
cp "$SRC_SCRIPTS/review-bot.sh" "$SRC_SCRIPTS/bot-common.sh" "$DF/scripts/"
# shellcheck disable=SC2016  # $1 belongs to the generated script
printf '#!/bin/bash\necho "test-token-$1"\n' > "$DF/scripts/review-bot-token.sh"
chmod +x "$DF/scripts/"*.sh

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }

# fixture <name> <head sha> <include open human thread: 0|1>
# R1: bot review on commit h1 with threads T1 (agent answered), T2
#     (already resolved) and optionally T3 (seabbs answered, stays open).
# R2: bot summary-only review on commit h2. R9: a human review.
fixture() {
  jq -n --arg head "$2" --argjson human "$3" '
    def c(id; who; rev): {id: id, author: {login: who}, isMinimized: false,
      pullRequestReview: {id: rev}};
    {data: {repository: {pullRequest: {
      headRefOid: $head,
      reviews: {nodes: [
        {id: "R1", author: {login: "seabbs-review-bot"}, isMinimized: false,
         commit: {oid: "h1"}},
        {id: "R2", author: {login: "seabbs-review-bot"}, isMinimized: false,
         commit: {oid: "h2"}},
        {id: "R9", author: {login: "seabbs"}, isMinimized: false,
         commit: {oid: "h1"}}]},
      reviewThreads: {nodes: ([
        {id: "T1", isResolved: false, comments: {nodes: [
          c("C1"; "seabbs-review-bot"; "R1"), c("C1r"; "seabbs-bot"; null)]}},
        {id: "T2", isResolved: true, comments: {nodes: [
          c("C2"; "seabbs-review-bot"; "R1")]}}] +
        (if $human == 1 then [
        {id: "T3", isResolved: false, comments: {nodes: [
          c("C3"; "seabbs-review-bot"; "R1"), c("C3r"; "seabbs"; null)]}}]
        else [] end))}}}}}' > "$WORK/$1.json"
}

run() {
  local name=$1 home="$WORK/home-$1"
  mkdir -p "$home/.local/bin"
  cp "$HERE/stub-gh-review-bot" "$home/.local/bin/gh"
  chmod +x "$home/.local/bin/gh"
  HOME="$home" RB_TEST_CALLS="$home/calls.log" \
    RB_TEST_COMMENTS="$home/comments.log" RB_TEST_GQL="$WORK/$name.json" \
    REVIEW_BOT_KEY=dummy REVIEW_BOT_SANDBOX=0 \
    "$DF/scripts/review-bot.sh" --tidy seabbs/demo#7 > "$home/run.out" 2>&1 \
    || true
  { grep 'graphql' "$home/calls.log" 2>/dev/null | grep -v 'query=query' \
    | grep -o 'id=[A-Za-z0-9]*' | sort | tr '\n' ' '; } || true
}

echo "== open human thread, head unchanged =="
fixture open h2 1
got="$(run open)"
if [ "$got" = "id=C1 id=C2 id=T1 " ]; then
  pass "resolves T1, hides C1 and C2, leaves T3, R1 and R2"
else
  bad "mutations were: $got"
fi

echo "== nothing open, head moved =="
fixture handled h3 0
got="$(run handled)"
if [ "$got" = "id=C1 id=C2 id=R1 id=R2 id=T1 " ]; then
  pass "also hides R1 (all handled) and R2 (head moved)"
else
  bad "mutations were: $got"
fi

if [ "$fail" = "0" ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
