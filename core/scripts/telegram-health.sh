#!/bin/bash
# ============================================================================
# Telegram Health Check
#
# Standalone diagnostic that checks:
#   1. Bot API reachability (getMe)
#   2. Pending updates in queue (getUpdates offset=-1)
#   3. Daemon process status (PID file check)
#
# Outputs a clean health JSON to .claude/telegram/health.json
#
# Usage:
#   bash telegram-health.sh             # Run check, output status
#   bash telegram-health.sh --verbose   # Run check with detailed output
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$PROJECT_DIR/.claude/telegram"
HEALTH_FILE="$STATE_DIR/health.json"
PID_FILE="$STATE_DIR/daemon.pid"
ENV_FILE="$STATE_DIR/.env"

VERBOSE=false
[ "${1:-}" = "--verbose" ] && VERBOSE=true

# Read bot token
TOKEN=""
while IFS='=' read -r key value; do
  [ "$key" = "TELEGRAM_BOT_TOKEN" ] && TOKEN="$value"
done < "$ENV_FILE"

if [ -z "$TOKEN" ]; then
  echo "ERROR: No TELEGRAM_BOT_TOKEN found in $ENV_FILE" >&2
  exit 1
fi

mkdir -p "$STATE_DIR"

# --- Secure API call ---
api_call() {
  local endpoint="$1"
  local curl_conf
  curl_conf=$(mktemp)
  echo "url = https://api.telegram.org/bot${TOKEN}/${endpoint}" > "$curl_conf"
  chmod 600 "$curl_conf"
  local result
  result=$(curl -s --max-time 10 -K "$curl_conf" 2>/dev/null) || result=""
  rm -f "$curl_conf"
  echo "$result"
}

NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# --- Check 1: Bot API reachability ---
BOT_INFO=$(api_call "getMe")
BOT_OK=$(echo "$BOT_INFO" | jq -r '.ok // false' 2>/dev/null)
BOT_USERNAME=$(echo "$BOT_INFO" | jq -r '.result.username // "unknown"' 2>/dev/null)

$VERBOSE && echo "Bot API: $BOT_OK (username: @$BOT_USERNAME)"

if [ "$BOT_OK" != "true" ]; then
  STATUS="bot_api_unreachable"
  $VERBOSE && echo "ALERT: Telegram Bot API is not responding. Check token and network."

  jq -n \
    --arg status "$STATUS" \
    --arg bot_username "unknown" \
    --argjson queue_pending 0 \
    --argjson daemon_running false \
    --arg checked_at "$NOW_ISO" \
    '{
      status: $status,
      bot_api_reachable: false,
      bot_username: $bot_username,
      queue_pending: $queue_pending,
      daemon_running: $daemon_running,
      checked_at: $checked_at
    }' > "$HEALTH_FILE"
  chmod 600 "$HEALTH_FILE"

  echo "$STATUS"
  exit 0
fi

# --- Check 2: Pending messages in queue ---
QUEUE_RESPONSE=$(api_call "getUpdates?offset=-1&timeout=0&limit=1")
QUEUE_COUNT=$(echo "$QUEUE_RESPONSE" | jq '.result | length' 2>/dev/null || echo 0)

$VERBOSE && echo "Pending updates in Telegram queue: $QUEUE_COUNT"

# --- Check 3: Daemon running? ---
DAEMON_RUNNING=false
if [ -f "$PID_FILE" ]; then
  DAEMON_PID=$(cat "$PID_FILE" 2>/dev/null)
  if [ -n "$DAEMON_PID" ] && kill -0 "$DAEMON_PID" 2>/dev/null; then
    DAEMON_RUNNING=true
    $VERBOSE && echo "Daemon running (PID $DAEMON_PID)"
  else
    $VERBOSE && echo "Daemon PID file exists but process is not running"
  fi
else
  $VERBOSE && echo "No daemon PID file found"
fi

# --- Determine health status ---
STATUS="healthy"

if [ "$DAEMON_RUNNING" = "false" ]; then
  STATUS="daemon_not_running"
  $VERBOSE && echo "Status: daemon_not_running"
else
  $VERBOSE && echo "Status: healthy"
fi

# --- Write health file ---
jq -n \
  --arg status "$STATUS" \
  --arg bot_username "@$BOT_USERNAME" \
  --argjson queue_pending "$QUEUE_COUNT" \
  --argjson daemon_running "$DAEMON_RUNNING" \
  --arg checked_at "$NOW_ISO" \
  '{
    status: $status,
    bot_api_reachable: true,
    bot_username: $bot_username,
    queue_pending: $queue_pending,
    daemon_running: $daemon_running,
    checked_at: $checked_at
  }' > "$HEALTH_FILE"

chmod 600 "$HEALTH_FILE"

echo "$STATUS"
