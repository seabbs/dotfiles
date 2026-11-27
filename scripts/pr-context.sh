#!/usr/bin/env bash
# pr-context.sh — everything about a PR or issue, in one request.
#
#   pr-context.sh https://github.com/seabbs/dotfiles/pull/101
#   pr-context.sh seabbs/dotfiles#101
#   pr-context.sh 101                  (in a checkout of that repo)
#   pr-context.sh --json  ...          the same, structured
#   pr-context.sh --diff  ...          add the patch
#
# Paste a link and get the state, the conversation, the review threads and
# whether each is resolved, the checks and the changed files. Reading that
# by hand is five gh calls and some guessing about which comment answers
# which; this is one GraphQL query, so it is quick enough to run before
# every look rather than only when you are stuck.
#
# --json is for an agent, the default rendering is for a person. Same
# request either way: one source of facts, two ways of showing it, so an
# agent and the person reading over its shoulder cannot be looking at
# different things.
#
# Facts only. Nothing here decides whether the PR is any good, which is
# the slow, expensive half and belongs to a reviewer.

set -uo pipefail

JSON=false
DIFF=false
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=true; shift ;;
    --diff) DIFF=true; shift ;;
    --help|-h)
      awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
      exit 0 ;;
    *) break ;;
  esac
done

TARGET="${1:-}"
[ -n "$TARGET" ] || { echo "usage: pr-context.sh <url|owner/repo#n|n>" >&2
  exit 2; }

# Accept whatever is to hand: a pasted link, the shorthand, or a bare
# number in a checkout. A link is the common case because it is what
# GitHub gives you to copy.
owner=""; repo=""; number=""; kind="pr"
case "$TARGET" in
  http*://*/*/*/pull/*|http*://*/*/*/issues/*)
    rest="${TARGET#*://*/}"
    owner="${rest%%/*}"; rest="${rest#*/}"
    repo="${rest%%/*}";  rest="${rest#*/}"
    case "$rest" in issues/*) kind="issue" ;; esac
    number="${rest#*/}"; number="${number%%[!0-9]*}" ;;
  */*#*)
    owner="${TARGET%%/*}"
    repo="${TARGET#*/}"; repo="${repo%%#*}"
    number="${TARGET##*#}" ;;
  *[!0-9]*) echo "cannot read '$TARGET' as a PR" >&2; exit 2 ;;
  *)
    number="$TARGET"
    slug="$(gh repo view --json nameWithOwner --jq .nameWithOwner \
      2>/dev/null)"
    [ -n "$slug" ] || { echo "not in a repo; give owner/repo#$number" >&2
      exit 2; }
    owner="${slug%%/*}"; repo="${slug#*/}" ;;
esac
[ -n "$owner" ] && [ -n "$repo" ] && [ -n "$number" ] || {
  echo "cannot read '$TARGET' as a PR" >&2; exit 2; }

read -r -d '' QUERY <<'GQL'
query($owner:String!, $repo:String!, $number:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$number) {
      number title state isDraft mergeable reviewDecision
      author { login } createdAt updatedAt url body
      headRefName baseRefName additions deletions changedFiles
      comments(last:40) {
        nodes { author { login } createdAt body }
      }
      reviews(last:30) {
        nodes { author { login } state submittedAt body }
      }
      reviewThreads(last:40) {
        nodes {
          isResolved isOutdated path line
          comments(first:20) {
            nodes { author { login } createdAt body }
          }
        }
      }
      files(first:100) { nodes { path additions deletions } }
      commits(last:1) {
        nodes { commit { statusCheckRollup { state
          contexts(first:40) { nodes {
            __typename
            ... on CheckRun { name conclusion }
            ... on StatusContext { context state }
          } } } } }
      }
    }
  }
}
GQL

raw="$(gh api graphql -F owner="$owner" -F repo="$repo" \
  -F number="$number" -f query="$QUERY" 2>&1)"
if ! jq -e '.data.repository.pullRequest' >/dev/null 2>&1 <<< "$raw"; then
  echo "could not read $owner/$repo#$number" >&2
  jq -r '.errors[]?.message // empty' <<< "$raw" >&2 2>/dev/null
  exit 1
fi

pr="$(jq '.data.repository.pullRequest' <<< "$raw")"

if $JSON; then
  if $DIFF; then
    patch="$(gh pr diff "$number" -R "$owner/$repo" 2>/dev/null)"
    jq --arg d "$patch" '. + {diff: $d}' <<< "$pr"
  else
    printf '%s\n' "$pr"
  fi
  exit 0
fi

jq -r --arg slug "$owner/$repo" '
  def trim(n): if (. | length) > n then .[0:n] + " …" else . end;
  def clean: (. // "") | gsub("\r"; "");
  def block(s): (s | clean | split("\n")
    | map("  " + .) | .[0:40] | join("\n"));

  "\($slug)#\(.number)  \(.state)" +
    (if .isDraft then "  draft" else "" end) +
    "  mergeable:\(.mergeable // "?")" +
    "  review:\(.reviewDecision // "none")",
  .title,
  "\(.author.login)  \(.headRefName) → \(.baseRefName)" +
    "  +\(.additions) −\(.deletions)  \(.changedFiles) files" +
    "  updated \(.updatedAt)",
  "",
  (.commits.nodes[0].commit.statusCheckRollup as $c
   | if $c == null then "CHECKS  none reported"
     else "CHECKS  \($c.state)" + ( [$c.contexts.nodes[]
       | select((.conclusion // .state) as $s
                | $s != "SUCCESS" and $s != null)
       | "  " + (.name // .context) + " " + (.conclusion // .state)]
       | if length == 0 then "" else "\n" + join("\n") end)
     end),
  "",
  "BODY", block(.body),
  "",
  "CONVERSATION (\(.comments.nodes | length))",
  (.comments.nodes[]
   | "  \(.author.login)  \(.createdAt)\n" +
     (block(.body | trim(600)) | split("\n") | map("  " + .) | join("\n"))),
  "",
  ((.reviewThreads.nodes | map(select(.isResolved | not)) | length) as $open
   | (.reviewThreads.nodes | length) as $all
   | "REVIEW THREADS (\($open) open of \($all))"),
  (.reviewThreads.nodes[]
   | "  \(.path):\(.line // 0)  " +
     (if .isResolved then "resolved" else "UNRESOLVED" end) +
     (if .isOutdated then " outdated" else "" end) + "\n" +
     ([.comments.nodes[]
       | "    \(.author.login): " + (.body | clean
         | gsub("\n"; " ") | trim(300))] | join("\n"))),
  "",
  "REVIEWS (\(.reviews.nodes | length))",
  (.reviews.nodes[]
   | "  \(.author.login)  \(.state)  \(.submittedAt // "pending")"),
  "",
  "FILES (\(.files.nodes | length))",
  (.files.nodes[] | "  +\(.additions) −\(.deletions)  \(.path)")
' <<< "$pr"

if $DIFF; then
  echo
  echo "DIFF"
  gh pr diff "$number" -R "$owner/$repo" 2>/dev/null
fi
