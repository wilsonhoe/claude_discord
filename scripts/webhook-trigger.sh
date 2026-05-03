#!/bin/bash
# Webhook Trigger - Monitors repo for changes and triggers auto-push
# This simulates a webhook by watching for file changes using inotify
#
# Usage: ./webhook-trigger.sh [start|stop|status]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PIDFILE="/tmp/github-webhook-trigger.pid"
LOGFILE="/tmp/github-webhook-trigger.log"
PUSH_SCRIPT="$REPO_ROOT/scripts/github-auto-push.sh"

start_monitor() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Webhook trigger already running (PID: $(cat "$PIDFILE"))"
    exit 0
  fi

  echo "Starting webhook trigger..."
  echo "Watching: $REPO_ROOT"
  echo "Log: $LOGFILE"

  # Check if inotifywait is available
  if ! command -v inotifywait >/dev/null 2>&1; then
    echo "[ERROR] inotifywait not found. Install inotify-tools:"
    echo "  sudo apt install inotify-tools"
    exit 1
  fi

  # Start background monitor
  (
    echo "=== Webhook Trigger Started $(date) ===" > "$LOGFILE"
    while true; do
      # Wait for any file change (excluding .git)
      if inotifywait -r -e modify,move,create,delete \
        --exclude '(.git/|.log$|threads.db|node_modules/)' \
        -q \
        "$REPO_ROOT" 2>/dev/null; then

        echo "[$(date '+%H:%M:%S')] Change detected, waiting 30s for batching..." >> "$LOGFILE"
        sleep 30

        # Run auto-push
        if [ -x "$PUSH_SCRIPT" ]; then
          echo "[$(date '+%H:%M:%S')] Triggering auto-push..." >> "$LOGFILE"
          "$PUSH_SCRIPT" >> "$LOGFILE" 2>&1 || true
        else
          echo "[$(date '+%H:%M:%S')] Push script not found: $PUSH_SCRIPT" >> "$LOGFILE"
        fi
      fi
    done
  ) &

  echo $! > "$PIDFILE"
  echo "Webhook trigger started (PID: $(cat "$PIDFILE"))"
}

stop_monitor() {
  if [ -f "$PIDFILE" ]; then
    PID=$(cat "$PIDFILE")
    if kill -0 "$PID" 2>/dev/null; then
      echo "Stopping webhook trigger (PID: $PID)..."
      kill "$PID"
      rm -f "$PIDFILE"
      echo "Stopped."
    else
      echo "Webhook trigger not running (stale PID file)"
      rm -f "$PIDFILE"
    fi
  else
    echo "Webhook trigger not running"
  fi
}

show_status() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "Status: RUNNING (PID: $(cat "$PIDFILE"))"
    echo "Log: $LOGFILE"
    echo "Last 5 log entries:"
    tail -5 "$LOGFILE" 2>/dev/null || echo "(no log entries)"
  else
    echo "Status: STOPPED"
    echo "Start with: $0 start"
  fi
}

case "${1:-status}" in
  start)
    start_monitor
    ;;
  stop)
    stop_monitor
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: $0 [start|stop|status]"
    exit 1
    ;;
esac
