#!/bin/bash
# Install scheduled jobs.
# macOS: generate plists from templates and load via launchd.
# Linux: install user crontab entries.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$(cd "$SCRIPT_DIR/.." && pwd)"

mkdir -p "$HOME/.local/share/sync-repos"
mkdir -p "$HOME/.local/share/julia-maintenance"
mkdir -p "$HOME/.local/share/update-claude-plugins"

# Job definitions: label, script, hour, minute, extra PATH
JOBS=(
  "com.seabbs.sync-repos|sync-repos.sh|7|0|"
  "com.seabbs.julia-maintenance|julia-maintenance.sh|6|30|$HOME/.juliaup/bin:"
  "com.seabbs.update-claude-plugins|update-claude-plugins.sh|7|15|$HOME/.local/bin:"
)

if [[ "$(uname)" == "Darwin" ]]; then
  AGENTS_DIR="$HOME/Library/LaunchAgents"
  mkdir -p "$AGENTS_DIR"

  generate_plist() {
    local label="$1" script="$2" hour="$3" minute="$4"
    local extra_path="$5"
    local log_name="${label#com.seabbs.}"
    local log_dir="$HOME/.local/share/$log_name"
    mkdir -p "$log_dir"

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
    <string>${DOTFILES}/scripts/${script}</string>
  </array>
  <key>StartCalendarInterval</key>
  <dict>
    <key>Hour</key>
    <integer>${hour}</integer>
    <key>Minute</key>
    <integer>${minute}</integer>
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
    IFS='|' read -r label script hour minute extra_path <<< "$job"
    target="$AGENTS_DIR/$label.plist"

    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null
    generate_plist "$label" "$script" "$hour" "$minute" \
      "$extra_path" > "$target"
    launchctl bootstrap "gui/$(id -u)" "$target"
    echo "Loaded $label"
  done
else
  install_cron() {
    local script="$1" schedule="$2" label="$3"
    local cmd="$schedule /bin/bash $DOTFILES/scripts/$script"
    if crontab -l 2>/dev/null | grep -qF "$script"; then
      echo "$label cron job already installed"
    else
      (crontab -l 2>/dev/null; echo "$cmd") | crontab -
      echo "Installed $label cron job"
    fi
  }
  install_cron "sync-repos.sh" "0 7 * * *" "sync-repos"
  install_cron "julia-maintenance.sh" "30 6 * * *" "julia-maintenance"
  install_cron "update-claude-plugins.sh" "15 7 * * *" "update-claude-plugins"
fi
