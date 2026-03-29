#!/bin/bash
# CEOLoop Hook: Enforce that all agent spawns use run_in_background: true.
#
# The CEO must never block on a foreground agent call. Foreground agents
# prevent the CEO from processing incoming messages (Telegram, etc.),
# which means messages are lost or delayed.
#
# This hook only fires for the main session (no agent_id = CEO).
# Agent teammates spawning their own sub-agents are not affected.

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
RUN_IN_BG=$(echo "$INPUT" | jq -r '.tool_input.run_in_background // false')

# Only enforce on the main session (CEO has no agent_id)
if [ -z "$AGENT_ID" ] && [ "$RUN_IN_BG" != "true" ]; then
  echo "BLOCKED: All agents must be spawned with run_in_background: true. CEO must never block on foreground work." >&2
  exit 2
fi

exit 0
