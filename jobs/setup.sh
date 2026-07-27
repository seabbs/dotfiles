#!/bin/bash
# Install scheduled jobs.
# macOS: generate plists from templates and load via launchd.
# Linux: install user crontab entries.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$HOME/.local/share/sync-repos"
mkdir -p "$HOME/.local/share/julia-maintenance"
mkdir -p "$HOME/.local/share/update-claude-plugins"
mkdir -p "$HOME/.local/share/org-sync"
mkdir -p "$HOME/.local/share/worktree-gc"

# Job definitions, pipe separated:
#   label|script|hour|minute|extra PATH|weekday|args
# weekday is empty for daily, or 0-6 (0 = Sunday) for weekly.
# gh lives in /usr/local/bin or /opt/homebrew/bin, already on the default
# PATH below, so org-sync and worktree-gc need no extra PATH.
JULIA_PATH="$HOME/.juliaup/bin:"
LOCAL_PATH="$HOME/.local/bin:"
JOBS=(
  "com.seabbs.org-sync|org-sync.sh|6|0|||"
  "com.seabbs.julia-maintenance|julia-maintenance.sh|6|30|$JULIA_PATH||"
  "com.seabbs.sync-repos|sync-repos.sh|7|0|||"
  "com.seabbs.update-claude-plugins|update-claude-plugins.sh|7|15|$LOCAL_PATH||"
  "com.seabbs.worktree-gc|worktree-gc.sh|5|0||0|--apply"
)

if [[ "$(uname)" == "Darwin" ]]; then
  AGENTS_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$AGENTS_DIR"

  generate_plist() {
    local label="$1" script="$2" hour="$3" minute="$4"
    local extra_path="$5" weekday="$6" args="$7"
    local log_name="${label#com.seabbs.}"
    local log_dir="$HOME/.local/share/$log_name"
    mkdir -p "$log_dir"

    local arg_xml=""
    [ -n "$args" ] && arg_xml="
    <string>${args}</string>"
    local weekday_xml=""
    [ -n "$weekday" ] && weekday_xml="
    <key>Weekday</key>
    <integer>${weekday}</integer>"

    cat <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${label}</string>
  <key>ProgramArguments</key>
  <array>
    <string>/bin/bash</string>
    <string>${DOTFILES}/scripts/${script}</string>${arg_xml}
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>${minute}</integer>${weekday_xml}
  </dict>
  <key>StandardOutPath</key>
  <string>${log_dir}/launchd-stdout.log</string>
  <key>StandardErrorPath</key>
  <string>${log_dir}/launchd-stderr.log</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>${extra_path}/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin</string>
  </dict>
</dict>
</plist>
PLIST
  }

  for job in "${JOBS[@]}"; do
    IFS='|' read -r label script hour minute extra_path weekday args \
      <<< "$job"
    target="$AGENTS_DIR/$label.plist"

    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
    generate_plist "$label" "$script" "$hour" "$minute" \
      "$extra_path" "$weekday" "$args" > "$target"
    launchctl bootstrap "gui/$(id -u)" "$target"
    echo "Loaded $label"
  done
else
  install_cron() {
    local script="$1" schedule="$2" label="$3" args="$4"
    local cmd="$schedule /bin/bash $DOTFILES/scripts/$script"
    [ -n "$args" ] && cmd="$cmd $args"
    if crontab -l 2>/dev/null | grep -qF "$script"; then
      echo "$label cron job already installed"
    else
      (crontab -l 2>/dev/null; echo "$cmd") | crontab -
      echo "Installed $label cron job"
    fi
  }

  for job in "${JOBS[@]}"; do
    IFS='|' read -r label script hour minute extra_path weekday args \
      <<< "$job"
    install_cron "$script" "$minute $hour * * ${weekday:-*}" \
      "${label#com.seabbs.}" "$args"
  done
fi
