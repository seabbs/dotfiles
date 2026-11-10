#!/bin/bash
# Round helpers for review-bot.sh, sourced. A PR's later reviews change
# shape: from round DIFF_ONLY_FROM the bot reads only what moved since its
# last pass, and after STEP_BACK_AFTER rounds it asks the author to
# reconsider the approach instead of trading more line fixes. Past
# findings are handed back so it never repeats one.

# review_round <history.tsv> <owner/repo#N>: 1 for the first review.
review_round() {
  local n
  n="$(awk -F'\t' -v t="$2" '$2 == t' "$1" 2>/dev/null | wc -l)"
  echo $(( ${n:-0} + 1 ))
}

# round_scope <round> <last-reviewed-sha> <base..head>: how to read the
# change this round. An empty sha (unknown, or lost to a force-push)
# means a full read.
round_scope() {
  local round="$1" last="$2" full="$3" head="${3#*..}"
  local diff_from="${REVIEW_BOT_DIFF_ONLY_FROM:-3}"
  local step_after="${REVIEW_BOT_STEP_BACK_AFTER:-3}"

  if [ "$round" -ge "$diff_from" ] && [ -n "$last" ]; then
    cat <<EOF
This is review round $round. Review only what changed since your last pass:
  git diff --stat $last..$head
  git diff $last..$head
The full change is git diff $full. Read it for context, not for findings.
EOF
  else
    cat <<EOF
This is review round $round. Read the change first:
  git diff --stat $full
  git diff $full
EOF
  fi

  if [ "$round" -gt "$step_after" ]; then
    cat <<EOF

This PR has had $step_after rounds of review already and has not settled.
Open the summary by asking the author to step back and reconsider the
approach, and say what in the history suggests it is not converging.
Report only issue-level findings this round.
EOF
  fi
}

# prior_findings <posted-dir> <owner/repo> <N>: one line per finding this
# bot has already posted on the PR.
prior_findings() {
  local f files=()
  for f in "$1/${2//\//_}-$3-"*.json; do
    [ -f "$f" ] && files+=("$f")
  done
  [ "${#files[@]}" -gt 0 ] || return 0
  jq -r '.review.comments[]?
    | "- \(.path):\(.line) "
      + (if (.title // "") != "" then .title
         else (.body | .[0:200] | gsub("\n"; " ")) end)' "${files[@]}" \
    2>/dev/null
}
