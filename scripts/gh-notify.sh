#!/usr/bin/env bash
# gh-notify.sh — the GitHub inbox with your own bots' noise taken out,
# except where a bot is actually asking you something.
#
# gh dash cannot do this. Its notification filters are client-side and
# only understand is:, reason: and repo:, so there is no way to say "not
# this author" there. The filtering has to happen here instead.
#
#   gh-notify.sh           the inbox: muted actors dropped, asks kept
#   gh-notify.sh --asks    only the questions a muted actor is asking you
#   gh-notify.sh --muted   only what was dropped, so nothing is lost
#   gh-notify.sh --read    mark the dropped ones read, never an ask
#
# Muting is by whoever caused the notification, not by reason. The bot's
# work arrives as reason:mention -- it @s you in its own PRs -- so a rule
# that spared mentions would spare exactly the noise it is meant to drop.
#
# A muted actor asking a question is not noise, so it survives the mute
# and is marked ASK. A question is the needs-seabbs label the worker adds
# when it is stuck, or a comment that addresses you by name and asks
# something. The label is the reliable half; the text test is there for
# anything written before the convention existed.
#
# Reads as seabbs, not seabbs-bot: notifications belong to an account, and
# the bot is usually the active gh login on this machine.

set -uo pipefail

MUTE="${GH_NOTIFY_MUTE:-seabbs-bot}"
OWNER="${GH_NOTIFY_OWNER:-seabbs}"
ASK_LABEL="${GH_NOTIFY_ASK_LABEL:-needs-seabbs}"

mode=list
case "${1:-}" in
  --asks)  mode=asks ;;
  --muted) mode=muted ;;
  --read)  mode=read ;;
  --help|-h)
    # The header block, however long it grows: comment lines after the
    # shebang, stopping at the first line that is not one.
    awk 'NR > 1 { if (!/^#/) exit; sub(/^# ?/, ""); print }' "$0"
    exit 0 ;;
  "") ;;
  *) echo "unknown option: $1" >&2; exit 2 ;;
esac

GH_TOKEN="$(gh auth token --user "$OWNER" 2>/dev/null)"
[ -n "$GH_TOKEN" ] || {
  echo "no token for $OWNER; run: gh auth login" >&2
  exit 1
}
export GH_TOKEN

# Who caused it, and what they said, in one call. latest_comment_url is
# the comment that triggered the notification; for a thread with nothing
# on it yet it is null and the subject itself is what happened. Newlines
# are flattened so the body survives as one TSV field.
actor_and_body() {
  local url="$1"
  [ -n "$url" ] && [ "$url" != "null" ] || { printf 'unknown\t'; return; }
  gh api "$url" --jq '[(.user.login // "unknown"),
      ((.body // "") | gsub("[\n\r\t]"; " "))] | @tsv' 2>/dev/null \
    || printf 'unknown\t'
}

muted_actor() {
  local who="$1" m
  for m in $MUTE; do [ "$who" = "$m" ] && return 0; done
  return 1
}

# Addressed to you by name and asking something. The -bot guard matters:
# every one of the bot's own comments contains its own @name.
asks_owner() {
  local body="$1"
  grep -qE "@$OWNER([^-A-Za-z0-9]|\$)" <<< "$body" || return 1
  grep -q '?' <<< "$body"
}

labelled_ask() {
  gh api "$1" --jq "[.labels[].name] | index(\"$ASK_LABEL\") != null" \
    2>/dev/null | grep -q true
}

kept=0; hidden=0; marked=0; asks=0
while IFS=$'\t' read -r id reason repo title url suburl; do
  [ -n "$id" ] || continue
  IFS=$'\t' read -r who body < <(actor_and_body "$url")

  is_ask=false
  if muted_actor "$who"; then
    if asks_owner "${body:-}" || labelled_ask "$suburl"; then
      is_ask=true
    fi
  fi

  if muted_actor "$who" && ! $is_ask; then
    hidden=$((hidden + 1))
    case "$mode" in
      muted) printf '  %-16s %-34s %s\n' "$reason" "$repo" "$title" ;;
      read)
        if gh api -X PATCH "notifications/threads/$id" >/dev/null 2>&1; then
          marked=$((marked + 1))
          printf '  read  %-30s %s\n' "$repo" "$title"
        else
          printf '  FAILED %-29s %s\n' "$repo" "$title"
        fi ;;
    esac
    continue
  fi

  $is_ask && asks=$((asks + 1))
  kept=$((kept + 1))
  case "$mode" in
    list) if $is_ask; then
            printf '  ASK %-12s %-34s %s\n' "$who" "$repo" "$title"
          else
            printf '  %-16s %-34s %s\n' "$reason" "$repo" "$title"
          fi ;;
    asks) $is_ask && \
            printf '  %-14s %-34s %s\n' "$who" "$repo" "$title" ;;
  esac
done < <(gh api "notifications?per_page=100" --paginate \
  --jq '.[] | [.id, .reason, .repository.full_name,
               (.subject.title[0:46]),
               (.subject.latest_comment_url // .subject.url // ""),
               (.subject.url // "")] | @tsv' 2>/dev/null)

case "$mode" in
  list)  printf '\n%d shown (%d of them asks), %d muted (%s).\n' \
           "$kept" "$asks" "$hidden" "$MUTE" ;;
  asks)  printf '\n%d asking you.\n' "$asks" ;;
  muted) printf '\n%d muted (%s), %d left alone.\n' \
           "$hidden" "$MUTE" "$kept" ;;
  read)  printf '\n%d marked read, %d left alone (asks are never read).\n' \
           "$marked" "$kept" ;;
esac
