#!/bin/bash
# ============================================================================
# Telegram Poll — Dual-Fetch Strategy
#
# Polls the Telegram Bot API using two fetches (recent history + forward
# from offset) to prevent message loss. Deduplicates and writes new
# messages to the inbox as JSON files.
#
# State is stored under .claude/telegram/ inside the project directory
# so everything is portable. Copy the project, add .env, run the daemon.
#
# Called by telegram-daemon.sh every 5 seconds. Not intended to be run
# directly (though it works fine standalone for debugging).
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
STATE_DIR="$PROJECT_DIR/.claude/telegram"
INBOX_DIR="$STATE_DIR/inbox"
PROCESSED_DIR="$STATE_DIR/processed"
OFFSET_FILE="$PROJECT_DIR/.claude/telegram-offset"
# Migrate old offset location
[ -f "$STATE_DIR/telegram-offset" ] && [ ! -f "$OFFSET_FILE" ] && mv "$STATE_DIR/telegram-offset" "$OFFSET_FILE"
HEALTH_FILE="$STATE_DIR/health.json"
ACCESS_FILE="$STATE_DIR/access.json"
ENV_FILE="$STATE_DIR/.env"
DEDUP_FILE="$STATE_DIR/processed-ids.txt"

# Read bot token from project config
TOKEN=""
while IFS='=' read -r key value; do
  [ "$key" = "TELEGRAM_BOT_TOKEN" ] && TOKEN="$value"
done < "$ENV_FILE"

if [ -z "$TOKEN" ]; then
  echo "ERROR: No TELEGRAM_BOT_TOKEN found in $ENV_FILE" >&2
  exit 1
fi

# Read allowlisted user ID
ALLOWED_USER_ID="$(jq -r '.allowFrom[0] // empty' "$ACCESS_FILE" 2>/dev/null)"
if [ -z "$ALLOWED_USER_ID" ]; then
  echo "ERROR: No allowed user ID in $ACCESS_FILE" >&2
  exit 1
fi

mkdir -p "$INBOX_DIR" "$PROCESSED_DIR"

# Auto-seed dedup file from existing processed messages (migration from v2)
if [ ! -f "$DEDUP_FILE" ]; then
  touch "$DEDUP_FILE"
  for f in "$PROCESSED_DIR"/*.json; do
    [ -f "$f" ] || continue
    local_mid=$(jq -r '.message_id // empty' "$f" 2>/dev/null)
    [ -n "$local_mid" ] && echo "$local_mid" >> "$DEDUP_FILE"
  done
  # Also seed from any existing inbox messages
  for f in "$INBOX_DIR"/*.json; do
    [ -f "$f" ] || continue
    local_mid=$(jq -r '.message_id // empty' "$f" 2>/dev/null)
    [ -n "$local_mid" ] && echo "$local_mid" >> "$DEDUP_FILE"
  done
  sort -u -o "$DEDUP_FILE" "$DEDUP_FILE"
fi

# --- Dedup check using append-only file ---
is_already_processed() {
  local needle="$1"
  grep -qxF "$needle" "$DEDUP_FILE" 2>/dev/null
}

mark_processed() {
  local msg_id="$1"
  echo "$msg_id" >> "$DEDUP_FILE"
}

# Trim dedup file if it gets too large (over 10000 lines -> keep last 5000)
trim_dedup_file() {
  local line_count
  line_count=$(wc -l < "$DEDUP_FILE" 2>/dev/null || echo 0)
  if [ "$line_count" -gt 10000 ]; then
    local tmp
    tmp=$(mktemp)
    tail -n 5000 "$DEDUP_FILE" > "$tmp"
    mv "$tmp" "$DEDUP_FILE"
  fi
}

# --- Approvals directory ---
APPROVALS_DIR="$PROJECT_DIR/.claude/approvals"

# --- Secure API call helper (GET) ---
api_call() {
  local endpoint="$1"
  local curl_conf
  curl_conf=$(mktemp)
  echo "url = https://api.telegram.org/bot${TOKEN}/${endpoint}" > "$curl_conf"
  chmod 600 "$curl_conf"
  local result
  result=$(curl -s -K "$curl_conf" 2>/dev/null) || result=""
  rm -f "$curl_conf"
  echo "$result"
}

# --- Secure API call helper (POST JSON) ---
api_post() {
  local endpoint="$1"
  local data="$2"
  local curl_conf
  curl_conf=$(mktemp)
  echo "url = https://api.telegram.org/bot${TOKEN}/${endpoint}" > "$curl_conf"
  chmod 600 "$curl_conf"
  local result
  result=$(echo "$data" | curl -s -X POST -K "$curl_conf" -H "Content-Type: application/json" -d @- 2>/dev/null) || result=""
  rm -f "$curl_conf"
  echo "$result"
}

# --- Handle approval callback queries (button clicks) ---
handle_callback() {
  local callback_id="$1"
  local callback_data="$2"
  local chat_id="$3"
  local message_id="$4"

  local action request_id
  action=$(echo "$callback_data" | cut -d: -f1)
  request_id=$(echo "$callback_data" | cut -d: -f2)

  local pending_file="$APPROVALS_DIR/pending/$request_id.json"

  case "$action" in
    approve)
      if [ -f "$pending_file" ]; then
        mkdir -p "$APPROVALS_DIR/approved"
        local cmd
        cmd=$(jq -r '.command' "$pending_file")
        jq '.status = "approved"' "$pending_file" > "$APPROVALS_DIR/approved/$request_id.json"
        rm -f "$pending_file"

        # Edit the original message to show result
        api_post "editMessageText" "$(jq -n \
          --arg chat_id "$chat_id" \
          --argjson message_id "$message_id" \
          --arg text "$(printf "Approved\n\n%s" "$cmd")" \
          '{chat_id: $chat_id, message_id: $message_id, text: $text}')" >/dev/null 2>&1

        # Drop a message in inbox so CEO knows to retry
        jq -n \
          --arg request_id "$request_id" \
          --arg command "$cmd" \
          --arg received_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{type: "approval_response", action: "approved", request_id: $request_id,
            command: $command, text: "Founder approved this command. Re-assign to the responsible agent.",
            received_at: $received_at, source: "approval-gate"}' \
          > "$INBOX_DIR/approval_${request_id}.json" 2>/dev/null
      fi
      api_post "answerCallbackQuery" "$(jq -n \
        --arg id "$callback_id" --arg text "Approved" \
        '{callback_query_id: $id, text: $text}')" >/dev/null 2>&1
      ;;

    reject)
      if [ -f "$pending_file" ]; then
        mkdir -p "$APPROVALS_DIR/rejected"
        local cmd
        cmd=$(jq -r '.command' "$pending_file")
        jq '.status = "rejected"' "$pending_file" > "$APPROVALS_DIR/rejected/$request_id.json"
        rm -f "$pending_file"

        api_post "editMessageText" "$(jq -n \
          --arg chat_id "$chat_id" \
          --argjson message_id "$message_id" \
          --arg text "$(printf "Rejected\n\n%s" "$cmd")" \
          '{chat_id: $chat_id, message_id: $message_id, text: $text}')" >/dev/null 2>&1

        jq -n \
          --arg request_id "$request_id" \
          --arg command "$cmd" \
          --arg received_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
          '{type: "approval_response", action: "rejected", request_id: $request_id,
            command: $command, text: "Founder rejected this command. Do not retry.",
            received_at: $received_at, source: "approval-gate"}' \
          > "$INBOX_DIR/approval_${request_id}.json" 2>/dev/null
      fi
      api_post "answerCallbackQuery" "$(jq -n \
        --arg id "$callback_id" --arg text "Rejected" \
        '{callback_query_id: $id, text: $text}')" >/dev/null 2>&1
      ;;

    details)
      if [ -f "$pending_file" ]; then
        local full_cmd desc ts tool
        full_cmd=$(jq -r '.command' "$pending_file")
        desc=$(jq -r '.description // "None"' "$pending_file")
        ts=$(jq -r '.timestamp // "Unknown"' "$pending_file")
        tool=$(jq -r '.tool // "Bash"' "$pending_file")

        local details_text
        details_text=$(printf "Request Details\n\nID: %s\nTool: %s\nTime: %s\nReason: %s\n\nFull command:\n%s" \
          "$request_id" "$tool" "$ts" "$desc" "$full_cmd")

        # Send as a new message (keep the buttons on the original)
        api_post "sendMessage" "$(jq -n \
          --arg chat_id "$chat_id" \
          --arg text "$details_text" \
          '{chat_id: $chat_id, text: $text}')" >/dev/null 2>&1
      fi
      api_post "answerCallbackQuery" "$(jq -n \
        --arg id "$callback_id" \
        '{callback_query_id: $id}')" >/dev/null 2>&1
      ;;
  esac
}

# --- Fetch 1: Recent history (last 20 messages, ignoring offset) ---
RECENT_RESPONSE=$(api_call "getUpdates?offset=-20&timeout=0&limit=20")

# --- Fetch 2: Forward from last known offset (normal poll) ---
OFFSET=0
[ -f "$OFFSET_FILE" ] && OFFSET=$(cat "$OFFSET_FILE")
FORWARD_RESPONSE=$(api_call "getUpdates?offset=${OFFSET}&timeout=0&limit=100")

# --- Merge and dedup updates from both fetches ---
MERGED_UPDATES=$(
  {
    echo "$RECENT_RESPONSE" | jq -c '.result[]?' 2>/dev/null
    echo "$FORWARD_RESPONSE" | jq -c '.result[]?' 2>/dev/null
  } | jq -sc 'unique_by(.update_id) | sort_by(.update_id) | .[]' 2>/dev/null
)

NEW_COUNT=0

# Process updates using here-string (not pipe) so variables propagate
while read -r update; do
  [ -z "$update" ] && continue

  UPDATE_ID=$(echo "$update" | jq -r '.update_id')

  # Advance offset past this update
  NEXT_OFFSET=$((UPDATE_ID + 1))
  CURRENT_OFFSET=0
  [ -f "$OFFSET_FILE" ] && CURRENT_OFFSET=$(cat "$OFFSET_FILE")
  [ "$NEXT_OFFSET" -gt "$CURRENT_OFFSET" ] && echo "$NEXT_OFFSET" > "$OFFSET_FILE"

  # --- Handle callback queries (approval button clicks) ---
  CALLBACK_DATA=$(echo "$update" | jq -r '.callback_query.data // empty')
  if [ -n "$CALLBACK_DATA" ]; then
    CB_ID=$(echo "$update" | jq -r '.callback_query.id')
    CB_USER=$(echo "$update" | jq -r '.callback_query.from.id // empty')
    CB_CHAT=$(echo "$update" | jq -r '.callback_query.message.chat.id // empty')
    CB_MSG=$(echo "$update" | jq -r '.callback_query.message.message_id // empty')
    # Security: only process from allowed user
    [ "$CB_USER" = "$ALLOWED_USER_ID" ] && handle_callback "$CB_ID" "$CALLBACK_DATA" "$CB_CHAT" "$CB_MSG"
    continue
  fi

  # --- Handle regular messages ---
  USER_ID=$(echo "$update" | jq -r '.message.from.id // empty')
  MSG_ID=$(echo "$update" | jq -r '.message.message_id // empty')

  # Security: only process messages from allowlisted users
  [ "$USER_ID" != "$ALLOWED_USER_ID" ] && continue

  # Skip if no message_id
  [ -z "$MSG_ID" ] && continue

  # Dedup: skip if we already processed this message_id
  if is_already_processed "$MSG_ID"; then
    continue
  fi

  # Extract fields and build JSON safely with jq
  echo "$update" | jq '{
    update_id: .update_id,
    chat_id: (.message.chat.id | tostring),
    message_id: (.message.message_id | tostring),
    user_id: (.message.from.id | tostring),
    username: (.message.from.username // .message.from.first_name // "unknown"),
    text: (.message.text // ""),
    timestamp: (.message.date | tostring),
    received_at: now | strftime("%Y-%m-%dT%H:%M:%SZ"),
    source: "poll-dual-fetch"
  }' > "$INBOX_DIR/${UPDATE_ID}.json" 2>/dev/null || continue

  # Record this message_id as processed
  mark_processed "$MSG_ID"

  NEW_COUNT=$((NEW_COUNT + 1))
done <<< "$MERGED_UPDATES"

# Set restrictive permissions on inbox files
chmod 600 "$INBOX_DIR"/*.json 2>/dev/null || true

# Clean processed JSON files older than 7 days
find "$PROCESSED_DIR" -name "*.json" -mtime +7 -delete 2>/dev/null || true

# Trim dedup file if needed
trim_dedup_file

# --- Health status ---
NOW_ISO=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

BOT_INFO=$(api_call "getMe")
BOT_OK=$(echo "$BOT_INFO" | jq -r '.ok // false' 2>/dev/null)

if [ "$BOT_OK" = "true" ]; then
  STATUS="healthy"
else
  STATUS="bot_api_unreachable"
fi

jq -n \
  --arg status "$STATUS" \
  --arg bot_api "$BOT_OK" \
  --arg last_poll "$NOW_ISO" \
  '{
    status: $status,
    bot_api_reachable: ($bot_api == "true"),
    last_poll: $last_poll
  }' > "$HEALTH_FILE"

chmod 600 "$HEALTH_FILE"

echo "$STATUS"
