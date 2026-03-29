#!/bin/bash
# ============================================================================
# Check Telegram Inbox
#
# Reads unprocessed messages from the inbox, outputs them as readable text,
# and moves them to the processed/ directory.
#
# Designed to be called by the CEO on a schedule (via /loop or CronCreate).
# Each call drains all pending messages.
#
# Usage:
#   bash telegram-check-inbox.sh          # Read and process new messages
#   bash telegram-check-inbox.sh --peek   # Read without marking as processed
#   bash telegram-check-inbox.sh --count  # Just print the count
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$PROJECT_DIR/.claude/telegram"
INBOX_DIR="$STATE_DIR/inbox"
PROCESSED_DIR="$STATE_DIR/processed"

mkdir -p "$INBOX_DIR" "$PROCESSED_DIR"

MODE="${1:-read}"

# Count new messages (only .json files, not alerts or other artifacts)
count_new() {
  local count=0
  for f in "$INBOX_DIR"/*.json; do
    [ -f "$f" ] || continue
    count=$((count + 1))
  done
  echo "$count"
}

# Just print count
if [ "$MODE" = "--count" ]; then
  count_new
  exit 0
fi

# Check if there are any messages
NEW_COUNT=$(count_new)
if [ "$NEW_COUNT" -eq 0 ]; then
  echo "No new Telegram messages."
  exit 0
fi

echo "=== $NEW_COUNT new Telegram message(s) ==="
echo ""

# Process each message, sorted by update_id (chronological)
for f in $(ls "$INBOX_DIR"/*.json 2>/dev/null | sort); do
  [ -f "$f" ] || continue

  # Extract fields
  USERNAME=$(jq -r '.username // "unknown"' "$f" 2>/dev/null)
  TEXT=$(jq -r '.text // ""' "$f" 2>/dev/null)
  CHAT_ID=$(jq -r '.chat_id // ""' "$f" 2>/dev/null)
  MSG_ID=$(jq -r '.message_id // ""' "$f" 2>/dev/null)
  TIMESTAMP=$(jq -r '.timestamp // ""' "$f" 2>/dev/null)
  RECEIVED=$(jq -r '.received_at // ""' "$f" 2>/dev/null)

  # Format timestamp
  if [ -n "$TIMESTAMP" ] && [ "$TIMESTAMP" != "null" ]; then
    TIME_STR=$(date -r "$TIMESTAMP" "+%H:%M:%S" 2>/dev/null || echo "$TIMESTAMP")
  else
    TIME_STR="$RECEIVED"
  fi

  # Output the message
  echo "--- From: $USERNAME | $TIME_STR | chat:$CHAT_ID msg:$MSG_ID ---"
  if [ -n "$TEXT" ] && [ "$TEXT" != "" ]; then
    echo "$TEXT"
  else
    echo "(no text -- may be a photo, sticker, or other media)"
  fi
  echo ""

  # Move to processed (unless peeking)
  if [ "$MODE" != "--peek" ]; then
    mv "$f" "$PROCESSED_DIR/" 2>/dev/null || true
  fi
done

echo "=== End of messages ==="
