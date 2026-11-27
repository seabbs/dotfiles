#!/usr/bin/env bash
# triage.sh — one popup for what actually needs you.
#
# The inbox tells you what happened. This tells you what to do about it,
# and lets you do it: Enter opens a PR straight into octo's review mode,
# so reading and answering are the same keystroke.
#
# Two ways to hand a row off rather than do it yourself: C-a opens a
# Claude session on it (prsesh for a PR, agent for a repo), and C-b asks
# seabbs-bot to take it, by commenting on the thread the way you would by
# hand. The bot's scan only claims a comment that starts a line with its
# name and was written by you, so this is that comment and nothing special.
#
#   prefix + i         the popup (tmux)
#   triage.sh          the same list, printed
#   triage.sh --list   rows only, for the popup to reload
#
# The sorting is deliberately mechanical and fast. Who caused a thing,
# whether it is labelled, whether it is yours, whether CI shouted: none of
# that needs judgement, and a popup that takes ten seconds to think is a
# popup you stop opening. gh-notify.sh --tsv makes the one judgement call
# that is not mechanical, which is whether a muted actor is asking you
# something, and this reuses that rather than guessing again.
#
# Reads as seabbs. Notifications belong to an account, and seabbs-bot is
# usually the active gh login here.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
NOTIFY="$HERE/gh-notify.sh"
OCTO="$HERE/octo-review.sh"
TUICR="$HERE/tuicr-review.sh"
CODE_DIR="${CODE_DIR:-$HOME/code}"
OWNER="${TRIAGE_OWNER:-seabbs}"
BOT="${TRIAGE_BOT:-seabbs-bot}"

GH_TOKEN="$(gh auth token --user "$OWNER" 2>/dev/null)"
[ -n "$GH_TOKEN" ] || {
  echo "no token for $OWNER; run: gh auth login" >&2
  exit 1
}
export GH_TOKEN

# A row is what you see, then the fields an action needs. fzf is told to
# display only the first, so the rest ride along invisibly.
row() { printf '%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "$4" "${5:-}"; }

search() {
  gh api -X GET search/issues -f q="$1 archived:false" -f per_page=50 \
    --jq '.items[] | [(.repository_url | sub("^.*/repos/"; "")),
                      .number, (.title | .[0:52]),
                      (if .pull_request then "pr" else "issue" end),
                      .user.login] | @tsv' 2>/dev/null
}

# A dependency bump is a review request in name only. They are the bulk of
# what review-requested returns and they drown everything a person asked
# for, so they get their own heading rather than a place in the queue.
# seabbs-bot is not on this list: its PRs are the work, not the noise.
is_bump_author() {
  case "$1" in
    dependabot*|renovate*|github-actions*|*-bot\[bot\]) return 0 ;;
  esac
  return 1
}

line_for() {
  # Truncating as well as padding: a long repo name would otherwise shove
  # every title out of its column and the list stops scanning as a table.
  printf '%-4s %-13.13s %-28.28s %.52s' "$1" "$2" "$3" "$4"
}

list_rows() {
  local notify kind who reason repo number title thread author seen=""
  local bumps=""

  notify="$($NOTIFY --tsv 2>/dev/null)"

  # 1. Someone is asking you something. The one thing here that is never
  #    noise, so it leads.
  while IFS=$'\t' read -r kind who reason repo number title thread; do
    [ "$kind" = "ask" ] || continue
    row "$(line_for ASK "$who" "$repo" "$title")" \
      pr "$repo" "$number" "$thread"
    seen="$seen $repo#$number"
  done <<< "$notify"

  # 2. Your review was actually requested, which the inbox buries among
  #    everything else tagged review_requested by a bot.
  while IFS=$'\t' read -r repo number title type author; do
    [ -n "$repo" ] || continue
    case " $seen " in *" $repo#$number "*) continue ;; esac
    seen="$seen $repo#$number"
    if is_bump_author "$author"; then
      bumps="$bumps$(row "$(line_for BUMP "$author" "$repo" "$title")" \
        "$type" "$repo" "$number" "")"$'\n'
      continue
    fi
    row "$(line_for REV "$author" "$repo" "$title")" \
      "$type" "$repo" "$number" ""
  done < <(search "is:open is:pr review-requested:@me")

  # 3. CI shouted. Taken from the notification feed rather than asked for
  #    per PR: the answer is already in the inbox, and a check call per
  #    open PR would cost more than everything else here put together.
  while IFS=$'\t' read -r kind who reason repo number title thread; do
    [ "$reason" = "ci_activity" ] || continue
    case " $seen " in *" $repo#$number "*) continue ;; esac
    row "$(line_for CI "$who" "$repo" "$title")" \
      pr "$repo" "$number" "$thread"
    seen="$seen $repo#$number"
  done <<< "$notify"

  # 4. Yours and the bot's, open and not otherwise listed. Not work, but
  #    the thing you forget: a PR of your own sitting unmerged.
  echo -e "───  your open PRs\t\t\t\t"
  while IFS=$'\t' read -r repo number title type author; do
    [ -n "$repo" ] || continue
    case " $seen " in *" $repo#$number "*) continue ;; esac
    row "$(line_for PR "$author" "$repo" "$title")" \
      "$type" "$repo" "$number" ""
  done < <(search "is:open is:pr author:$OWNER author:$BOT")

  if [ -n "$bumps" ]; then
    echo -e "───  dependency bumps\t\t\t\t"
    printf '%s' "$bumps"
  fi
}

repo_path() {
  local p="$CODE_DIR/$1"
  [ -d "$p/.git" ] && printf '%s' "$p"
}

open_item() {
  local type="$1" repo="$2" number="$3" path
  [ -n "$repo" ] && [ -n "$number" ] || return 0
  path="$(repo_path "$repo")"
  if [ "$type" = "issue" ]; then
    # octo-review.sh is PR-only, so an issue opens its own buffer.
    local target="${path:-$CODE_DIR/$repo}"
    [ -d "$target/.git" ] || target="$HOME"
    if [ -n "${TMUX:-}" ]; then
      tmux new-window -c "$target" -n "issue-$number" \
        "nvim -c 'Octo issue edit $number'"
    else
      (cd "$target" && exec nvim -c "Octo issue edit $number")
    fi
    return 0
  fi
  exec "$OCTO" "$repo" "$number" "$path" review
}

# Hand the thread to seabbs-bot. Nothing clever: the comment is posted as
# you, and the bot's scan picks it up on its next run because it starts a
# line with the bot's name. Public repos mean a public comment, so it says
# what it will post before posting it.
delegate() {
  local repo="$1" number="$2" what="$3"
  [ -n "$repo" ] && [ -n "$number" ] || return 0
  if [ -z "$what" ]; then
    echo "nothing asked, so nothing posted" >&2
    return 1
  fi
  gh issue comment "$number" -R "$repo" \
    --body "@$BOT $what" >/dev/null 2>&1 \
    && echo "asked $BOT on $repo#$number: $what" \
    || echo "could not comment on $repo#$number" >&2
}

# Open a Claude session on it. prsesh for a PR, since it checks the branch
# out and lays the window out; agent for anything else, which lands in the
# repo itself.
dispatch_agent() {
  local type="$1" repo="$2" number="$3"
  [ -n "$repo" ] || return 0
  if [ "$type" = "pr" ] && [ -n "$number" ]; then
    exec zsh -ic "prsesh $repo $number"
  fi
  exec zsh -ic "agent ${repo##*/}"
}

case "${1:-}" in
  --list) list_rows; exit 0 ;;
  --dismiss)
    # Mark the notification read. Only rows that came from the inbox carry
    # a thread, so this quietly does nothing for the rest.
    [ -n "${2:-}" ] && gh api -X PATCH "notifications/threads/$2" \
      >/dev/null 2>&1
    exit 0 ;;
  --open) shift; open_item "$@"; exit 0 ;;
  --help|-h)
    awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
esac

rows="$(list_rows)"
if [ -z "$(printf '%s' "$rows" | tr -d '[:space:]')" ]; then
  echo "nothing waiting on you"
  exit 0
fi

# Outside tmux there is nothing to pop up into, so just print it.
if [ -z "${TMUX:-}" ] && [ -z "${TRIAGE_FORCE_FZF:-}" ]; then
  cut -d$'\t' -f1 <<< "$rows"
  exit 0
fi

sel="$(fzf --ansi --no-sort --delimiter='\t' --with-nth=1 \
  --border-label ' needs you ' --prompt '  ' \
  --header \
    'Enter=octo  C-t=tuicr  C-a=agent  C-b=ask bot  C-d=dismiss  C-r=reload' \
  --bind "ctrl-d:execute-silent($0 --dismiss {5})+reload($0 --list)" \
  --bind "ctrl-r:reload($0 --list)" \
  --expect=ctrl-t,ctrl-a,ctrl-b <<< "$rows")"

key="$(sed -n '1p' <<< "$sel")"
line="$(sed -n '2p' <<< "$sel")"
[ -n "$line" ] || exit 0

IFS=$'\t' read -r _ type repo number _ <<< "$line"
[ -n "$repo" ] || exit 0

case "$key" in
  ctrl-t) exec "$TUICR" "$repo" "$number" "$(repo_path "$repo")" ;;
  ctrl-a) dispatch_agent "$type" "$repo" "$number" ;;
  ctrl-b)
    # Asked outside the popup, which has closed by now, so the prompt is
    # visible and editable rather than squeezed into a picker.
    printf 'ask %s to do what on %s#%s?\n> ' "$BOT" "$repo" "$number"
    IFS= read -r what
    delegate "$repo" "$number" "$what"
    ;;
  *) open_item "$type" "$repo" "$number" ;;
esac
