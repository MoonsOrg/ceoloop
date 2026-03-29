#!/bin/bash
# ============================================================================
# Telegram Polling Daemon
#
# Continuously polls the Telegram Bot API and writes messages to disk.
# Runs as a background process in its own tmux window.
#
# Messages land in .claude/telegram/inbox/ as JSON files.
# The CEO reads them via telegram-check-inbox.sh on a schedule.
#
# This is the ONLY process that should poll Telegram. Running multiple
# pollers against the same bot token causes 409 conflicts.
#
# Usage:
#   bash telegram-daemon.sh           # Run in foreground (for tmux)
#   bash telegram-daemon.sh --once    # Poll once and exit (for testing)
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
POLL_SCRIPT="$SCRIPT_DIR/telegram-poll.sh"
POLL_INTERVAL=5  # seconds between polls
STATE_DIR="$PROJECT_DIR/.claude/telegram"
PID_FILE="$STATE_DIR/daemon.pid"

mkdir -p "$STATE_DIR"

if [ ! -x "$POLL_SCRIPT" ]; then
  echo "ERROR: telegram-poll.sh not found or not executable at $POLL_SCRIPT" >&2
  exit 1
fi

# Single-run mode for testing
if [ "${1:-}" = "--once" ]; then
  bash "$POLL_SCRIPT"
  exit $?
fi

# Write PID for status checking
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"; exit 0' INT TERM EXIT

echo "[telegram-daemon] Started (PID $$, polling every ${POLL_INTERVAL}s)"
echo "[telegram-daemon] Inbox: $STATE_DIR/inbox/"
echo "[telegram-daemon] Press Ctrl+C to stop"

CONSECUTIVE_ERRORS=0
MAX_ERRORS=10
LOG_FILE="$STATE_DIR/daemon.log"

# Rotate log if over 1000 lines
rotate_log() {
  if [ -f "$LOG_FILE" ]; then
    local line_count
    line_count=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$line_count" -gt 1000 ]; then
      local tmp
      tmp=$(mktemp)
      tail -n 500 "$LOG_FILE" > "$tmp"
      mv "$tmp" "$LOG_FILE"
    fi
  fi
}

log_msg() {
  echo "[$(date -u +%Y-%m-%dT%H:%M:%SZ)] $1" >> "$LOG_FILE"
}

log_msg "Daemon started (PID $$)"

while true; do
  if POLL_OUTPUT=$(bash "$POLL_SCRIPT" 2>&1); then
    CONSECUTIVE_ERRORS=0
  else
    CONSECUTIVE_ERRORS=$((CONSECUTIVE_ERRORS + 1))
    log_msg "Poll error ($CONSECUTIVE_ERRORS/$MAX_ERRORS): $POLL_OUTPUT"
    echo "[telegram-daemon] Poll error ($CONSECUTIVE_ERRORS/$MAX_ERRORS)" >&2
    if [ "$CONSECUTIVE_ERRORS" -ge "$MAX_ERRORS" ]; then
      log_msg "Too many consecutive errors. Backing off to 30s."
      echo "[telegram-daemon] Too many consecutive errors. Backing off to 30s." >&2
      sleep 30
      CONSECUTIVE_ERRORS=0
    fi
  fi
  rotate_log
  sleep "$POLL_INTERVAL"
done
