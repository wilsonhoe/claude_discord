#!/bin/bash
# Kill stuck claude -p processes
# Run via cron every 15 minutes
#
# Usage: ./kill-stuck-sessions.sh

STUCK=$(ps aux | grep "claude -p" | grep -v grep | awk '{if ($3 > 90.0) print $2}')

for PID in $STUCK; do
  RUNTIME=$(ps -o etime= -p $PID | tr -d ' ')
  # Kill if running > 10 minutes
  if [[ "$RUNTIME" =~ ^[0-9]+-[0-9]+:[0-9]+:[0-9]+$ ]] || \
     [[ "$RUNTIME" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    echo "$(date '+%Y-%m-%d %H:%M:%S') Killing stuck process $PID (CPU > 90%, runtime: $RUNTIME)"
    kill -9 $PID
  fi
done
