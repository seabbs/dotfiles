#!/bin/bash
# dep-prs-scan.sh — find automated dependency PRs whose CI is red, so the
# worker can make the package work with the new version of the dependency.
#
#   dep-prs-scan.sh            list candidates as JSON, newest first
#
# Discovery only. Nothing is claimed and nothing is written, so this can
# be run to see what the worker would look at without it looking.
#
# The rules it enforces, mechanically rather than left to the agent:
#
#   Only a dependency bot's PR counts. dependabot opens its own; the
#   CompatHelper workflow opens Julia compat bumps as github-actions,
#   which also opens plenty of PRs that are nothing to do with deps, so
#   that author only counts with a CompatHelper title.
#
#   Only red PRs. A green bump needs no work, and merging it is a human's
#   decision, not the bot's.
#
#   Only settled CI. A PR with a job still running is left for the next
#   run rather than diagnosed from a half-finished log.
#
#   Only quiet branches. Anything pushed in the last half hour is
#   someone else mid-thought, including dependabot rebasing its own
#   branch.
#
#   Only twice. The bot's own commits on the branch are the attempt
#   count, so GitHub holds it and a lost container cannot reset it.
#
#   Nothing archived, nothing draft, nothing labelled no-bot, and nothing
#   outside the allowed owners.
#
# Note on pushing to these branches: once anyone other than dependabot
# commits to one of its PRs, dependabot stops rebasing that PR. That is
# the behaviour we want — the branch becomes ours — but it means the base
# will go stale, so finish the PR or say why you could not.
#
# GH_TOKEN should be seabbs-bot's, as for the rest of the bot scripts.

set -uo pipefail

BOT_USER="${DEP_PRS_BOT:-seabbs-bot}"
# Where the bot may work. An owner not listed here is ignored even if the
# bot can see the repo, so read access can never become a work queue.
OWNERS="${DEP_PRS_OWNERS:-seabbs epinowcast epiforecasts EpiAware nfidd}"
# A PR carrying this is off limits, whatever it says.
SKIP_LABEL="${DEP_PRS_SKIP_LABEL:-no-bot}"
# Older than this and the bump has been sitting unloved for months. Those
# want a human deciding whether the package is still alive, not a bot
# spending an hour on a compat bound nobody wants.
SINCE_DAYS="${DEP_PRS_SINCE_DAYS:-60}"
# A branch pushed more recently than this is someone else's, for now.
QUIET_MINUTES="${DEP_PRS_QUIET_MINUTES:-30}"
# Attempts, counted as the bot's own commits on the branch.
MAX_ATTEMPTS="${DEP_PRS_MAX_ATTEMPTS:-2}"
# CompatHelper runs as github-actions, which opens much else besides.
COMPAT_RE="${DEP_PRS_COMPAT_RE:-^CompatHelper:}"

PR_FIELDS="number,title,url,isDraft,headRefName,baseRefName"
PR_FIELDS="$PR_FIELDS,updatedAt,statusCheckRollup,commits"

die() { echo "dep-prs-scan: $*" >&2; exit 1; }
command -v gh >/dev/null || die "gh not found"
command -v jq >/dev/null || die "jq not found"

since="$(date -u -v-"${SINCE_DAYS}"d +%Y-%m-%d 2>/dev/null \
  || date -u -d "${SINCE_DAYS} days ago" +%Y-%m-%d)"
now="$(date -u +%s)"

# Open PRs in the allowed owners by either dependency bot. `archived:false`
# keeps the frozen repos out: their CI cannot be fixed and their PRs
# cannot be merged.
search_prs() {
  local q o
  q="is:open is:pr archived:false"
  q="$q author:app/dependabot author:app/github-actions"
  q="$q updated:>=$since"
  for o in $OWNERS; do q="$q user:$o"; done
  gh api -X GET search/issues --paginate \
    -f q="$q" -f per_page=100 -f sort=updated -f order=desc \
    --jq '.items[] | {repo: (.repository_url | sub("^.*/repos/"; "")),
                      number, title, author: .user.login,
                      labels: [.labels[].name]}' \
    2>/dev/null
}

# Is this author allowed to set the bot working? dependabot always;
# github-actions only when the title says CompatHelper, because that
# account opens release PRs, docs PRs and whatever else a workflow asks.
is_dep_pr() {
  local author="$1" title="$2"
  case "$author" in
    dependabot|dependabot\[bot\]) return 0 ;;
    github-actions|github-actions\[bot\])
      [[ "$title" =~ $COMPAT_RE ]] && return 0 ;;
  esac
  return 1
}

echo "["
first=true
while IFS= read -r item; do
  [ -n "$item" ] || continue
  repo="$(jq -r '.repo' <<< "$item")"
  number="$(jq -r '.number' <<< "$item")"
  title="$(jq -r '.title' <<< "$item")"
  author="$(jq -r '.author' <<< "$item")"

  case " $OWNERS " in
    *" ${repo%%/*} "*) ;;
    *) continue ;;
  esac
  is_dep_pr "$author" "$title" || continue
  jq -e --arg l "$SKIP_LABEL" '.labels | index($l)' <<< "$item" \
    >/dev/null 2>&1 && continue

  pr="$(gh pr view "$number" -R "$repo" --json "$PR_FIELDS" 2>/dev/null)"
  jq -e '.number' <<< "$pr" >/dev/null 2>&1 || continue
  [ "$(jq -r '.isDraft' <<< "$pr")" = "true" ] && continue

  # CI must have finished. Judging a red PR while half its jobs are still
  # running means reading a log that is about to change.
  pending="$(jq '[.statusCheckRollup[]?
    | select((.status // .state)
             | IN("QUEUED", "IN_PROGRESS", "PENDING", "WAITING",
                  "REQUESTED"))] | length' <<< "$pr")"
  [ "${pending:-0}" -gt 0 ] && continue

  failing="$(jq -c '[.statusCheckRollup[]?
    | select((.conclusion // .state)
             | IN("FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ERROR"))
    | {name: (.name // .context), url: (.detailsUrl // .targetUrl)}]' \
    <<< "$pr")"
  [ "$(jq 'length' <<< "$failing")" -eq 0 ] && continue

  # The last push decides whether this branch is anyone else's right now.
  last_at="$(jq -r '.commits[-1].committedDate // empty' <<< "$pr")"
  [ -n "$last_at" ] || continue
  last_epoch="$(date -u -d "$last_at" +%s 2>/dev/null \
    || date -u -j -f '%Y-%m-%dT%H:%M:%SZ' "$last_at" +%s 2>/dev/null \
    || echo 0)"
  [ $(( (now - last_epoch) / 60 )) -lt "$QUIET_MINUTES" ] && continue

  # Our own commits are the attempt count. Two failed goes at the same
  # bump is enough; a third is the same hour spent again.
  attempts="$(jq --arg b "$BOT_USER" \
    '[.commits[]? | select([.authors[]?.login] | index($b))] | length' \
    <<< "$pr")"
  [ "${attempts:-0}" -ge "$MAX_ATTEMPTS" ] && continue

  $first || echo ","
  first=false
  jq -c --arg repo "$repo" --arg author "$author" \
    --argjson failing "$failing" --argjson attempts "${attempts:-0}" '{
      repo: $repo, number, title, author: $author, url,
      head_ref: .headRefName, base_ref: .baseRefName,
      updated_at: .updatedAt, attempts: $attempts, failing: $failing
    }' <<< "$pr"
done < <(search_prs)
echo "]"
