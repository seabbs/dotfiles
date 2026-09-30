#!/bin/bash
# bot-tasks-scan.sh — find work seabbs has asked seabbs-bot to do, and
# freeze what it says before anyone can edit it.
#
# Two commands, so discovery can be read-only and auditable:
#   bot-tasks-scan.sh              list unclaimed tasks as JSON
#   bot-tasks-scan.sh --claim REPO COMMENT_ID   react eyes, then print the
#                                               frozen snapshot
#
# The rules it enforces, all of them mechanical rather than left to the
# agent reading the thread:
#
#   Only seabbs gives instructions. A tag from anyone else is not a task,
#   and no one else's comment is an instruction however it is phrased.
#   Every other participant is context, labelled as such, because an issue
#   on a public repo is written by whoever turns up.
#
#   Only the tagging comment is the instruction. It is captured with its
#   updated_at, so an edit after the fact cannot change what was asked.
#
#   The thread is frozen at the tag. Comments created after it are left
#   out entirely, and a comment edited after it is passed through marked
#   edited_after_tag so the agent knows not to rely on it.
#
#   The eyes reaction is the claim, and GitHub holds it. Nothing is
#   remembered locally, so a lost container cannot cause a task to be
#   picked up twice, and you can see what has been claimed by looking.
#
# GH_TOKEN must be seabbs-bot's. Reacting as anyone else breaks the claim.

set -uo pipefail

OWNER_USER="${BOT_TASKS_OWNER:-seabbs}"
BOT_USER="${BOT_TASKS_BOT:-seabbs-bot}"
# Where the bot may work. An owner not listed here is ignored even if the
# bot can see the repo, so read access can never become a work queue.
OWNERS="${BOT_TASKS_OWNERS:-seabbs epinowcast epiforecasts EpiAware nfidd}"
# The mention must start a line, which is how you address someone rather
# than talk about them. Testing this against real threads, a plain "mentions
# the bot" match picked up "I did a large scan with a team of @seabbs-bot"
# and "happy to allocate to @seabbs-bot" as if they were orders. A quoted
# line starts with ">" and so cannot trigger either. jq's regex anchors to
# start of the string, so the newline alternative is what reads the rest
# of the lines.
TRIGGER_RE="(^|\\n)[[:space:]]*@${BOT_USER}\\b"
# An issue or PR carrying this is off limits, whatever it says.
SKIP_LABEL="${BOT_TASKS_SKIP_LABEL:-no-bot}"
# How far back to look. A tag older than this has been missed for days
# and wants a human, not a surprise commit.
SINCE_DAYS="${BOT_TASKS_SINCE_DAYS:-14}"

die() { echo "bot-tasks-scan: $*" >&2; exit 1; }
command -v gh >/dev/null || die "gh not found"
command -v jq >/dev/null || die "jq not found"

since="$(date -u -v-"${SINCE_DAYS}"d +%Y-%m-%d 2>/dev/null \
  || date -u -d "${SINCE_DAYS} days ago" +%Y-%m-%d)"

# Issues and PRs in the allowed owners that mention the bot and that
# seabbs has commented on. Both qualifiers matter: mentions alone pulls in
# every thread where someone else named the bot.
search_threads() {
  local q="mentions:$BOT_USER commenter:$OWNER_USER updated:>=$since" o
  for o in $OWNERS; do q="$q user:$o"; done
  gh api -X GET search/issues --paginate \
    -f q="$q" -f per_page=100 \
    --jq '.items[] | {url: .repository_url, number, labels: [.labels[].name],
                      state, pull_request: (.pull_request != null)}' \
    2>/dev/null
}

# Every comment on one thread, plus the opening post, oldest first and in
# one shape. The issue body is comment id 0: it is part of what was being
# discussed when the tag landed, and it can be edited like any comment.
thread_comments() {
  local repo="$1" number="$2"
  { gh api "repos/$repo/issues/$number" \
      --jq '{id: 0, author: .user.login, created_at, updated_at,
             body: (.body // "")}' 2>/dev/null
    gh api "repos/$repo/issues/$number/comments" --paginate \
      --jq '.[] | {id, author: .user.login, created_at, updated_at,
                   body: (.body // "")}' 2>/dev/null
  } | jq -sc 'sort_by(.created_at)'
}

# Has the bot already claimed this comment? The reaction is the only
# record, so this is the whole dedup.
claimed() {
  local repo="$1" id="$2"
  [ "$id" = "0" ] && return 1
  gh api "repos/$repo/issues/comments/$id/reactions" --paginate \
    --jq ".[] | select(.content == \"eyes\")
          | select(.user.login == \"$BOT_USER\") | .id" 2>/dev/null \
    | grep -q .
}

# The task, with the thread as it stood when the tag was written.
snapshot() {
  local repo="$1" number="$2" tag_id="$3" comments="$4" is_pr="$5"
  jq -nc --arg repo "$repo" --argjson number "$number" \
    --argjson tag_id "$tag_id" --argjson comments "$comments" \
    --argjson is_pr "$is_pr" --arg owner "$OWNER_USER" '
    ($comments | map(select(.id == $tag_id)) | first) as $tag
    | {
        repo: $repo,
        number: $number,
        is_pull_request: $is_pr,
        url: ("https://github.com/" + $repo + "/issues/" + ($number|tostring)),
        # The instruction, and nothing else. Frozen here so a later edit
        # cannot rewrite the task after it has been claimed.
        instruction: {
          comment_id: $tag.id,
          author: $tag.author,
          asked_at: $tag.created_at,
          edited: ($tag.updated_at != $tag.created_at),
          body: $tag.body
        },
        # Context only. Anything said after the tag is not here at all;
        # anything edited after it is flagged rather than trusted.
        context: [$comments[]
          | select(.id != $tag_id)
          | select(.created_at <= $tag.created_at)
          | {id, author, created_at,
             authority: (if .author == $owner then "owner" else "other" end),
             edited_after_tag: (.updated_at > $tag.created_at),
             body}]
      }'
}

# ------------------------------------------------------------------ claim

if [ "${1:-}" = "--claim" ]; then
  repo="${2:-}"; comment_id="${3:-}"
  [ -n "$repo" ] && [ -n "$comment_id" ] \
    || die "usage: $0 --claim owner/repo comment_id"

  # Everything the scan checked, checked again here. The caller is an agent
  # that has just read a pile of issue text, so --claim cannot be a way to
  # turn any comment into a task by naming it. A confused or steered agent
  # asking to claim a stranger's comment gets a refusal, not a snapshot
  # with someone else's words in the instruction field.
  case " $OWNERS " in
    *" ${repo%%/*} "*) ;;
    *) die "$repo is not in an allowed owner" ;;
  esac
  # gh prints its error body on stdout, so a 404 comes back as a non-empty
  # object. Key on the id being there rather than on the output existing.
  comment="$(gh api "repos/$repo/issues/comments/$comment_id" 2>/dev/null)"
  jq -e '.id' <<< "$comment" >/dev/null 2>&1 \
    || die "no such comment: $repo $comment_id"
  author="$(jq -r '.user.login // ""' <<< "$comment")"
  [ "$author" = "$OWNER_USER" ] \
    || die "comment $comment_id is by $author, not $OWNER_USER"
  jq -e --arg re "$TRIGGER_RE" '.body // "" | test($re)' <<< "$comment" \
    >/dev/null 2>&1 || die "comment $comment_id does not ask for anything"

  number="$(jq -r '.issue_url | split("/") | last' <<< "$comment")"
  [ -n "$number" ] || die "could not resolve the thread for $comment_id"
  gh api "repos/$repo/issues/$number" \
    --jq "[.labels[].name] | index(\"$SKIP_LABEL\")" 2>/dev/null \
    | grep -qv '^null$' && die "$repo#$number carries $SKIP_LABEL"

  # Claim first, work second. A crash after this leaves a visible eyes with
  # no reply, which is recoverable; working first and crashing before the
  # claim is how a task gets done twice.
  claimed "$repo" "$comment_id" && die "already claimed $repo#$comment_id"
  gh api -X POST "repos/$repo/issues/comments/$comment_id/reactions" \
    -f content=eyes >/dev/null 2>&1 || die "could not react on $repo"
  is_pr="$(gh api "repos/$repo/issues/$number" \
    --jq '.pull_request != null' 2>/dev/null)"
  snapshot "$repo" "$number" "$comment_id" \
    "$(thread_comments "$repo" "$number")" "${is_pr:-false}"
  exit 0
fi

# ------------------------------------------------------------------- scan

echo "["
first=true
while IFS= read -r thread; do
  [ -n "$thread" ] || continue
  repo="$(jq -r '.url | sub("^.*/repos/"; "")' <<< "$thread")"
  number="$(jq -r '.number' <<< "$thread")"
  is_pr="$(jq -r '.pull_request' <<< "$thread")"
  state="$(jq -r '.state' <<< "$thread")"
  [ "$state" = "open" ] || continue
  jq -e --arg l "$SKIP_LABEL" '.labels | index($l)' <<< "$thread" \
    >/dev/null 2>&1 && continue

  comments="$(thread_comments "$repo" "$number")"
  [ -n "$comments" ] || continue

  # Newest tag first: if seabbs asked twice, the latest ask is the one
  # that reflects what he wants now.
  while IFS= read -r tag_id; do
    [ -n "$tag_id" ] && [ "$tag_id" != "0" ] || continue
    claimed "$repo" "$tag_id" && continue
    $first || echo ","
    first=false
    snapshot "$repo" "$number" "$tag_id" "$comments" "$is_pr"
    break
  done < <(jq -r --arg owner "$OWNER_USER" --arg re "$TRIGGER_RE" '
      [.[] | select(.author == $owner) | select(.body | test($re))]
      | sort_by(.created_at) | reverse | .[].id' <<< "$comments")
done < <(search_threads)
echo "]"
