#!/bin/bash
# CEOLoop Hook: Block CEO from running build/deploy/long-running commands.
#
# The CEO agent is a coordinator, not a worker. Build commands, package
# managers, and long-running processes must be delegated to the appropriate
# agent teammate.
#
# Allowed: git status, ls, cat, quick lookups, jq, echo, and other
# fast read-only commands.
#
# This hook only fires for the main session (no agent_id = CEO).
# Agent teammates are not affected.

INPUT=$(cat)
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // empty')
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // empty')

# Only enforce on the main session (CEO has no agent_id)
if [ -z "$AGENT_ID" ] && [ -n "$COMMAND" ]; then
  # Block build, deploy, and long-running commands
  if echo "$COMMAND" | grep -qiE '(xcodebuild|xcodegen|swift build|swift test|npm run|npm test|npx |yarn |pnpm |supabase |docker |ffmpeg |yt-dlp|mlx-whisper|pip install|brew install|cargo |make |cmake |gradle |mvn |terraform |kubectl )'; then
    echo "BLOCKED: CEO must not run builds, deploys, or long-running commands. Delegate to the appropriate agent." >&2
    exit 2
  fi
fi

exit 0
