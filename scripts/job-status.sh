#!/bin/bash
# Show status and recent logs for all scheduled jobs.

echo "=== Scheduled Jobs ==="
echo ""

if [[ "$(uname)" == "Darwin" ]]; then
  echo "Platform: macOS (launchd)"
  echo ""
  for label in com.seabbs.sync-repos com.seabbs.julia-maintenance; do
    status=$(launchctl print "gui/$(id -u)/$label" 2>/dev/null \
      | grep "state" | head -1 || echo "  not loaded")
    echo "$label"
    echo "  $status"
  done
else
  echo "Platform: Linux (cron)"
  echo ""
  crontab -l 2>/dev/null | grep -E "sync-repos|julia-maintenance" \
    || echo "  No jobs found"
fi

echo ""
echo "=== Schedule ==="
echo "  sync-repos:        daily at 07:00"
echo "  julia-maintenance: daily at 06:30"

for job in sync-repos julia-maintenance; do
  log="$HOME/.local/share/$job/last-run.log"
  echo ""
  echo "=== $job (last run) ==="
  if [ -f "$log" ]; then
    cat "$log"
  else
    echo "  No log found (never run?)"
  fi
done
