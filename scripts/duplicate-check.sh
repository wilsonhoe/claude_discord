#!/bin/bash
# Duplicate bot instance check
# Run via cron every 5 minutes
#
# Usage: ./duplicate-check.sh

COUNT=$(ps aux | grep "tsx src/index" | grep -v grep | wc -l)

if [ "$COUNT" -gt 1 ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') WARNING: $COUNT bot instances detected. Killing duplicates..."
  pkill -9 -f "tsx src/index.ts"
  sleep 2
  systemctl --user restart discord-claude-ubuntu.service
  echo "$(date '+%Y-%m-%d %H:%M:%S') Restarted via systemd."
fi
