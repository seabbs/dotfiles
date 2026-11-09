#!/bin/bash
# Checks scripts/review-bot-format.jq lays reviews out with a short visible
# line and the detail collapsed in <details>, so a reader can skim.
#
# Usage: test-review-bot-format.sh [path-to-scripts-dir]
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC_SCRIPTS="${1:-$(dirname "$HERE")}"
FMT="$SRC_SCRIPTS/review-bot-format.jq"

fail=0
pass() { echo "PASS: $1"; }
bad()  { echo "FAIL: $1"; fail=1; }
has() {
  if grep -qF -- "$2" <<< "$3"; then pass "$1"; else bad "$1: $3"; fi
}
lacks() {
  if grep -qF -- "$2" <<< "$3"; then bad "$1: $3"; else pass "$1"; fi
}

review='{"summary": "Adds a cache. Sound apart from one bug.",
  "detail": "The cache key ignores the locale.",
  "comments": [
    {"path": "R/a.R", "line": 3, "severity": "issue",
     "title": "Include the locale in the cache key.",
     "body": "Two locales share an entry. Use paste(key, locale)."},
    {"path": "R/b.R", "line": 9, "severity": "note",
     "body": "Old shape with no title."}]}'

fmt() {
  jq -n --argjson review "$review" --arg sha abc --arg footer "FOOT" \
    --arg mode "$1" -f "$FMT"
}

echo "== inline review =="
out="$(fmt inline)"
body="$(jq -r .body <<< "$out")"
c1="$(jq -r '.comments[0].body' <<< "$out")"
c2="$(jq -r '.comments[1].body' <<< "$out")"
has "verdict visible first" "Adds a cache. Sound apart from one bug." \
  "$(head -n 1 <<< "$body")"
has "detail collapsed" "<summary>Detail</summary>" "$body"
has "footer collapsed" "<summary>About this review</summary>" "$body"
has "blank line after summary" $'</summary>\n\nThe cache key' "$body"
has "headline visible" "**issue** Include the locale in the cache key." \
  "$(head -n 1 <<< "$c1")"
has "why collapsed" "<summary>Why and how to fix</summary>" "$c1"
has "fix inside block" $'\n\nTwo locales share an entry.' "$c1"
has "closes block" $'paste(key, locale).\n\n</details>' "$c1"
has "untitled comment stays plain" "**note** Old shape with no title." "$c2"
lacks "untitled comment has no block" "<details>" "$c2"
has "inline fields kept" "R/a.R 3 RIGHT abc" \
  "$(jq -r '"\(.comments[0].path) \(.comments[0].line)'\
' \(.comments[0].side) \(.commit_id)"' <<< "$out")"

echo
echo "== plain fallback =="
out="$(fmt plain)"
body="$(jq -r .body <<< "$out")"
has "no inline comments" "null" "$(jq -c .comments <<< "$out")"
has "comment as dropdown" \
  "<summary>issue: R/a.R:3 Include the locale in the cache key.</summary>" \
  "$body"
has "untitled comment as dropdown" \
  "<summary>note: R/b.R:9</summary>" "$body"

echo
echo "== no detail, no comments =="
review='{"summary": "Looks fine.", "comments": []}'
body="$(fmt inline | jq -r .body)"
lacks "no empty detail block" "<summary>Detail</summary>" "$body"

echo
if [ "$fail" = "0" ]; then echo "ALL PASS"; else echo "SOME FAILED"; fi
exit "$fail"
