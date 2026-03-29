#!/bin/bash
# ============================================================================
# Approval Gate — PreToolUse hook for destructive commands
#
# Detects dangerous commands and sends them to the founder via Telegram
# for approval using inline keyboard buttons. No timeout — the founder
# responds whenever they're free.
#
# Flow:
#   1. Command matches destructive pattern → check for existing decision
#   2. If approved → allow (exit 0) and clean up approval file
#   3. If rejected → block (exit 1) and clean up
#   4. If pending → block with "awaiting approval" message
#   5. If new → create pending request, send Telegram, block
#
# The agent sees the block message and shelves the task. When the founder
# responds (via Telegram button), telegram-poll.sh writes the decision
# file and drops a message in the inbox. On the next cycle, the CEO
# re-assigns the task and the agent retries.
# ============================================================================
set -euo pipefail

TOOL_INPUT="${CLAUDE_TOOL_INPUT:-}"
[ -z "$TOOL_INPUT" ] && exit 0

COMMAND=$(echo "$TOOL_INPUT" | jq -r '.command // empty' 2>/dev/null)
[ -z "$COMMAND" ] && exit 0

DESCRIPTION=$(echo "$TOOL_INPUT" | jq -r '.description // "No description"' 2>/dev/null)

# --- Destructive command patterns ---
DANGEROUS=false
for pattern in \
  '^rm ' '^rm$' \
  'git push.*--force' 'git push.*-f ' \
  'git reset --hard' \
  'git clean.*-f' \
  'git branch.*-D ' \
  'DROP TABLE' 'DROP DATABASE' 'TRUNCATE ' \
  'docker rm ' 'docker rmi ' \
  'kubectl delete' \
; do
  echo "$COMMAND" | grep -qiE "$pattern" && DANGEROUS=true && break
done

[ "$DANGEROUS" = false ] && exit 0

# --- Exempt routine cleanup (not truly destructive) ---
if echo "$COMMAND" | grep -qE '^rm .*(\.claude/(logs|telegram/processed)/|/tmp/)'; then
  exit 0
fi

# --- Approval check ---
PROJECT_DIR="$(pwd)"
APPROVALS_DIR="$PROJECT_DIR/.claude/approvals"
mkdir -p "$APPROVALS_DIR"/{pending,approved,rejected}

# Deterministic request ID from command content
if command -v md5 >/dev/null 2>&1; then
  REQUEST_ID=$(echo -n "$COMMAND" | md5 | cut -c1-12)
else
  REQUEST_ID=$(echo -n "$COMMAND" | md5sum | cut -c1-12)
fi

# Already approved? Allow and consume the approval
if [ -f "$APPROVALS_DIR/approved/$REQUEST_ID.json" ]; then
  rm -f "$APPROVALS_DIR/approved/$REQUEST_ID.json"
  exit 0
fi

# Already rejected? Block and consume
if [ -f "$APPROVALS_DIR/rejected/$REQUEST_ID.json" ]; then
  rm -f "$APPROVALS_DIR/rejected/$REQUEST_ID.json"
  echo "Command rejected by founder." >&2
  exit 1
fi

# Already pending? Remind and block
if [ -f "$APPROVALS_DIR/pending/$REQUEST_ID.json" ]; then
  echo "Awaiting founder approval via Telegram. Will retry on next cycle." >&2
  exit 1
fi

# --- Create pending request ---
jq -n \
  --arg id "$REQUEST_ID" \
  --arg command "$COMMAND" \
  --arg description "$DESCRIPTION" \
  --arg tool "${CLAUDE_TOOL_NAME:-Bash}" \
  --arg timestamp "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{id: $id, command: $command, description: $description, tool: $tool, timestamp: $timestamp, status: "pending"}' \
  > "$APPROVALS_DIR/pending/$REQUEST_ID.json"

# --- Send Telegram approval request with buttons ---
bash "$PROJECT_DIR/.claude/scripts/telegram-send-approval.sh" "$REQUEST_ID" 2>/dev/null || true

echo "Sent approval request to founder via Telegram. Command shelved until approved." >&2
exit 1
