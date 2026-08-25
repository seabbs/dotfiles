#!/usr/bin/env bash
# tmux session switcher / project launcher
# Needs bash 4+ (declare -A); macOS /bin/bash is 3.2, so resolve via env to pick
# up a modern bash (e.g. Homebrew's) from PATH.
# Uses fzf to pick from active sessions + project dirs,
# then switches or creates via tmuxinator.
#
# Two-step flow:
#   1. Pick a session or project
#   2. If session has multiple windows, pick a window
#      or create a new feature branch
#
# Keybindings in session picker:
#   Ctrl-a  show all (sessions + projects + extras)
#   Ctrl-s  show active sessions only
#   Ctrl-p  show projects only
#   Ctrl-w  show worktrees across all repos
#   Ctrl-e  show extra roots only (home, notes, …)
#   Ctrl-d  kill selected session
#   Enter   switch to / create session
#           (unmatched query → session at $HOME)

CODE_DIR="${CODE_DIR:-$HOME/code}"

# Extra roots outside $CODE_DIR. Each entry is `name → path`;
# `name` becomes the tmux session name when picked.
declare -A EXTRA_ROOTS=(
  [home]="$HOME"
  [notes]="$HOME/Library/CloudStorage/GoogleDrive-s.e.abbott12@gmail.com/My Drive/cloud/apps/obsidian/notes"
)

# Remote hub hosts to span (space-separated ssh aliases), overridable via env.
HUB_HOSTS="${HUB_HOSTS:-archie}"
# This script's path on a hub, for routing kill/create actions there over ssh.
RS='~/code/seabbs/dotfiles/scripts/sessionizer.sh'
# Host scope for cross-machine listing: all | home | <hub host>. Cycled with
# C-r in the picker, reset to "all" on each launch.
HOST_STATE="$HOME/.cache/sessionizer-host"
mkdir -p "$HOME/.cache" 2>/dev/null
dbg() { [ -n "${SESSIONIZER_DEBUG:-}" ] && \
  echo "$(date '+%T') $*" >> /tmp/sessionizer-debug.log; }
# Always-on failure logger for the cross-host path: append to a persistent log
# and, inside tmux, surface the message so the popup never closes with no
# feedback (the silent-close class of bug). $*=message.
slog() {
  echo "$(date '+%F %T') $*" >> "$CACHE_DIR/errors.log" 2>/dev/null
  [ -n "${TMUX:-}" ] && \
    tmux display-message -d 4000 "sessionizer: $*" 2>/dev/null
  return 0
}
host_scope() { cat "$HOST_STATE" 2>/dev/null || echo all; }
SELF_HOST="$(hostname -s)"
self_host() { printf '%s' "$SELF_HOST"; }
# Hub hosts other than the current machine.
remote_hubs() {
  local h
  for h in $HUB_HOSTS; do [[ "$h" != "$(self_host)" ]] && echo "$h"; done
}
# Label for the current machine's own sessions: "home" on the mac, otherwise
# the hub's own name (so on archie its sessions read [archie], not [home]).
local_label() {
  local l="home" h
  for h in $HUB_HOSTS; do [[ "$h" == "$(self_host)" ]] && l="$h"; done
  echo "$l"
}

# Print the cached output of a remote tmux command instantly (last-known), and
# refresh the cache in the background so it is current next time. Turns the
# blocking ssh into a non-blocking cache lookup. $1=host $2=key $3=tmux command.
CACHE_DIR="$HOME/.cache/sessionizer"
mkdir -p "$CACHE_DIR" 2>/dev/null
remote_cached() {
  local host="$1" key="$2" cmd="$3"
  local cache="$CACHE_DIR/$host-$key" lock
  [ -f "$cache" ] && cat "$cache"
  lock="$cache.lock"
  # Steal a stale lock: a refresh killed mid-flight (popup closed, SIGKILL)
  # leaves the lock dir behind, blocking every later refresh forever. Expire
  # any lock older than 30s so the cache self-heals (cross-platform stat).
  if [ -d "$lock" ]; then
    local lmt
    lmt=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)
    [ "$(( $(date +%s) - lmt ))" -ge 30 ] && rmdir "$lock" 2>/dev/null
  fi
  if mkdir "$lock" 2>/dev/null; then
    # Bound the refresh: a degraded link must not hang holding the lock and
    # block every later refresh. ServerAlive kills a dead connection quickly.
    # Force bash for $cmd regardless of the hub's login shell: these commands
    # are bash syntax, but ssh runs them under the remote user's own shell
    # (zsh on archie), and zsh silently breaks a `cmd | while read` pipe
    # nested inside a `for` loop after its first iteration — no error, just
    # every repo after the first vanishing from worktree/session listings.
    # %q round-trips $cmd as a single safely-quoted argument to `bash -c`.
    # -s "$cache.tmp": an overloaded hub can return a zero-exit but EMPTY
    # result (the remote tmux call itself stalls/returns nothing under load,
    # while ssh still succeeds) -- without this guard that empty result wins
    # the mv and clobbers a previously-good cache, hiding every hub session
    # until the next refresh happens to land clean.
    ( ssh -o ConnectTimeout=8 -o ServerAliveInterval=5 -o ServerAliveCountMax=2 \
        "$host" "bash -c $(printf '%q' "$cmd")" >"$cache.tmp" 2>/dev/null \
        && [ -s "$cache.tmp" ] && mv "$cache.tmp" "$cache"
      rm -f "$cache.tmp"; rmdir "$lock" ) >/dev/null 2>&1 &
  fi
}

# Active sessions merged across home + hub hosts, most-recently-active first
# and deduped by name (the host is shown when picking a window in step 2).
# Respects the current host scope.
list_sessions() {
  local scope llbl h; scope="$(host_scope)"; llbl="$(local_label)"
  local fmt='#{session_activity}|#{session_name}|#{@hub}'
  {
    # Local block first (current machine ranks first), each block by last
    # activity; dedup keeps the local copy; @hub gateway sessions excluded.
    # Local is fresh; remote comes from a cache refreshed in the background, so
    # the finder never blocks on ssh.
    [[ "$scope" == "all" || "$scope" == "$llbl" || "$scope" == "home" ]] && \
      tmux list-sessions -F "$fmt" 2>/dev/null \
        | awk -F'|' '$3!="1"' | sort -rn -t'|' -k1
    for h in $(remote_hubs); do
      [[ "$scope" == "all" || "$scope" == "$h" ]] && \
        remote_cached "$h" "sessions" "tmux list-sessions -F '$fmt'" \
          | awk -F'|' '$3!="1"' | sort -rn -t'|' -k1
    done
  } | awk -F'|' 'NF && $2 && !seen[$2]++ {
        # Org sessions are stored as org-<name> (to avoid colliding with a repo
        # session of the same name) but display as "[org] <name>" — the same
        # label and selection handler as the C-o org view, so the internal
        # prefix never leaks into the picker.
        if ($2 ~ /^org-/) print "[org] " substr($2, 5)
        else print "[active] " $2
      }'
}

# Local repo dirs as "org/repo", most-recently-modified first.
list_projects_local() {
  local dirs=() org_dir org proj_dir proj
  for org_dir in "$CODE_DIR"/*/; do
    org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    for proj_dir in "$org_dir"*/; do
      [[ -d "$proj_dir" ]] || continue
      proj=$(basename "$proj_dir")
      [[ "$proj" == "worktrees" || "$proj" == worktree-* || "$proj" == .* ]] \
        && continue
      dirs+=("$proj_dir")
    done
  done
  [[ ${#dirs[@]} -gt 0 ]] || return 0
  # Order by last modified (most-recent first); ls -t works on mac and linux.
  ls -dt "${dirs[@]}" 2>/dev/null | sed "s|^$CODE_DIR/||; s|/\$||"
}

# The same "org/repo" list on a hub, via a plain inline ssh command (NOT the
# hub's copy of this script) so it works whatever script version is deployed
# there. Mirrors list_projects_local's exclusions (archive/worktrees/hidden).
REMOTE_PROJECTS_CMD="cd ~/code 2>/dev/null && ls -dt */*/ 2>/dev/null | sed 's:/*\$::' | grep -vE '^archive/|/worktrees\$|/worktree-|/\.'"

# Projects merged across home + hub hosts (deduped, local first), scope-aware.
# A repo living on only one host still appears; selecting it routes to whichever
# host actually has it (see the project handler). Remote comes from a
# background-refreshed cache so the finder never blocks on ssh.
list_projects() {
  local scope llbl h; scope="$(host_scope)"; llbl="$(local_label)"
  {
    [[ "$scope" == "all" || "$scope" == "$llbl" || "$scope" == "home" ]] && \
      list_projects_local
    for h in $(remote_hubs); do
      [[ "$scope" == "all" || "$scope" == "$h" ]] && \
        remote_cached "$h" "projects" "$REMOTE_PROJECTS_CMD"
    done
  } | awk 'NF && !seen[$0]++'
}

list_worktrees_local() {
  local org_dir org proj_dir proj
  for org_dir in "$CODE_DIR"/*/; do
    org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    for proj_dir in "$org_dir"/*/; do
      [[ ! -d "$proj_dir" ]] && continue
      proj=$(basename "$proj_dir")
      [[ "$proj" == "worktrees" ]] && continue
      [[ "$proj" == worktree-* ]] && continue
      [[ "$proj" == .* ]] && continue
      [[ ! -d "${proj_dir%/}/worktrees" ]] && continue
      # Use git's authoritative worktree list and label each by its path under
      # worktrees/, so slashed branch names (feat/x, fix/y) survive intact
      # rather than being truncated to their first path segment by a one-level
      # glob. The base is taken from git's own first (main) worktree line so it
      # is byte-identical to the linked-worktree paths it is matched against
      # (the shell-built path can carry a stray // from the loop globs).
      git -C "$proj_dir" worktree list --porcelain 2>/dev/null \
        | awk -v label="$org/$proj" '
            /^worktree / {
              path = substr($0, 10)
              if (NR == 1) { base = path "/worktrees/"; next }
              if (index(path, base) == 1)
                print label " :: " substr(path, length(base) + 1)
            }'
    done
  done
}

# The same "org/repo :: branch" list on a hub, via a plain inline ssh command
# (version-independent). Pure shell so slashed branch names survive intact.
REMOTE_WORKTREES_CMD='cd ~/code 2>/dev/null || exit; for p in */*/; do case "$p" in archive/*|*/worktrees/|*/worktree-*/) continue;; esac; [ -d "${p}worktrees" ] || continue; repo="${p%/}"; git -C "$p" worktree list 2>/dev/null | while read -r path _; do case "$path" in */worktrees/*) echo "$repo :: ${path#*/worktrees/}";; esac; done; done'

# Worktrees merged across home + hub hosts (deduped, local first), scope-aware.
# A worktree on only one host still appears; selecting it routes to that host.
list_worktrees() {
  local scope llbl h; scope="$(host_scope)"; llbl="$(local_label)"
  {
    [[ "$scope" == "all" || "$scope" == "$llbl" || "$scope" == "home" ]] && \
      list_worktrees_local
    for h in $(remote_hubs); do
      [[ "$scope" == "all" || "$scope" == "$h" ]] && \
        remote_cached "$h" "worktrees" "$REMOTE_WORKTREES_CMD"
    done
  } | awk 'NF && !seen[$0]++'
}

# Org-level roots: top-level $CODE_DIR dirs that carry a CLAUDE.md (the marker
# for "an org folder with repos"). Excludes archive and loose project dirs.
# Picking one opens a session rooted at the org dir, where the org-wide CLAUDE.md
# and the /org-* skills have the right context to work across all its repos.
# Emitted as a bare name so the project-selection handler picks it up directly.
list_orgs() {
  local org_dir org
  for org_dir in "$CODE_DIR"/*/; do
    org=$(basename "$org_dir")
    [[ "$org" == "archive" ]] && continue
    [[ -f "$org_dir/CLAUDE.md" ]] && echo "[org] $org"
  done | sort
}

list_extras() {
  for name in "${!EXTRA_ROOTS[@]}"; do
    [[ -d "${EXTRA_ROOTS[$name]}" ]] && echo "[dir] $name"
  done | sort
}

list_all() {
  list_sessions
  echo "────────────"
  list_extras
  list_projects
}

list_windows() {
  local session="$1" scope h llbl; scope="$(host_scope)"; llbl="$(local_label)"
  local fmt='#{window_activity} #{window_index}:#{window_name}'
  # Collect local + remote (cached, so instant) windows tagged with their host,
  # then sort all of them together by last activity so home and archie windows
  # interleave by recency rather than grouping home-then-archie. The activity
  # timestamp leads each line for the sort and is stripped afterwards.
  {
    [[ "$scope" == "all" || "$scope" == "$llbl" || "$scope" == "home" ]] && \
      tmux list-windows -t "=$session" -F "$fmt" 2>/dev/null \
        | sed "s/ / [$llbl] /"
    for h in $(remote_hubs); do
      [[ "$scope" == "all" || "$scope" == "$h" ]] && \
        remote_cached "$h" "windows-$session" \
          "tmux list-windows -t '=$session' -F '$fmt'" \
          | sed "s/ / [$h] /"
    done
  } | sort -rn -k1,1 | cut -d' ' -f2-
}

# Mark a local session as a dormant hub gateway: @hub for listing/exclusion,
# plus per-session options so the outer tmux passes everything through and
# hides its status bar whenever this session is viewed.
flag_hub() {
  # @hub marks it for listing/exclusion; status off hides the outer bar (the
  # inner remote tmux shows its own). Prefix stays active: a hub session is a
  # mac tmux session, so prefix+f / prefix+a here run the HOME finder. The
  # inner remote tmux is reached via the finder or send-prefix (double C-Space).
  tmux set-option -t "$1" @hub 1
  tmux set-option -t "$1" status off
}

# A hub gateway whose mosh pane has died — or one resurrect restored after a
# reboot (the session name comes back, but its mosh pane and @hub flag are
# runtime-only and do not) — still answers has-session, so callers would wrongly
# reuse a dead shell. A live gateway always carries @hub (set by flag_hub);
# anything named like a hub without it is a husk. Drop it so a fresh, live
# gateway is recreated on demand. $1 = hub host.
drop_dead_gateway() {
  tmux has-session -t "=$1" 2>/dev/null || return 0
  # Read @hub via an exact-name match in list-sessions: display-message -t
  # "=name" does not resolve a session-only target here (it falls back to
  # another session and reads an empty @hub, which would wrongly condemn a live
  # gateway). list-sessions -F is how the rest of this script reads @hub.
  local flag
  flag=$(tmux list-sessions -F '#{session_name}	#{@hub}' 2>/dev/null \
    | awk -F'\t' -v s="$1" '$1==s {print $2; exit}')
  if [ "$flag" = "1" ]; then
    # Flagged, but confirm the pane is still live: a mosh that exited leaves a
    # dead pane (a remain-on-exit husk) that answers has-session yet shows
    # nothing. Key on pane_dead, not the command name, so a still-connecting
    # gateway (zsh -> mosh bootstrap) is never mistaken for a husk and killed.
    local dead
    dead=$(tmux list-panes -t "=$1" -F '#{pane_dead}' 2>/dev/null | head -1)
    [ "$dead" != "1" ] && return 0
  fi
  tmux kill-session -t "=$1" 2>/dev/null
}

# Ensure a session exists on a hub host WITHOUT jumping into it: clone the repo
# on demand, then start the session detached if missing. Callers that want to
# then pick/create a window on the hub (the project path) use this and let
# pick_window do the routing. $1=hub $2=session $3=dir $4=repo (optional).
ensure_hub_session() {
  local hub="$1" sname="$2" dir="$3" repo="${4:-}" err
  dbg "ensure_hub_session hub=$hub sname=$sname dir=$dir repo=$repo"
  # Clone the repo on demand if it is not on the hub yet (gh credential helper
  # on the hub covers private repos). git clone creates missing parent dirs.
  if [[ -n "$repo" ]]; then
    err=$(ssh "$hub" \
      "[ -d $dir ] || git clone https://github.com/$repo.git $dir" 2>&1) \
      || slog "clone $repo on $hub failed: $err"
  fi
  # Start the session detached if missing, then confirm it actually exists —
  # tmuxinator errors were previously swallowed, so a failed start left every
  # later window/feature step targeting a session that was never created.
  if ! ssh "$hub" "tmux has-session -t '=$sname' 2>/dev/null"; then
    err=$(ssh "$hub" \
      "tmuxinator start project '$sname' '$dir' --no-attach" 2>&1)
    if ! ssh "$hub" "tmux has-session -t '=$sname' 2>/dev/null"; then
      slog "could not create session '$sname' on $hub: $err"
      return 1
    fi
  fi
  return 0
}

# Create a session on a hub host (if missing) and jump into its nested mosh
# session here. $1=hub  $2=session name  $3=working dir on the hub  $4=repo.
create_hub_session() {
  ensure_hub_session "$@" || return 1
  jump_to_hub_session "$1" "$2"
}

# Open a worktree window on a hub: ensure the repo session, then run `feat` in
# it (idempotent — reuses an existing worktree, so it just opens a window with
# the nvim/ai/repl layout), then jump in. $1=hub $2=session $3=org/repo $4=branch.
open_hub_worktree() {
  local hub="$1" session="$2" rel="$3" branch="$4"
  ensure_hub_session "$hub" "$session" "~/code/$rel" "$rel" || return 1
  ssh "$hub" \
    "tmux new-window -t '=$session' -n _launcher -c '~/code/$rel' \
       \"zsh -ic 'feat $branch; exit'\"" \
    2>/dev/null || slog "feat '$branch' on $hub:$session failed"
  rm -f "$CACHE_DIR/$hub-windows-$session" 2>/dev/null
  jump_to_hub_session "$hub" "$session"
}

# The hub host currently filtered to (empty unless C-r is on a specific hub).
hub_scope() {
  local scope; scope="$(host_scope)"; local h
  for h in $(remote_hubs); do [ "$scope" = "$h" ] && { echo "$h"; return; }; done
}

# Name of the hub host whose session cache currently lists a session named $1,
# or empty. Lets the picker route to a session that is live on a hub but not
# local (e.g. an org session started on archie) instead of shadowing it with a
# fresh empty local session of the same name.
hub_with_session() {
  local want="$1" h
  for h in $(remote_hubs); do
    [ -f "$CACHE_DIR/$h-sessions" ] || continue
    awk -F'|' -v s="$want" '$2==s{f=1} END{exit !f}' \
      "$CACHE_DIR/$h-sessions" && { printf '%s' "$h"; return; }
  done
}

# Name of the hub host whose cached project list contains "org/repo" $1, or
# empty. Lets a repo that exists only on a hub open on that hub without the user
# choosing a host (seamless cross-host open).
hub_with_project() {
  local want="$1" h
  for h in $(remote_hubs); do
    [ -f "$CACHE_DIR/$h-projects" ] || continue
    awk -v s="$want" '$0==s{f=1} END{exit !f}' \
      "$CACHE_DIR/$h-projects" && { printf '%s' "$h"; return; }
  done
}

# Map a (sanitised) session name back to an "org/repo" by scanning a hub's
# cached project list, so a session scoped to the hub in the window step can be
# created from its repo. Matches on the sanitised basename so dotted repos
# (e.g. CensoredDistributions.jl -> CensoredDistributions_jl) resolve.
# Case-insensitive: the same repo can be cloned with different casing on home
# vs a hub (e.g. Juliacon2026 vs JuliaCon2026), which otherwise silently
# breaks recreation ("no repo for session ... cannot create it"). Prints
# org/repo, or nothing. $1=hub $2=session.
hub_repo_for_session() {
  local hub="$1" want="$2" line base
  want="${want,,}"
  [ -f "$CACHE_DIR/$hub-projects" ] || return 0
  while IFS= read -r line; do
    base="${line##*/}"
    base="$(sanitize_session "$base")"
    [ "${base,,}" = "$want" ] && \
      { printf '%s' "$line"; return 0; }
  done < "$CACHE_DIR/$hub-projects"
}

# Map a GitHub owner to a local org dir name: an existing ~/code/<owner>
# (case-insensitive), else "external" (matching the ~/code/external convention
# for other people's repos). Home and hub mirror the same org layout.
org_dir_for() {
  local owner="$1" d name
  for d in "$CODE_DIR"/*/; do
    name=$(basename "$d")
    [[ "${name,,}" == "${owner,,}" ]] && { printf '%s' "$name"; return; }
  done
  printf 'external'
}

# tmux rewrites '.' and ':' in a session name to '_', so a dotted repo such as
# CensoredDistributions.jl or epiaware.github.io lives in a session with
# underscores. Derive that tmux-safe name up front so every -t '=name' target
# (local and over ssh) matches what tmux actually stored — otherwise the main
# session is created but window/feature targets miss and silently do nothing.
sanitize_session() { printf '%s' "$1" | sed 's/[^a-zA-Z0-9_-]/_/g'; }

# GitHub owners to pre-list (your own + orgs), overridable via env.
GH_OWNERS="${GH_OWNERS:-seabbs epinowcast epiforecasts EpiAware nfidd}"

# Your own + org repos as "[gh] owner/repo", printed instantly from cache and
# refreshed in the background (the gh API round-trips are slow). Mirrors the
# remote_cached pattern so C-g never blocks.
list_github() {
  local cache="$CACHE_DIR/github-repos" lock o
  [ -f "$cache" ] && cat "$cache"
  lock="$cache.lock"
  if [ -d "$lock" ]; then
    local lmt
    lmt=$(stat -f %m "$lock" 2>/dev/null || stat -c %Y "$lock" 2>/dev/null || echo 0)
    [ "$(( $(date +%s) - lmt ))" -ge 60 ] && rmdir "$lock" 2>/dev/null
  fi
  if mkdir "$lock" 2>/dev/null; then
    ( for o in $GH_OWNERS; do
        gh repo list "$o" --no-archived --limit 200 \
          --json nameWithOwner --jq '.[].nameWithOwner' 2>/dev/null
      done | sort -u | sed 's/^/[gh] /' >"$cache.tmp" \
        && mv "$cache.tmp" "$cache"
      rm -f "$cache.tmp"; rmdir "$lock" ) >/dev/null 2>&1 &
  fi
}

# Search all of GitHub for $1 (⌥g in the picker), as "[gh] owner/repo".
search_github() {
  local q="$1"
  [ -z "$q" ] && return 0
  gh search repos "$q" --limit 40 --json fullName --jq '.[].fullName' 2>/dev/null \
    | sed 's/^/[gh] /'
}

# Clone a GitHub "owner/repo" onto a chosen host (home or a hub) under
# ~/code/<owner-or-external>/<repo>, then open a session there. For a hub the
# clone happens on demand via create_hub_session (gh credential helper covers
# private repos). Invoked when a [gh] entry is picked.
clone_and_open() {
  local full="$1" owner repo dest_org rel host dest session
  owner="${full%%/*}"; repo="${full##*/}"
  dest_org="$(org_dir_for "$owner")"
  rel="$dest_org/$repo"
  session="$(sanitize_session "$repo")"

  host=$(printf 'home\n%s\n' "$(remote_hubs)" | sed '/^$/d' | fzf \
    --no-sort --border-label " clone $full " --prompt '  ' \
    --header 'Where should this repo live?')
  [ -z "$host" ] && return 0

  if [ "$host" = "home" ] || [ "$host" = "$(local_label)" ]; then
    dest="$CODE_DIR/$rel"
    if [ ! -d "$dest" ]; then
      mkdir -p "$CODE_DIR/$dest_org"
      tmux display-message "cloning $full …"
      git clone "https://github.com/$full.git" "$dest" 2>/dev/null \
        || { tmux display-message "clone failed: $full"; return 1; }
    fi
    tmux has-session -t "=$session" 2>/dev/null \
      || tmuxinator start project "$session" "$dest" --no-attach
    tmux switch-client -t "=$session"
    pick_window "$session"
  else
    echo "$host" > "$HOST_STATE"
    create_hub_session "$host" "$session" "~/code/$rel" "$full"
  fi
}

# Open PRs of a GitHub "owner/repo" for the picker: "#<n>  <title>  (author:head)".
list_prs() {
  gh pr list -R "$1" --limit 40 \
    --json number,title,headRefName,author \
    --jq '.[] | "#\(.number)  \(.title)  (\(.author.login):\(.headRefName))"' \
    2>/dev/null
}

# Check out PR #num of owner/repo as a worktree session on the LOCAL host,
# cloning the base repo under ~/code/<owner>/<repo> on demand. prsesh does the
# fork-aware checkout + window; it resolves the repo by the "owner/repo" arg, so
# PRs live under the owner dir (not external) to keep that resolution exact.
open_local_pr() {
  local full="$1" num="$2" owner repo dest session
  owner="${full%%/*}"; repo="${full##*/}"; dest="$CODE_DIR/$owner/$repo"
  if [ ! -d "$dest" ]; then
    mkdir -p "$CODE_DIR/$owner"
    tmux display-message "cloning $full …"
    git clone "https://github.com/$full.git" "$dest" 2>/dev/null \
      || { tmux display-message "clone failed: $full"; return 1; }
  fi
  session=$(printf '%s' "$repo" | sed 's/[^a-zA-Z0-9_-]/_/g')
  tmux has-session -t "=$session" 2>/dev/null \
    || tmuxinator start project "$session" "$dest" --no-attach
  tmux switch-client -t "=$session"
  # PRSESH_HOST=home: open_github_repo already asked which host to use, so the
  # prsesh in the launcher must not ask again.
  tmux new-window -t "=$session" -n _launcher -c "$dest" \
    "PRSESH_HOST=home zsh -ic 'prsesh $full $num; exit'"
}

# Same, on a hub: clone the base repo on demand, then run prsesh in a launcher
# window on the hub and jump into the repo session.
open_hub_pr() {
  local hub="$1" full="$2" num="$3" owner repo session
  owner="${full%%/*}"; repo="${full##*/}"
  session=$(printf '%s' "$repo" | sed 's/[^a-zA-Z0-9_-]/_/g')
  ensure_hub_session "$hub" "$session" "~/code/$owner/$repo" "$full" || return 1
  # PRSESH_HOST=home: the host is already decided by the time we get here, and
  # without it the prsesh on the hub would prompt for a host of its own.
  ssh "$hub" \
    "tmux new-window -t '=$session' -n _launcher -c '~/code/$owner/$repo' \
       \"PRSESH_HOST=home zsh -ic 'prsesh $full $num; exit'\"" \
    2>/dev/null || slog "prsesh $full #$num on $hub:$session failed"
  rm -f "$CACHE_DIR/$hub-windows-$session" 2>/dev/null
  jump_to_hub_session "$hub" "$session"
}

# Entry for a picked [gh] repo: choose "open repo" or "open a PR" (pick the PR,
# then the host), so a session can be made from a PR branch of a repo you do not
# have locally yet — cloned on demand on the chosen host.
open_github_repo() {
  local full="$1" action pr num host
  action=$(printf 'open repo\nopen a PR\n' | fzf --no-sort \
    --border-label " $full " --prompt '  ' --header 'What do you want?')
  [ -z "$action" ] && return 0
  if [ "$action" = "open repo" ]; then
    clone_and_open "$full"
    return 0
  fi
  pr=$(list_prs "$full" | fzf --no-sort --border-label " PRs · $full " \
    --prompt '  ' --header 'Pick a PR (Enter)')
  [ -z "$pr" ] && return 0
  num="${pr#\#}"; num="${num%% *}"
  host=$(printf 'home\n%s\n' "$(remote_hubs)" | sed '/^$/d' | fzf \
    --no-sort --border-label " PR #$num → where?" --prompt '  ' \
    --header 'Set up on which host?')
  [ -z "$host" ] && return 0
  if [ "$host" = "home" ] || [ "$host" = "$(local_label)" ]; then
    open_local_pr "$full" "$num"
  else
    open_hub_pr "$host" "$full" "$num"
  fi
}

# Kill a window on the local tmux, cleaning up its git worktree if it is one.
kill_window_local() {
  local session="$1" win_ref="$2" win_index win_name root
  win_index="${win_ref%%:*}"; win_name="${win_ref#*:}"
  root=$(tmux display-message -t "=$session:1" -p '#{pane_current_path}' \
    2>/dev/null)
  root=$(git -C "$root" worktree list 2>/dev/null | awk 'NR==1 {print $1}' \
    || echo "$root")
  if [[ -d "$root/worktrees/$win_name" ]]; then
    zsh -ic "cd $root && feat-done $win_name" 2>/dev/null
  else
    tmux kill-window -t "=$session:$win_index" 2>/dev/null
  fi
}

# Point a hub's live client at a session (and optional window). Targets the
# most-recently-active client explicitly: a roamed mosh connection can leave an
# idle orphan client on the hub, and an unqualified switch-client may then drive
# that stale client instead of the gateway in view, so the jump silently appears
# to do nothing. $1=hub  $2=session  $3=window index (optional).
hub_switch_client() {
  local hub="$1" session="$2" win="${3:-}" sel=""
  [ -n "$win" ] && sel=" \\; select-window -t '=$session:$win'"
  ssh "$hub" "c=\$(tmux list-clients -F '#{client_activity} #{client_name}' \
      2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-); \
    [ -n \"\$c\" ] || exit 0; \
    tmux switch-client -c \"\$c\" -t '=$session'$sel" \
    2>/dev/null || true
}

# Switch the active client into a hub's nested mosh session, creating the
# connection on demand (flagged @hub). $1=hub  $2=session name on the hub.
jump_to_hub_session() {
  local hub="$1" session="$2"
  drop_dead_gateway "$hub"
  if tmux has-session -t "=$hub" 2>/dev/null; then
    hub_switch_client "$hub" "$session"
  else
    tmux new-session -d -s "$hub" \
      "/bin/zsh -lc 'mosh --predict=experimental $hub -- tmux attach -t $session'"
    flag_hub "$hub"
  fi
  tmux switch-client -t "=$hub"
}

# Resolve a session's project root (main repo, not a worktree).
get_project_root() {
  local session="$1" root
  root=$(
    tmux display-message -t "=$session:1" \
      -p '#{pane_current_path}' 2>/dev/null
  )
  git -C "$root" worktree list 2>/dev/null \
    | awk 'NR==1 {print $1}' \
    || echo "$root"
}

# Resolve a query to a repo directory directly under an org dir. Tries an exact
# child first, then a unique case-insensitive prefix match. Prints the absolute
# repo path, or nothing if there is no unambiguous match.
resolve_org_repo() {
  local org_dir="$1" q="$2" d name match=""
  if [[ -d "$org_dir/$q" ]]; then echo "$org_dir/$q"; return 0; fi
  for d in "$org_dir"/*/; do
    [[ -d "$d" ]] || continue
    name=$(basename "$d")
    [[ "$name" == worktrees || "$name" == .* ]] && continue
    if [[ "${name,,}" == "${q,,}"* ]]; then
      [[ -n "$match" ]] && return 1   # ambiguous prefix
      match="${d%/}"
    fi
  done
  [[ -n "$match" ]] && echo "$match"
}

# Build the standard nvim / ai / repl layout as a new window named $2 in
# session $1, rooted at $3. Mirrors the worktree-selection layout below; the
# repl is auto-detected (Julia / R / shell).
build_dev_window() {
  local session="$1" name="$2" dir="$3" repl="zsh"
  if [[ -f "$dir/Project.toml" ]]; then
    repl="julia --project=."
  elif [[ -f "$dir/DESCRIPTION" ]]; then
    repl="R"
  fi
  tmux new-window -t "=$session" -n "$name" -c "$dir"
  tmux select-pane -T "nvim"
  tmux send-keys "nvim ." Enter
  tmux split-window -h -c "$dir"
  tmux select-pane -T "ai:$name"
  tmux send-keys "${AGENT_CLI_DEV_TOOL:-claude}" Enter
  tmux split-window -v -c "$dir"
  tmux select-pane -T "repl"
  tmux send-keys "$repl" Enter
  tmux select-pane -t 0
}

# Step 2 as a standalone unit: pick (or create) a window in $1, cross-host.
# Used by the inline project flow and by --switch-window (prefix s), which
# jumps straight here for the current session, skipping the project picker.
# Windows are listed by last activity (most-recent first) across all hosts.
pick_window() {
  local session="$1"
  local result query match host_tag win_index win_type hub root project_root
  [[ -z "$session" ]] && return 0

  result=$(list_windows "$session" | fzf \
    --no-sort \
    --border-label " $session " \
    --prompt '  ' \
    --header 'Enter=select  C-r host  C-d=kill  C-l=linked view  Type=new' \
    --print-query \
    --bind 'tab:down,btab:up' \
    --bind "ctrl-r:transform($0 --cycle-host \"--list-windows $session\")" \
    --bind "ctrl-d:execute-silent($0 --kill-window $session {1} {2})+reload($0 --list-windows $session)" \
    --bind "ctrl-l:execute-silent($0 --link-session $session)+abort" \
  )

  query=$(echo "$result" | sed -n '1p')
  match=$(echo "$result" | sed -n '2p')

  # Escape with no input
  [[ -z "$query" && -z "$match" ]] && return 0

  if [[ -n "$match" ]]; then
    # Matched an existing window: route by its host tag ([home]/[hub]).
    host_tag="${match%%] *}"; host_tag="${host_tag#[}"
    match="${match#\[*\] }"
    win_index="${match%%:*}"
    if [[ "$host_tag" == "$(local_label)" ]]; then
      tmux switch-client -t "=$session"
      tmux select-window -t "=$session:$win_index"
    else
      # Remote hub: switch to its nested mosh session here (created on demand,
      # flagged @hub for auto-passthrough). It lives inside this tmux.
      drop_dead_gateway "$host_tag"
      # A stale window cache can offer a window for a hub session that no longer
      # exists there (e.g. it was killed since the last refresh). Recreate it
      # from its repo so the switch lands on it, rather than silently leaving
      # the gateway on whatever session it was showing before.
      if ! ssh "$host_tag" "tmux has-session -t '=$session' 2>/dev/null"; then
        local rel; rel="$(hub_repo_for_session "$host_tag" "$session")"
        if [[ -z "$rel" ]]; then
          slog "session '$session' is gone from $host_tag"
          rm -f "$CACHE_DIR/$host_tag-windows-$session" 2>/dev/null
          return 0
        fi
        ensure_hub_session "$host_tag" "$session" "~/code/$rel" "$rel" \
          || return 0
      fi
      if tmux has-session -t "=$host_tag" 2>/dev/null; then
        # Existing connection: drive its live client to the chosen window.
        hub_switch_client "$host_tag" "$session" "$win_index"
      else
        # First time: pre-select the target window on the host, then attach that
        # session directly via mosh (bypassing the home auto-attach) so we land
        # on the exact window, not the host's home session.
        ssh "$host_tag" "tmux select-window -t '=$session:$win_index'" \
          2>/dev/null || true
        tmux new-session -d -s "$host_tag" \
          "/bin/zsh -lc 'mosh --predict=experimental $host_tag -- tmux attach -t $session'"
        flag_hub "$host_tag"
      fi
      tmux switch-client -t "=$host_tag"
    fi
  else
    # Detect an org session: root is a top-level $CODE_DIR dir with a CLAUDE.md.
    # get_project_root resolves worktree -> main repo and is empty for a
    # non-repo dir, so read the pane path directly here.
    local pane_path is_org=0
    pane_path=$(tmux display-message -t "=$session:1" \
      -p '#{pane_current_path}' 2>/dev/null)
    [[ "$(dirname "$pane_path")" == "${CODE_DIR%/}" \
       && -f "$pane_path/CLAUDE.md" ]] && is_org=1

    # No match: ask what kind of window to create. An org session has no single
    # repo, so offer "open repo" (drill into one of its repos) rather than
    # "feature branch".
    local menu
    if [[ $is_org -eq 1 ]]; then
      menu=$'open repo\nbare terminal'
    else
      menu=$'feature branch\nbare terminal'
    fi
    win_type=$(printf '%s' "$menu" \
      | fzf \
        --no-sort \
        --border-label " new: $query " \
        --prompt '  ' \
        --header 'What kind of window?' \
    )

    [[ -z "$win_type" ]] && return 0

    # If the picker is filtered to a hub, create the window/feature THERE (in the
    # hub's copy of the session) and jump into it, rather than locally.
    hub="$(hub_scope)"
    if [[ -n "$hub" ]]; then
      local rel
      # The picker can be scoped to the hub (C-r) without the project step
      # having created the session there, e.g. opening a repo that also exists
      # locally, then C-r to the hub to branch. Ensure the session exists first,
      # or the new-window below targets a missing session and silently no-ops
      # (the reported "prefix f closes and does nothing" on a fresh hub repo).
      if ! ssh "$hub" "tmux has-session -t '=$session' 2>/dev/null"; then
        rel="$(hub_repo_for_session "$hub" "$session")"
        if [[ -z "$rel" ]]; then
          slog "no repo for session '$session' on $hub, cannot create it"
          return 0
        fi
        ensure_hub_session "$hub" "$session" "~/code/$rel" "$rel" || return 0
      fi
      root=$(ssh "$hub" \
        "tmux display-message -t '=$session:1' -p '#{pane_current_path}'" \
        2>/dev/null)
      if [[ "$win_type" == "bare terminal" ]]; then
        ssh "$hub" "tmux new-window -t '=$session' -n '$query' -c '$root'" \
          2>/dev/null || slog "new window '$query' on $hub:$session failed"
      else
        ssh "$hub" \
          "tmux new-window -t '=$session' -n _launcher -c '$root' \
             \"zsh -ic 'feat $query; exit'\"" \
          2>/dev/null || slog "feat '$query' on $hub:$session failed"
      fi
      rm -f "$CACHE_DIR/$hub-windows-$session" 2>/dev/null
      jump_to_hub_session "$hub" "$session"
      return 0
    fi

    project_root=$(get_project_root "$session")
    tmux switch-client -t "=$session"

    if [[ "$win_type" == "open repo" ]]; then
      # Org session: open one of its repos (resolved from the typed query) as a
      # window with the standard dev layout, reusing an existing one if present.
      local repo_dir repo_name existing_repo_win
      repo_dir=$(resolve_org_repo "$pane_path" "$query")
      if [[ -z "$repo_dir" ]]; then
        tmux display-message \
          "no repo matching '$query' under $(basename "$pane_path")"
      else
        repo_name=$(basename "$repo_dir")
        existing_repo_win=$(
          tmux list-windows -t "=$session" \
            -F '#{window_index}:#{window_name}' 2>/dev/null \
            | while IFS= read -r line; do
                [[ "${line#*:}" == "$repo_name" ]] \
                  && echo "${line%%:*}" && break
              done
        )
        if [[ -n "$existing_repo_win" ]]; then
          tmux select-window -t "=$session:$existing_repo_win"
        else
          build_dev_window "$session" "$repo_name" "$repo_dir"
        fi
      fi
    elif [[ "$win_type" == "bare terminal" ]]; then
      # Org sessions are non-repos, so project_root is empty; fall back to the
      # org dir itself.
      [[ -z "$project_root" ]] && project_root="$pane_path"
      tmux new-window -t "=$session" -n "$query" \
        -c "$project_root"
    else
      # Run feat in a temporary window that sources the shell config, runs feat,
      # then closes itself. feat creates its own window with the full layout so
      # this runner window is just a launcher.
      tmux new-window -t "=$session" \
        -n "_launcher" -c "$project_root" \
        "zsh -ic 'feat $query; exit'"
    fi
  fi
}

# Handle flags for fzf reload
case "${1:-}" in
  --list-all)      list_all; exit 0 ;;
  --list-sessions) list_sessions; exit 0 ;;
  --list-projects)   list_projects; exit 0 ;;
  --list-worktrees)  list_worktrees; exit 0 ;;
  --list-orgs)       list_orgs; exit 0 ;;
  --list-github)     list_github; exit 0 ;;
  --search-github)   search_github "$2"; exit 0 ;;
  --list-extras)     list_extras; exit 0 ;;
  --drop-hub-gateways)
    # Called from tmux-resurrect's post-restore hook. A reboot makes continuum
    # restore every session, including hub gateways, which come back as dead
    # husks (mosh pane + @hub flag are runtime-only). Drop each so the finder
    # rebuilds a live mosh+@hub gateway on demand instead of surfacing a dead
    # "archie" that masks/misroutes the picker. No-op on a hub host (self is
    # excluded from remote_hubs, so it has no gateways of its own).
    for _h in $(remote_hubs); do drop_dead_gateway "$_h"; done
    exit 0
    ;;
  --cycle-host)
    cur="$(host_scope)"
    order=(all home $(remote_hubs))
    n=all
    for i in "${!order[@]}"; do
      [[ "${order[$i]}" == "$cur" ]] && \
        n="${order[$(( (i + 1) % ${#order[@]} ))]}" && break
    done
    echo "$n" > "$HOST_STATE"
    reload="${2:---list-all}"
    printf 'change-prompt(%s ❯ )+reload(%s %s)' "$n" "$0" "$reload"
    exit 0
    ;;
  --list-windows)    list_windows "$2"; exit 0 ;;
  --kill-session)
    # Kill on the local tmux and on every hub, refreshing each hub's session
    # cache so the killed session disappears from the picker immediately.
    tmux kill-session -t "=$2" 2>/dev/null
    for _h in $(remote_hubs); do
      ssh "$_h" "tmux kill-session -t '=$2'" 2>/dev/null
      ssh "$_h" "tmux list-sessions -F '#{session_activity}|#{session_name}|#{@hub}'" \
        >"$CACHE_DIR/$_h-sessions" 2>/dev/null
    done
    exit 0
    ;;
  --kill-window)
    # Route by the window's host tag: local kill, or kill on the hub (then
    # refresh that hub's window cache so the reload reflects it).
    session="$2"; tag="${3#[}"; tag="${tag%]}"; win_ref="$4"
    if [[ "$tag" == "$(local_label)" ]]; then
      kill_window_local "$session" "$win_ref"
    else
      ssh "$tag" "$RS --kill-window-local '$session' '$win_ref'" 2>/dev/null
      ssh "$tag" "tmux list-windows -t '=$session' -F '#{window_activity} #{window_index}:#{window_name}'" \
        >"$CACHE_DIR/$tag-windows-$session" 2>/dev/null
    fi
    exit 0
    ;;
  --kill-window-local) kill_window_local "$2" "$3"; exit 0 ;;
  --switch-popup)
    # Entry point for `prefix s`: invoked via run-shell so $2 is the correctly
    # expanded launching session. Open the switcher as a popup with it baked in
    # (a popup cannot resolve its own launching session reliably).
    exec tmux display-popup -E -w 60% -h 60% \
      "$0 --switch-window '${2}'"
    ;;
  --switch-window)
    # Window switcher for one session (cross-host), skipping the project picker.
    # Defaults to the current session when no name is passed.
    echo all > "$HOST_STATE"
    pick_window "${2:-$(tmux display-message -p '#{session_name}' 2>/dev/null)}"
    exit 0
    ;;
  --link-session)
    session="$2"
    # Create a grouped session with a unique name
    linked="${session}-$$"
    tmux new-session -d -t "=$session" -s "$linked"
    tmux switch-client -t "=$linked"
    exit 0
    ;;
  --open-hub-pr)
    # Entry point for prsesh once the user has picked a hub: set the PR up over
    # there and jump in. Lives here rather than in the shell function so the
    # hub plumbing (clone-on-demand, mosh gateway, client targeting) has one
    # implementation. $2=hub $3=org/repo $4=pr-number
    if [ -z "$2" ] || [ -z "$3" ] || [ -z "$4" ]; then
      echo "Usage: $0 --open-hub-pr <hub> <org/repo> <pr-number>" >&2
      exit 1
    fi
    open_hub_pr "$2" "$3" "$4"
    exit $?
    ;;
esac

# A fresh launch spans all hosts.
echo all > "$HOST_STATE"

# Step 1: pick a session or project
result=$(list_all | fzf \
  --no-sort \
  --border-label ' sessions ' \
  --prompt '  ' \
  --header \
    'C-a all  C-s sessions  C-r host  C-p projects  C-w worktrees  C-o orgs  C-g github(⌥g=all)  C-e extras  C-d kill' \
  --print-query \
  --bind 'tab:down,btab:up' \
  --bind "ctrl-a:change-prompt(  )+reload($0 --list-all)" \
  --bind "ctrl-s:change-prompt(  )+reload($0 --list-sessions)" \
  --bind "ctrl-r:transform($0 --cycle-host)" \
  --bind "ctrl-p:change-prompt(  )+reload($0 --list-projects)" \
  --bind "ctrl-w:change-prompt(  )+reload($0 --list-worktrees)" \
  --bind "ctrl-o:change-prompt(  )+reload($0 --list-orgs)" \
  --bind "ctrl-g:change-prompt(  )+reload($0 --list-github)" \
  --bind "alt-g:change-prompt(  )+reload($0 --search-github {q})" \
  --bind "ctrl-e:change-prompt(  )+reload($0 --list-extras)" \
  --bind "ctrl-d:execute-silent($0 --kill-session {2..})+reload($0 --list-all)" \
)
fzf_status=$?

# Cancelled with Esc / Ctrl-C
[[ $fzf_status -eq 130 ]] && exit 0

query=$(echo "$result" | sed -n '1p')
selected=$(echo "$result" | sed -n '2p')

# Nothing typed and nothing picked
[[ -z "$selected" && -z "$query" ]] && exit 0
[[ "$selected" == "────────────" ]] && exit 0

# GitHub repo picked (C-g / ⌥g view): open the repo, or set up a session from
# one of its PRs — on a chosen host, cloned on demand.
if [[ "$selected" == "[gh] "* ]]; then
  open_github_repo "${selected#\[gh\] }"
  exit 0
fi

# Unmatched query: ad-hoc session named after the query. If filtered to a hub,
# create it there; otherwise locally at $HOME.
if [[ -z "$selected" && -n "$query" ]]; then
  session=$(echo "$query" | tr -c 'A-Za-z0-9_-' '-' | sed 's/^-*//;s/-*$//')
  [[ -z "$session" ]] && exit 0
  hub="$(hub_scope)"
  dbg "unmatched query=$query session=$session scope=$(host_scope) hub=$hub"
  if [[ -n "$hub" ]]; then
    create_hub_session "$hub" "$session" '~'
    exit 0
  fi
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project "$session" "$HOME" --no-attach
  fi
  tmux switch-client -t "=$session"
  exit 0
fi

# Resolve session name
if [[ "$selected" == "[active] "* ]]; then
  session="${selected#\[active\] }"

elif [[ "$selected" == "[dir] "* ]]; then
  session="${selected#\[dir\] }"
  project_root="${EXTRA_ROOTS[$session]}"
  if [[ -z "$project_root" || ! -d "$project_root" ]]; then
    exit 0
  fi
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi

elif [[ "$selected" == "[org] "* ]]; then
  # Org-level session, rooted at the org dir. Named org-<name> so it never
  # collides with a repo session of the same name (e.g. epinowcast/epinowcast).
  org_name="${selected#\[org\] }"
  session="org-$org_name"
  project_root="$CODE_DIR/$org_name"

  # If the picker is scoped to a hub (C-r), open/switch the org session THERE,
  # mirroring how a project is created on the hub. Orgs are not a single repo,
  # so nothing is cloned — the org dir (with its org-wide CLAUDE.md) is assumed
  # to already exist on the hub.
  hub="$(hub_scope)"
  dbg "org selected=$selected session=$session scope=$(host_scope) hub=$hub"
  if [[ -n "$hub" ]]; then
    create_hub_session "$hub" "$session" "~/code/$org_name"
    exit 0
  fi

  # Otherwise, in "all" scope, prefer an already-live session over launching a
  # fresh local one: if it is live on a hub but not here, route to the hub. In
  # "home" scope this is skipped, so you can create a LOCAL org session even
  # when archie already has one of the same name (C-r home to force local).
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    if [[ "$(host_scope)" == "all" ]]; then
      hub="$(hub_with_session "$session")"
      if [[ -n "$hub" ]]; then
        jump_to_hub_session "$hub" "$session"
        exit 0
      fi
    fi
    [[ -d "$project_root" ]] || exit 0
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi

elif [[ "$selected" == *" :: "* ]]; then
  # Worktree selection: org/repo :: branch
  local_project="${selected%% :: *}"
  branch="${selected##* :: }"
  project="${local_project##*/}"
  project_root="$CODE_DIR/$local_project"
  worktree_path="$project_root/worktrees/$branch"
  # Sanitise to match how tmux stores the session name (it rewrites '.' and ':'
  # to '_'); targeting the raw dotted repo name (e.g. CensoredDistributions.jl)
  # fails because tmux reads the '.' as a window/pane separator.
  session=$(echo "$project" | sed 's/[^a-zA-Z0-9_-]/_/g')

  # Cross-host: open on the hub when C-r-scoped there, or (in "all" scope) when
  # the worktree exists only on the hub. feat is idempotent so it just opens a
  # window for the existing worktree.
  hub="$(hub_scope)"
  if [[ -z "$hub" && "$(host_scope)" == "all" && ! -d "$worktree_path" ]]; then
    hub="$(hub_with_project "$local_project")"
  fi
  if [[ -n "$hub" ]]; then
    open_hub_worktree "$hub" "$session" "$local_project" "$branch"
    exit 0
  fi

  # Ensure tmux session exists for the repo
  if ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi

  # Check if window for this branch already exists
  existing_win=$(
    tmux list-windows -t "=$session" \
      -F '#{window_index}:#{window_name}' 2>/dev/null \
      | while IFS= read -r line; do
          [[ "${line#*:}" == "$branch" ]] && echo "$line" \
            && break
        done
  )

  if [[ -n "$existing_win" ]]; then
    win_index="${existing_win%%:*}"
    tmux switch-client -t "=$session"
    tmux select-window -t "=$session:$win_index"
  else
    # Create window with feat layout at worktree path
    repl="zsh"
    if [[ -f "$worktree_path/Project.toml" ]]; then
      repl="julia --project=."
    elif [[ -f "$worktree_path/DESCRIPTION" ]]; then
      repl="R"
    fi

    tmux new-window -t "=$session" -n "$branch" \
      -c "$worktree_path"
    tmux select-pane -T "nvim"
    tmux send-keys "nvim ." Enter
    tmux split-window -h -c "$worktree_path"
    tmux select-pane -T "ai:$branch"
    tmux send-keys "${AGENT_CLI_DEV_TOOL:-claude}" Enter
    tmux split-window -v -c "$worktree_path"
    tmux select-pane -T "repl"
    tmux send-keys "$repl" Enter
    tmux select-pane -t 0
    tmux switch-client -t "=$session"
  fi
  exit 0

else
  # Project path. Resolve the target host, then fall through to the window step
  # so you can open the main window OR create a feature branch on that host.
  project="${selected##*/}"
  project_root="$CODE_DIR/$selected"
  session="$(sanitize_session "$project")"

  hub="$(hub_scope)"
  # Seamless cross-host open (only in "all" scope): if the repo is not here but
  # lives on a hub, target that hub and scope the window step to it, so an
  # archie-only repo opens on archie without the user choosing a host. In "home"
  # scope this is skipped so the picker stays strictly local.
  if [[ -z "$hub" && "$(host_scope)" == "all" && ! -d "$project_root" ]]; then
    hub="$(hub_with_project "$selected")"
    [[ -n "$hub" ]] && echo "$hub" > "$HOST_STATE"
  fi
  dbg "project selected=$selected session=$session scope=$(host_scope) hub=$hub"

  if [[ -n "$hub" ]]; then
    # Create/clone the session on the hub (no jump), then refresh its window
    # cache so the window step lists it right away. pick_window (scoped to the
    # hub) then opens a window or creates a feature branch ON the hub. Bail with
    # a visible message if the hub session could not be created, rather than
    # letting the window step target a missing session and silently no-op.
    ensure_hub_session "$hub" "$session" "~/code/$selected" "$selected" \
      || exit 0
    ssh "$hub" \
      "tmux list-windows -t '=$session' -F '#{window_activity} #{window_index}:#{window_name}'" \
      >"$CACHE_DIR/$hub-windows-$session" 2>/dev/null
  elif ! tmux has-session -t "=$session" 2>/dev/null; then
    tmuxinator start project \
      "$session" "$project_root" --no-attach
  fi
fi

# Step 2: pick a window in the resolved session (or create one)
pick_window "$session"
