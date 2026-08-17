#!/bin/bash
# review-bot.sh — first-pass review of my own and my bot's pull requests,
# posted as the seabbs-review-bot GitHub App.
#
# Why an app and not seabbs-bot: GitHub refuses APPROVE / REQUEST_CHANGES
# from the PR author, so a seabbs-bot review of a seabbs-bot PR reads as
# the author talking to itself. See review-bot-token.sh for the one-off
# app setup.
#
# What it reviews, deliberately narrow:
#   - automatically: open PRs authored by seabbs or seabbs-bot in the
#     owners listed below, once, when the PR first opens
#   - on request: any PR in those owners where seabbs (never seabbs-bot)
#     comments @seabbs-review-bot, including drafts, older PRs and other
#     work, and however many times he asks
# Everything else is left alone. It never approves, never requests changes,
# never pushes, and never edits a PR.
#
# Usage:
#   review-bot.sh                     poll and review (what cron runs)
#   review-bot.sh --dry-run           find work, print the review, post none
#   review-bot.sh --pr owner/repo#42  review one PR now, skipping discovery
#   review-bot.sh --force             ignore "already reviewed" state
#   review-bot.sh --list              show what it would pick up, then stop
#
# Interactive runs print to the terminal. Cron runs log only.

set -uo pipefail

# cron hands over a two-entry PATH; gh, claude and git live in brew.
PATH="$HOME/.local/bin:/home/linuxbrew/.linuxbrew/bin:/opt/homebrew/bin"
PATH="$PATH:/usr/local/bin:/usr/bin:/bin"
export PATH

DOTFILES="$(cd "$(dirname "$0")/.." && pwd)"
TOKEN_SH="$DOTFILES/scripts/review-bot-token.sh"
BUDGET_SH="$HOME/.claude/hooks/compute-budget.sh"

# Owners to watch. user: for personal repos, org: for organisations; the
# search ORs repeated owner qualifiers.
OWNERS="user:seabbs org:epinowcast org:epiforecasts org:EpiAware"
# PR authors whose work gets an automatic first pass.
AUTHORS="author:seabbs author:seabbs-bot"
# Only a human can ask for a re-review, so agent chatter cannot loop it.
TRIGGER_USER="seabbs"
# Asking the reviewer by name, the way you would ask a person. GitHub will
# not render it as a real mention, because the app's login carries a [bot]
# suffix, but the text is all this needs. One trigger and not a slash
# command, so nothing collides with the other bots on these repos.
TRIGGER_RE='(^|[[:space:]])@seabbs-review-bot(\[bot\])?([[:space:],.!]|$)'
# The app's login as it appears in the reviews API.
BOT_LOGIN="${REVIEW_BOT_LOGIN:-seabbs-review-bot[bot]}"
SKIP_LABEL="no-review"

MODEL="${REVIEW_BOT_MODEL:-sonnet}"
MAX_PRS="${REVIEW_BOT_MAX_PRS:-3}"
# Seconds a new head commit must sit before review, so a run mid-push
# does not review half a branch.
SETTLE="${REVIEW_BOT_SETTLE:-180}"
# Changed lines above which a PR is logged and left for a human.
MAX_DIFF="${REVIEW_BOT_MAX_DIFF:-3000}"
TIMEOUT="${REVIEW_BOT_TIMEOUT:-900}"

STATE_DIR="$HOME/.local/share/review-bot"
# PRs opened before this stamp are never picked up automatically, so
# switching the bot on does not review everything already in flight.
SINCE_FILE="$STATE_DIR/since"
# Stamp of the last completed poll, anchoring how far back to look.
POLL_FILE="$STATE_DIR/last-poll"
LOG_FILE="$STATE_DIR/last-run.log"
HISTORY="$STATE_DIR/reviews.log"
CACHE_DIR="$HOME/.cache/review-bot"
REPO_CACHE="$CACHE_DIR/repos"
STANDARDS_DIR="$CACHE_DIR/standards"
SANDBOX_HOME="$CACHE_DIR/sandbox-home"
LOCK_FILE="$CACHE_DIR/lock"
mkdir -p "$STATE_DIR" "$REPO_CACHE" "$STANDARDS_DIR"

DRY_RUN=false
FORCE=false
LIST_ONLY=false
ONE_PR=""
SANDBOX=true
[ "${REVIEW_BOT_SANDBOX:-1}" = "0" ] && SANDBOX=false

while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY_RUN=true; shift ;;
    --force) FORCE=true; shift ;;
    --list) LIST_ONLY=true; shift ;;
    --no-sandbox) SANDBOX=false; shift ;;
    --pr) ONE_PR="$2"; shift 2 ;;
    -h|--help) sed -n '2,30p' "$0"; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 1 ;;
  esac
done

INTERACTIVE=false
[ -t 1 ] && INTERACTIVE=true

: > "$LOG_FILE"
log() {
  printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$LOG_FILE"
  $INTERACTIVE && echo "$*"
  return 0
}

# ---------------------------------------------------------------- gates

# One run at a time. A review can take minutes; overlapping runs would
# double-post.
exec 9>"$LOCK_FILE"
if ! flock -n 9; then
  log "another run holds the lock, exiting"
  exit 0
fi

if [ -x "$BUDGET_SH" ] && ! "$BUDGET_SH" >/dev/null 2>&1; then
  log "compute budget red, skipping this run"
  exit 0
fi

for cmd in gh jq git claude; do
  command -v "$cmd" >/dev/null || { log "missing $cmd, exiting"; exit 1; }
done

# Only posting needs the app, so --list and --dry-run work before it exists.
if [ ! -f "$HOME/.config/review-bot/private-key.pem" ] \
  && [ -z "${REVIEW_BOT_KEY:-}" ] && ! $LIST_ONLY && ! $DRY_RUN; then
  log "no app key configured, see review-bot-token.sh header"
  exit 1
fi

iso_to_epoch() {
  date -d "$1" +%s 2>/dev/null || date -j -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s \
    2>/dev/null || echo 0
}

# Has the app already reviewed this PR, and when did it last do so?
# GitHub is the source of truth rather than a local file, so losing state
# cannot cause a duplicate review.
last_bot_review() {
  gh api "repos/$1/pulls/$2/reviews" --paginate \
    --jq "[.[] | select(.user.login == \"$BOT_LOGIN\")] | last
           | .submitted_at // empty" 2>/dev/null
}

# A human asking again: a mention by TRIGGER_USER newer than the
# app's last review. Comments by seabbs-bot are ignored on purpose.
retrigger_after() {
  local repo="$1" pr="$2" since="$3"
  gh api "repos/$repo/issues/$pr/comments" --paginate \
    --jq ".[] | select(.user.login == \"$TRIGGER_USER\")
          | select(.created_at > \"$since\") | .body" 2>/dev/null \
    | grep -Eq "$TRIGGER_RE"
}

# Decide whether this PR wants a review now. Echoes the reason, or nothing.
wants_review() {
  local repo="$1" pr="$2" meta="$3"
  local state author draft labels sha last

  state="$(jq -r '.state' <<< "$meta")"
  author="$(jq -r '.author.login' <<< "$meta")"
  draft="$(jq -r '.isDraft // false' <<< "$meta")"
  labels="$(jq -r '[.labels[].name] | join(",")' <<< "$meta")"
  sha="$(jq -r '.headRefOid' <<< "$meta")"

  [ "$state" = "OPEN" ] || { log "  skip $repo#$pr: $state"; return 1; }
  [ "$(jq -r '.mergedAt // "null"' <<< "$meta")" = "null" ] \
    || { log "  skip $repo#$pr: merged"; return 1; }
  case ",$labels," in
    *",$SKIP_LABEL,"*) log "  skip $repo#$pr: $SKIP_LABEL label"; return 1 ;;
  esac
  $FORCE && { echo "forced"; return 0; }

  last="$(last_bot_review "$repo" "$pr")"

  # An explicit ask beats every gate below, on any PR in the watched
  # owners: someone else's work, a draft, or one from years ago. Asking
  # is the point, and only seabbs can ask.
  if retrigger_after "$repo" "$pr" "${last:-1970-01-01T00:00:00Z}"; then
    echo "requested by $TRIGGER_USER"
    return 0
  fi

  if [ -n "$last" ]; then
    log "  skip $repo#$pr: reviewed at $last, not asked again since"
    return 1
  fi

  # Nobody asked, so the automatic path applies and it is limited to my
  # own work.
  case " $AUTHORS " in
    *" author:$author "*) ;;
    *) log "  skip $repo#$pr: author $author not watched"; return 1 ;;
  esac

  # A draft is work in progress. It still gets a review the moment it is
  # marked ready, and a mention works on it before then.
  if [ "$draft" = "true" ]; then
    log "  skip $repo#$pr: draft"
    return 1
  fi

  # The backlog of PRs that were already open when the bot was switched on
  # is left alone. Otherwise the first run would review dozens at once.
  local created
  created="$(jq -r '.createdAt' <<< "$meta")"
  if [[ "$created" < "$SINCE" ]]; then
    log "  skip $repo#$pr: opened $created, before the bot was enabled"
    return 1
  fi

  local committed age
  committed="$(gh api "repos/$repo/commits/$sha" \
    --jq '.commit.committer.date' 2>/dev/null)"
  age=$(( $(date +%s) - $(iso_to_epoch "${committed:-1970-01-01T00:00:00Z}") ))
  if [ "$age" -lt "$SETTLE" ]; then
    log "  skip $repo#$pr: head is ${age}s old, letting it settle"
    return 1
  fi
  echo "first pass"
}

# ------------------------------------------------------------- standards

# The org standards a package is actually held to live in two places, not
# in this script: EpiAwarePackageTools for Julia, the epinowcast style
# guide for R. Cache them so the reviewer reads the current version rather
# than a copy that drifts, and refresh at most daily.
STANDARDS=(
  "julia-standards.md|EpiAware/EpiAwarePackageTools.jl|docs/src/standards.md"
  "julia-contributing.md|EpiAware/.github|CONTRIBUTING.md"
  "r-style-guide.md|epinowcast/.github|STYLE_GUIDE.md"
  "r-contributing.md|epinowcast/.github|CONTRIBUTING.md"
)

sync_standards() {
  local entry name repo path dest
  for entry in "${STANDARDS[@]}"; do
    IFS='|' read -r name repo path <<< "$entry"
    dest="$STANDARDS_DIR/$name"
    if [ -f "$dest" ] && [ -z "$(find "$dest" -mtime +1 2>/dev/null)" ]; then
      continue
    fi
    if gh api "repos/$repo/contents/$path" --jq '.content' 2>/dev/null \
      | base64 -d > "$dest.tmp" && [ -s "$dest.tmp" ]; then
      mv "$dest.tmp" "$dest"
      log "  refreshed standards: $name"
    else
      rm -f "$dest.tmp"
      [ -f "$dest" ] || log "  could not fetch $repo/$path"
    fi
  done
}

detect_language() {
  local dir="$1"
  if [ -f "$dir/Project.toml" ]; then echo julia
  elif [ -f "$dir/DESCRIPTION" ]; then echo r
  else echo other
  fi
}

standards_block() {
  local lang="$1"
  case "$lang" in
    julia)
      cat <<STD

This is a Julia package in the EpiAware ecosystem. Hold it to the org
standards, not to generic Julia taste. Read these first:
  $STANDARDS_DIR/julia-standards.md
    the standards EpiAwarePackageTools enforces and suggests, which every
    package in the org adopts through template sync
  $STANDARDS_DIR/julia-contributing.md
and any AGENTS.md, CLAUDE.md or CONTRIBUTING.md in the checkout.

Runic formatting, Aqua, ExplicitImports, JET, docstring format and
doctests all run in CI, so do not report what those already catch. Review
what they cannot see: whether the change follows the ecosystem's
composition and type conventions, whether public API additions are
documented and tested as the standards require, whether test items are
placed and scoped the way the test infrastructure expects, and whether
anything breaks AD safety.
STD
      ;;
    r)
      cat <<STD

This is an R package. Hold it to the project's own standards, not to
generic R taste. Read these first:
  $STANDARDS_DIR/r-style-guide.md
  $STANDARDS_DIR/r-contributing.md
and any CONTRIBUTING.md, CLAUDE.md or AGENTS.md in the checkout, which
override the org defaults where they differ.

lintr and styler run in CI, so do not report what they already catch.
Review what they cannot see: whether exported functions have complete
roxygen documentation with working examples, whether input validation and
error messages follow the project's conventions, whether NEWS.md records
a user-facing change, and whether the tests exercise the behaviour the PR
claims to change.
STD
      ;;
  esac
}

# ------------------------------------------------------------- reviewing

# What CI already knows about this head. Read with the normal gh token, so
# the app itself never needs checks access. Told to the reviewer so it does
# not spend its findings on things a check has already reported.
ci_summary() {
  local repo="$1" sha="$2" runs failed pending total
  runs="$(gh api "repos/$repo/commits/$sha/check-runs" --paginate \
    --jq '.check_runs[] | "\(.conclusion // .status)\t\(.name)"' \
    2>/dev/null)"
  if [ -z "$runs" ]; then
    echo "CI has not reported on this head yet."
    return
  fi
  total="$(wc -l <<< "$runs" | tr -d ' ')"
  failed="$(grep -E '^(failure|timed_out|cancelled)' <<< "$runs" \
    | cut -f2 | paste -sd ', ' -)"
  pending="$(grep -cE '^(queued|in_progress)' <<< "$runs")"
  if [ -n "$failed" ]; then
    echo "CI on this head: $total checks, failing: $failed. A failing check
is evidence of a real defect, so read what it covers, but do not repeat
its output as a finding."
  elif [ "$pending" -gt 0 ]; then
    echo "CI on this head: $total checks, $pending still running, none
failing so far."
  else
    echo "CI on this head is green across $total checks, so do not report
anything a check would already have caught."
  fi
}

# A clone under ~/.cache, never the working copy in ~/code, so a review can
# never disturb what is checked out there.
prepare_checkout() {
  local repo="$1" pr="$2" sha="$3" dir="$REPO_CACHE/$repo"
  if [ ! -d "$dir/.git" ]; then
    gh repo clone "$repo" "$dir" -- --filter=blob:none --quiet \
      >/dev/null 2>&1 || return 1
  fi
  git -C "$dir" fetch --quiet --force origin \
    "+refs/pull/$pr/head:refs/review-bot/pr-$pr" >/dev/null 2>&1 || return 1
  git -C "$dir" fetch --quiet origin >/dev/null 2>&1
  git -C "$dir" checkout --quiet --force --detach "$sha" >/dev/null 2>&1 \
    || return 1
  echo "$dir"
}

build_prompt() {
  local repo="$1" pr="$2" author="$3" base="$4" range="$5" title="$6"
  local standards="$7" ci="$8"
  cat <<PROMPT
You are seabbs-review-bot, an independent first-pass reviewer on $repo
pull request #$pr, "$title", opened by $author. Assume it was written by
an AI agent. Review the code that is there, not the story the description
tells about it.

The PR head is checked out here. Read the change first:
  git diff --stat $range
  git diff $range
Then read the surrounding code with Read and Grep before judging
anything. A line that looks wrong in a diff is often fine in context, and
a line that looks fine is often wrong in context. Before calling anything
duplicated or reinvented, grep for the thing you think already exists and
name it. A finding you cannot point at is not a finding.
$standards
$ci
Machine-written code has a house style, and catching it is the main job
here. Look hard for:
- Documentation longer than the thing it documents. A docstring that
  restates the signature in prose, lists the obvious, or explains what
  the reader can see. Say what to cut.
- Comments that narrate development rather than explain code. Anything
  saying "previously", "now uses", "changed to", "as requested", "note
  that we refactored", or referring to this PR, an issue number, or an
  earlier attempt. Code is read by people who never saw the history.
- Comments restating the line below them.
- Logic copied rather than reused, in this package or across the
  ecosystem. Name the existing function it should call.
- A hand-rolled version of something the ecosystem already provides.
- Abstraction, options, or defensive branches nobody asked for, added
  for a case that does not exist in the codebase.
- Tests that assert the implementation rather than the behaviour, or
  that would still pass with the function body removed.

Alongside that, report:
1. Correctness bugs. Wrong logic, off-by-one, unhandled empty / NA /
   NULL input, an unintended behaviour change, broken boundary cases.
2. A behaviour the PR claims to change that no test covers.
3. Documentation, argument names or types that contradict the code.
4. A departure from the project standards above that CI does not catch.

Do not report formatting, line length, naming taste, anything a linter
catches, speculative future problems, or praise. Do not restate what the
diff does as if it were a finding. If the change is sound, say so and
return no comments.

Every comment says what to change, not just what is wrong. Where the fix
is a few lines, give them.

Each inline comment must name a file and a line that appears in the diff
above as an added or context line. If a point does not attach to such a
line, put it in the summary instead.

Reply with JSON and nothing else. No prose around it, no code fences:
{"summary": "...",
 "comments": [{"path": "R/file.R", "line": 42,
               "severity": "suggestion", "body": "..."}]}
summary: two or three sentences, what the change does and your verdict.
severity: default to "suggestion". Use "issue" only for a bug you can
demonstrate or a breach of an explicit project standard. Use "note" for
a genuine question. Most findings are suggestions.
comments: at most eight, most important first, [] if none.
UK English, short direct sentences, no adjectives you do not need.
PROMPT
}

# The reviewer reads agent-written code and its output is posted publicly,
# so text in a PR that talks the model into quoting a file would publish
# it. Tool limits alone are not enough, because Read reaches the whole
# filesystem. bwrap fixes that structurally: a tmpfs over $HOME hides
# ~/.ssh, ~/.config/gh, ~/code and the rest, and only the checkout and the
# standards are bound back in. The sandbox home holds a copy of the Claude
# credential and nothing else.
prepare_sandbox() {
  local creds="$HOME/.claude/.credentials.json"
  mkdir -p "$SANDBOX_HOME/.claude"
  chmod 700 "$SANDBOX_HOME" "$SANDBOX_HOME/.claude"
  # Refreshed every run: the OAuth token rotates.
  [ -f "$creds" ] && install -m 600 "$creds" "$SANDBOX_HOME/.claude/"
  return 0
}

sandbox_prefix() {
  $SANDBOX || return 0
  command -v bwrap >/dev/null || return 0
  printf '%s\0' bwrap \
    --ro-bind / / --dev-bind /dev /dev --proc /proc --tmpfs /tmp \
    --bind "$SANDBOX_HOME" "$HOME" \
    --bind "$1" "$1" \
    --ro-bind "$STANDARDS_DIR" "$STANDARDS_DIR" \
    --unshare-pid --unshare-ipc --unshare-uts --die-with-parent \
    --chdir "$1" --
}

run_review() {
  local dir="$1" prompt="$2" out
  local -a wrap=()
  if $SANDBOX; then
    if command -v bwrap >/dev/null; then
      prepare_sandbox
      mapfile -d '' -t wrap < <(sandbox_prefix "$dir")
    else
      log "  bwrap missing, running unsandboxed"
    fi
  fi
  # --safe-mode: no CLAUDE.md, skills, plugins, hooks or MCP servers. The
  # prompt is self-contained and a reviewer wants none of that machinery.
  out="$(cd "$dir" && timeout "$TIMEOUT" "${wrap[@]}" claude -p "$prompt" \
    --model "$MODEL" \
    --safe-mode \
    --output-format json \
    --add-dir "$STANDARDS_DIR" \
    --allowedTools "Read" "Grep" "Glob" "Bash(git diff:*)" \
      "Bash(git log:*)" "Bash(git show:*)" "Bash(git status:*)" \
    --disallowedTools "Write" "Edit" "WebFetch" "WebSearch" "Bash(gh:*)" \
    2>"$STATE_DIR/last-claude-stderr.log")" || return 1
  printf '%s' "$out" > "$STATE_DIR/last-claude-raw.json"
  # Unwrap the CLI envelope, then pull the JSON object out of whatever
  # wrapping the model added around it.
  jq -r '.result // empty' <<< "$out" \
    | sed -n '/^[[:space:]]*{/,$p' \
    | sed -e 's/^```json//' -e 's/^```//' -e 's/```[[:space:]]*$//' \
    | jq -c 'select(type == "object")' 2>/dev/null
}

# Nothing the model returns is posted unchecked. Comments must attach to a
# file the PR actually touches, lengths are capped, and a review carrying
# anything shaped like a credential is dropped rather than published.
SECRET_RE='BEGIN [A-Z ]*PRIVATE KEY|gh[pousr]_[A-Za-z0-9]{16,}'
SECRET_RE="$SECRET_RE"'|github_pat_[A-Za-z0-9_]{20,}|sk-ant-|AKIA[0-9A-Z]{16}'

sanitise_review() {
  local repo="$1" pr="$2" review="$3" files clean

  if grep -qE "$SECRET_RE" <<< "$review"; then
    log "  dropped review on $repo#$pr: output matched a credential shape"
    return 1
  fi

  files="$(gh api "repos/$repo/pulls/$pr/files" --paginate \
    --jq '.[].filename' 2>/dev/null | jq -R . | jq -sc .)"
  [ -n "$files" ] || files='[]'

  # A comment on a file outside the diff cannot be posted inline, so move
  # it into the summary instead of losing it.
  clean="$(jq -c --argjson files "$files" '
    (.comments // []) as $all
    | ($all | map(select(.path as $p | $files | index($p)))) as $keep
    | ($all | map(select(.path as $p | ($files | index($p)) | not))) as $moved
    | {
        summary: ((.summary // "" | .[0:4000])
          + (if ($moved | length) > 0 then
               "\n\nPoints that do not attach to a changed line:\n"
               + ($moved | map("- `" + .path + "` — " + .body) | join("\n"))
             else "" end)),
        comments: ($keep[0:8] | map({
          path, line,
          severity: (.severity // "suggestion"),
          body: (.body | .[0:2000])
        }))
      }' <<< "$review" 2>/dev/null)"

  [ -n "$clean" ] || { log "  unusable review shape on $repo#$pr"; return 1; }
  echo "$clean"
}

post_review() {
  local repo="$1" pr="$2" sha="$3" review="$4" reason="$5"
  local token payload body http

  body="$(jq -r '.summary' <<< "$review")"
  body="$body

<sub>Automated first pass by seabbs-review-bot (Claude $MODEL), triggered \
by: $reason. Not a human review. @seabbs can comment \
\`@seabbs-review-bot\` to re-run it, or add the \`$SKIP_LABEL\` label to \
opt this PR out. Ping @seabbs with any questions.</sub>"

  payload="$(jq -n --arg body "$body" --arg sha "$sha" \
    --argjson review "$review" '{
      commit_id: $sha,
      body: $body,
      event: "COMMENT",
      comments: [$review.comments[]? | {
        path: .path,
        line: .line,
        side: "RIGHT",
        body: ((if .severity == "issue" then "**issue** "
                elif .severity == "suggestion" then "**suggestion** "
                else "**note** " end) + .body)
      }]
    }')"

  if $DRY_RUN; then
    jq . <<< "$payload" > "$STATE_DIR/last-review.json"
    log "  dry run, review written to $STATE_DIR/last-review.json"
    $INTERACTIVE && jq . <<< "$payload"
    return 0
  fi

  # Re-check state at the last moment: the PR may have merged or closed
  # while the review was running.
  local now_state
  now_state="$(gh pr view "$pr" -R "$repo" --json state,mergedAt \
    --jq '.state + "/" + (.mergedAt // "null")' 2>/dev/null)"
  case "$now_state" in
    OPEN/null) ;;
    *) log "  abandoned $repo#$pr: now $now_state"; return 1 ;;
  esac

  token="$("$TOKEN_SH" "$repo")" || { log "  no token for $repo"; return 1; }

  http="$(GH_TOKEN="$token" gh api -X POST \
    "repos/$repo/pulls/$pr/reviews" --input - <<< "$payload" 2>&1)" \
    && { log "  posted review on $repo#$pr"; return 0; }

  # Inline comments 422 when a line is not in the diff. Rather than lose
  # the review, fold the comments into the body and post that.
  log "  inline post failed, retrying as a plain review"
  payload="$(jq -n --arg sha "$sha" --argjson p "$payload" '{
    commit_id: $sha,
    event: "COMMENT",
    body: ($p.body + "\n\n" + ([$p.comments[]?
      | "- `\(.path):\(.line)` — \(.body)"] | join("\n")))
  }')"
  if GH_TOKEN="$token" gh api -X POST "repos/$repo/pulls/$pr/reviews" \
    --input - <<< "$payload" >/dev/null 2>&1; then
    log "  posted plain review on $repo#$pr"
    return 0
  fi
  log "  post failed on $repo#$pr: $http"
  return 1
}

review_pr() {
  local repo="$1" pr="$2" reason="$3" meta="$4"
  local sha base author title dir range review count

  sha="$(jq -r '.headRefOid' <<< "$meta")"
  base="$(jq -r '.baseRefName' <<< "$meta")"
  author="$(jq -r '.author.login' <<< "$meta")"
  title="$(jq -r '.title' <<< "$meta")"
  count=$(( $(jq -r '.additions' <<< "$meta")
            + $(jq -r '.deletions' <<< "$meta") ))

  if [ "$count" -gt "$MAX_DIFF" ]; then
    log "  skip $repo#$pr: $count changed lines over the $MAX_DIFF cap"
    return 1
  fi

  log "  reviewing $repo#$pr ($reason, $count lines) $title"
  dir="$(prepare_checkout "$repo" "$pr" "$sha")" \
    || { log "  could not check out $repo#$pr"; return 1; }

  local mb lang
  mb="$(git -C "$dir" merge-base "origin/$base" "$sha" 2>/dev/null)"
  range="${mb:-origin/$base}..$sha"
  lang="$(detect_language "$dir")"
  log "  language: $lang"

  review="$(run_review "$dir" \
    "$(build_prompt "$repo" "$pr" "$author" "$base" "$range" "$title" \
      "$(standards_block "$lang")" "$(ci_summary "$repo" "$sha")")")"
  if [ -z "$review" ]; then
    log "  no usable review returned for $repo#$pr"
    return 1
  fi

  review="$(sanitise_review "$repo" "$pr" "$review")" || return 1
  post_review "$repo" "$pr" "$sha" "$review" "$reason" || return 1
  printf '%s\t%s#%s\t%s\t%s\t%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    "$repo" "$pr" "$sha" "$reason" \
    "$(jq -r '.comments | length' <<< "$review")" >> "$HISTORY"
}

# ------------------------------------------------------------------ main

META_FIELDS='state,mergedAt,isDraft,labels,headRefOid,baseRefName'
META_FIELDS="$META_FIELDS,author,title,additions,deletions,url,createdAt"

# The search API, not `gh search prs`, because repeated author: and org:
# qualifiers OR correctly here and the gh wrapper drops them.
#
# Both queries filter server side. That matters at a five minute cadence:
# a poll with nothing to do costs two API calls, not one per open PR.
search_prs() {
  gh api -X GET search/issues -f per_page=100 -f q="$1" \
    --jq '.items[] | "\(.repository_url | sub(".*/repos/"; "")) \(.number)"' \
    2>/dev/null
}

candidates() {
  if [ -n "$ONE_PR" ]; then
    echo "${ONE_PR/\#/ }"
    return
  fi
  {
    # Opened since the bot was switched on, ready for review.
    search_prs "is:open is:pr draft:false -label:$SKIP_LABEL \
$AUTHORS $OWNERS created:>=$SINCE"
    # Asked for by hand: any PR in these owners, any age, drafts and
    # other people's work included. The window is anchored on the last
    # completed poll, so a day with the machine off does not lose a
    # request. Searching on the commenter alone rather than on the trigger
    # text keeps this honest: GitHub's text matching is loose enough that
    # a phrase query both misses and over-matches. It costs nothing to
    # widen, since seabbs comments on a handful of PRs a week and
    # retrigger_after makes the real decision.
    search_prs "is:open is:pr $OWNERS \
commenter:$TRIGGER_USER updated:>=$WINDOW"
  } | sort -u
}

log "review-bot starting"

if [ ! -f "$SINCE_FILE" ]; then
  date -u +%Y-%m-%dT%H:%M:%SZ > "$SINCE_FILE"
  log "first run: only PRs opened after $(cat "$SINCE_FILE") are picked up"
fi
SINCE="$(cat "$SINCE_FILE")"

# How far back to look for a request. An hour before the last
# completed poll, so a missed or crashed run loses nothing, or a week on
# a first run.
if [ -f "$POLL_FILE" ]; then
  WINDOW="$(date -u -d "$(cat "$POLL_FILE") -1 hour" +%Y-%m-%dT%H:%M:%SZ \
    2>/dev/null)"
fi
: "${WINDOW:=$(date -u -d '7 days ago' +%Y-%m-%dT%H:%M:%SZ 2>/dev/null)}"
: "${WINDOW:=$SINCE}"

$LIST_ONLY || sync_standards
reviewed=0
while read -r repo pr; do
  [ -n "${repo:-}" ] || continue
  meta="$(gh pr view "$pr" -R "$repo" --json "$META_FIELDS" 2>/dev/null)"
  [ -n "$meta" ] || { log "  skip $repo#$pr: could not read PR"; continue; }

  reason="$(wants_review "$repo" "$pr" "$meta")" || continue
  if $LIST_ONLY; then
    log "  would review $repo#$pr ($reason)"
    continue
  fi

  review_pr "$repo" "$pr" "$reason" "$meta" && reviewed=$(( reviewed + 1 ))
  [ "$reviewed" -ge "$MAX_PRS" ] && { log "hit the $MAX_PRS per-run cap"
    break; }
done < <(candidates)

# Only a poll that ran to completion moves the window forward.
[ -z "$ONE_PR" ] && ! $LIST_ONLY && ! $DRY_RUN \
  && date -u +%Y-%m-%dT%H:%M:%SZ > "$POLL_FILE"

log "review-bot done, $reviewed reviewed"
