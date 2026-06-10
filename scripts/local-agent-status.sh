#!/bin/bash
# Local agent monitor with a host label (home on the mac, archie on archie),
# so it is clearly distinguishable from the remote segment in the status bar.
s=$("$HOME/code/seabbs/dotfiles/scripts/agent-sessions.sh" --status 2>/dev/null)
[ -z "$s" ] && exit 0
label=home
[ "$(hostname -s)" = "archie" ] && label=archie
printf '#[fg=#a6da95]%s#[default] %s' "$label" "$s"
