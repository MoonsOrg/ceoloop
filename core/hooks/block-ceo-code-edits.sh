#!/bin/bash
# CEOLoop Hook: Block CEO from editing code files directly.
#
# The CEO agent must delegate code changes to agent teammates. This hook
# prevents accidental direct edits to source code files.
#
# Allowed: files inside .claude/ (settings, agents, hooks, skills, config),
# markdown files, and documentation.
#
# This hook only fires for the main session (no agent_id = CEO).
# Agent teammates are not affected.

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty')

# Only enforce on the main session (CEO has no agent_id)
if [ -z "$AGENT_ID" ] && [ -n "$FILE_PATH" ]; then
  # Block code file extensions
  if echo "$FILE_PATH" | grep -qiE '\.(swift|ts|tsx|js|jsx|py|rb|go|rs|java|kt|c|cpp|h|hpp|html|css|scss|sql|sh|yaml|yml|toml)$'; then
    # Allow files inside .claude/ (settings, agents, hooks, skills)
    if ! echo "$FILE_PATH" | grep -q '/\.claude/'; then
      echo "BLOCKED: CEO must not edit code files directly. Delegate to the appropriate agent." >&2
      exit 2
    fi
  fi
fi

exit 0
