#!/bin/bash
# ============================================================================
# Telegram Send
#
# Sends a message via the Telegram Bot API. Token is passed through a
# curl config file so it never appears in process arguments (ps aux safe).
#
# Usage:
#   bash telegram-send.sh <chat_id> <text> [reply_to_message_id]
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
ENV_FILE="$PROJECT_DIR/.claude/telegram/.env"

# Read bot token safely
TOKEN=""
while IFS='=' read -r key value; do
  [ "$key" = "TELEGRAM_BOT_TOKEN" ] && TOKEN="$value"
done < "$ENV_FILE"

if [ -z "$TOKEN" ]; then
  echo "ERROR: No TELEGRAM_BOT_TOKEN found in $ENV_FILE" >&2
  exit 1
fi

CHAT_ID="$1"
TEXT="$2"
REPLY_TO="${3:-}"

# Build JSON payload safely with jq (no injection via message text)
if [ -n "$REPLY_TO" ]; then
  PAYLOAD=$(jq -n \
    --arg chat_id "$CHAT_ID" \
    --arg text "$TEXT" \
    --argjson reply_to "$REPLY_TO" \
    '{chat_id: $chat_id, text: $text, parse_mode: "Markdown", reply_parameters: {message_id: $reply_to}}')
else
  PAYLOAD=$(jq -n \
    --arg chat_id "$CHAT_ID" \
    --arg text "$TEXT" \
    '{chat_id: $chat_id, text: $text, parse_mode: "Markdown"}')
fi

# Post with JSON content type
# Token passed via curl config file to avoid ps aux exposure
CURL_CONF=$(mktemp)
trap 'rm -f "$CURL_CONF"' EXIT
echo "url = https://api.telegram.org/bot${TOKEN}/sendMessage" > "$CURL_CONF"
chmod 600 "$CURL_CONF"
curl -s -X POST -K "$CURL_CONF" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD"
