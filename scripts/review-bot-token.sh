#!/bin/bash
# review-bot-token.sh — mint a GitHub App installation token for one repo.
#
# The review bot posts as a GitHub App rather than as seabbs-bot because
# GitHub refuses APPROVE / REQUEST_CHANGES from the PR author, so a
# seabbs-bot review of a seabbs-bot PR can only ever be a COMMENTED note,
# and reads as the author talking to itself. A separate app identity is an
# independent reviewer in the UI, needs no seat or collaborator invite, and
# holds a one-hour scoped token instead of a long-lived PAT on disk.
#
# One-off setup (browser, ~2 minutes):
#   1. https://github.com/settings/apps/new
#      - name: seabbs-review-bot
#      - homepage: https://github.com/seabbs
#      - Webhook: uncheck "Active", and subscribe to no events. Events
#        would need a public URL and a server to receive them. review-bot.sh
#        polls instead, so the app is an identity and nothing else.
#      - Repository permissions:
#          Metadata:      Read-only   (mandatory)
#          Contents:      Read-only   (so the app can read a repo on its own)
#          Pull requests: Read & write (submitting the review)
#          Checks:        Read-only   (CI state on the head commit)
#        Nothing else. No write access to code, issues, actions or workflows.
#      - "Any account": required, not optional. The app is owned by the
#        seabbs user, and "Only on this account" would then confine it to
#        seabbs' own repos, leaving out epinowcast, epiforecasts and
#        EpiAware. A stranger installing it grants us write on their pull
#        requests, which we never use: the app has no webhook and no server,
#        so it acts only when this poller mints a token, and the poller only
#        looks at the owners listed in review-bot.sh.
#   2. Generate a private key, then:
#        mkdir -p ~/.config/review-bot && chmod 700 ~/.config/review-bot
#        mv ~/Downloads/seabbs-review-bot.*.private-key.pem \
#           ~/.config/review-bot/private-key.pem
#        chmod 600 ~/.config/review-bot/private-key.pem
#        echo <APP_ID> > ~/.config/review-bot/app-id
#   3. Install the app on seabbs, epinowcast, epiforecasts and EpiAware.
#
# Usage:
#   review-bot-token.sh owner/repo     print an installation token
#   review-bot-token.sh --check        verify config and app identity
#
# Tokens are cached under ~/.cache/review-bot/tokens until five minutes
# before they expire, so a poller run that touches several PRs in one repo
# mints once.

set -uo pipefail

CONFIG_DIR="${REVIEW_BOT_CONFIG:-$HOME/.config/review-bot}"
APP_ID_FILE="$CONFIG_DIR/app-id"
KEY_FILE="${REVIEW_BOT_KEY:-$CONFIG_DIR/private-key.pem}"
CACHE_DIR="$HOME/.cache/review-bot/tokens"

die() { echo "review-bot-token: $*" >&2; exit 1; }

b64url() { openssl base64 -A | tr '+/' '-_' | tr -d '='; }

app_id() {
  if [ -n "${REVIEW_BOT_APP_ID:-}" ]; then
    echo "$REVIEW_BOT_APP_ID"
  elif [ -f "$APP_ID_FILE" ]; then
    tr -d '[:space:]' < "$APP_ID_FILE"
  else
    die "no app id: set REVIEW_BOT_APP_ID or write $APP_ID_FILE"
  fi
}

# A GitHub App JWT: RS256 over {header}.{payload}, valid ten minutes.
# iat is backdated 60s because GitHub rejects tokens issued in its future.
make_jwt() {
  local id iat exp header payload signing_input sig
  id="$(app_id)" || exit 1
  [ -f "$KEY_FILE" ] || die "no private key at $KEY_FILE"
  iat=$(( $(date +%s) - 60 ))
  exp=$(( iat + 600 ))
  header='{"alg":"RS256","typ":"JWT"}'
  payload="{\"iat\":$iat,\"exp\":$exp,\"iss\":\"$id\"}"
  signing_input="$(printf '%s' "$header" | b64url).$(
    printf '%s' "$payload" | b64url)"
  sig="$(printf '%s' "$signing_input" \
    | openssl dgst -sha256 -sign "$KEY_FILE" -binary | b64url)" \
    || die "could not sign JWT with $KEY_FILE"
  printf '%s.%s' "$signing_input" "$sig"
}

api() {
  local method="$1" path="$2" auth="$3" data="${4:-}"
  local args=(-sS -X "$method"
    -H "Authorization: Bearer $auth"
    -H "Accept: application/vnd.github+json"
    -H "X-GitHub-Api-Version: 2022-11-28")
  [ -n "$data" ] && args+=(-d "$data")
  curl "${args[@]}" "https://api.github.com$path"
}

if [ "${1:-}" = "--check" ]; then
  jwt="$(make_jwt)" || exit 1
  out="$(api GET /app "$jwt")"
  slug="$(printf '%s' "$out" | jq -r '.slug // empty')"
  [ -n "$slug" ] || die "app lookup failed: $(printf '%s' "$out" \
    | jq -r '.message // .')"
  echo "app: $slug (id $(printf '%s' "$out" | jq -r .id))"
  echo "permissions: $(printf '%s' "$out" | jq -c .permissions)"
  api GET /app/installations "$jwt" \
    | jq -r '.[] | "installed on: \(.account.login) (\(.target_type))"'
  exit 0
fi

REPO="${1:-}"
[ -n "$REPO" ] || die "usage: review-bot-token.sh owner/repo | --check"
OWNER="${REPO%%/*}"
NAME="${REPO##*/}"
# Exactly one slash, both halves non-empty. Comparing the two halves would
# reject epinowcast/epinowcast, where the repo is named after its owner.
case "$REPO" in
  */*/*|/*|*/) die "expected owner/repo, got '$REPO'" ;;
  */*) ;;
  *) die "expected owner/repo, got '$REPO'" ;;
esac

mkdir -p "$CACHE_DIR"
chmod 700 "$HOME/.cache/review-bot" "$CACHE_DIR" 2>/dev/null
CACHE_FILE="$CACHE_DIR/${OWNER}__${NAME}.json"

if [ -f "$CACHE_FILE" ]; then
  expiry="$(jq -r '.expires_at // empty' < "$CACHE_FILE")"
  if [ -n "$expiry" ]; then
    expiry_s="$(date -d "$expiry" +%s 2>/dev/null \
      || date -j -f '%Y-%m-%dT%H:%M:%SZ' "$expiry" +%s 2>/dev/null)"
    if [ -n "$expiry_s" ] && [ "$expiry_s" -gt $(( $(date +%s) + 300 )) ]; then
      jq -r .token < "$CACHE_FILE"
      exit 0
    fi
  fi
fi

jwt="$(make_jwt)" || exit 1

install_json="$(api GET "/repos/$OWNER/$NAME/installation" "$jwt")"
install_id="$(printf '%s' "$install_json" | jq -r '.id // empty')"
[ -n "$install_id" ] || die "app not installed on $REPO ($(
  printf '%s' "$install_json" | jq -r '.message // .'))"

token_json="$(api POST "/app/installations/$install_id/access_tokens" "$jwt" \
  "{\"repositories\":[\"$NAME\"]}")"
token="$(printf '%s' "$token_json" | jq -r '.token // empty')"
[ -n "$token" ] || die "token request failed: $(printf '%s' "$token_json" \
  | jq -r '.message // .')"

umask 077
printf '%s' "$token_json" > "$CACHE_FILE"
echo "$token"
