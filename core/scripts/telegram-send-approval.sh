#!/bin/bash
# ============================================================================
# Telegram Send Approval Request
#
# Sends a permission request to the founder with inline keyboard buttons:
#   [Approve] [Reject] [Details]
#
# The founder can respond at any time — no timeout. Button clicks are
# handled by telegram-poll.sh which writes approval/rejection files.
#
# Usage:
#   bash telegram-send-approval.sh <request_id>
# ============================================================================
set -euo pipefail

REQUEST_ID="$1"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
CONFIG_FILE="$PROJECT_DIR/.claude/ceoloop.json"
ENV_FILE="$PROJECT_DIR/.claude/telegram/.env"
PENDING_FILE="$PROJECT_DIR/.claude/approvals/pending/${REQUEST_ID}.json"

[ ! -f "$PENDING_FILE" ] && exit 1

# Read founder chat ID
CHAT_ID=$(jq -r '.founder_chat_id // empty' "$CONFIG_FILE" 2>/dev/null)
[ -z "$CHAT_ID" ] && exit 1

# Read bot token safely
TOKEN=""
while IFS='=' read -r key value; do
  [ "$key" = "TELEGRAM_BOT_TOKEN" ] && TOKEN="$value"
done < "$ENV_FILE"
[ -z "$TOKEN" ] && exit 1

# Read request details
COMMAND=$(jq -r '.command' "$PENDING_FILE")
DESCRIPTION=$(jq -r '.description // "No description"' "$PENDING_FILE")
TOOL=$(jq -r '.tool // "Bash"' "$PENDING_FILE")

# Truncate command for display (keep first 200 chars)
if [ ${#COMMAND} -gt 200 ]; then
  DISPLAY_CMD="${COMMAND:0:200}..."
else
  DISPLAY_CMD="$COMMAND"
fi

# Build message text (plain text — avoids Markdown escaping issues)
TEXT=$(printf "Permission Request\n\nTool: %s\nAction: %s\nReason: %s" "$TOOL" "$DISPLAY_CMD" "$DESCRIPTION")

# Build inline keyboard
KEYBOARD=$(jq -n \
  --arg approve "approve:${REQUEST_ID}" \
  --arg reject "reject:${REQUEST_ID}" \
  --arg details "details:${REQUEST_ID}" \
  '{inline_keyboard: [[
    {text: "Approve", callback_data: $approve},
    {text: "Reject", callback_data: $reject},
    {text: "More", callback_data: $details}
  ]]}')

# Build payload
PAYLOAD=$(jq -n \
  --arg chat_id "$CHAT_ID" \
  --arg text "$TEXT" \
  --argjson reply_markup "$KEYBOARD" \
  '{chat_id: $chat_id, text: $text, reply_markup: $reply_markup}')

# Send via Telegram API (token in curl config, not command line)
CURL_CONF=$(mktemp)
trap 'rm -f "$CURL_CONF"' EXIT
echo "url = https://api.telegram.org/bot${TOKEN}/sendMessage" > "$CURL_CONF"
chmod 600 "$CURL_CONF"

RESPONSE=$(curl -s -X POST -K "$CURL_CONF" \
  -H "Content-Type: application/json" \
  -d "$PAYLOAD")

# Store the Telegram message_id in the pending file for later editing
TG_MSG_ID=$(echo "$RESPONSE" | jq -r '.result.message_id // empty' 2>/dev/null)
if [ -n "$TG_MSG_ID" ]; then
  TMP=$(mktemp)
  jq --arg msg_id "$TG_MSG_ID" --arg chat_id "$CHAT_ID" \
    '. + {telegram_message_id: $msg_id, telegram_chat_id: $chat_id}' \
    "$PENDING_FILE" > "$TMP" && mv "$TMP" "$PENDING_FILE"
fi
