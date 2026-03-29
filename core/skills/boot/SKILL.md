---
name: boot
description: Boot the CEO agent system — discover agents, create team, verify infrastructure, set schedules, report to founder
user-invocable: true
allowed-tools: Read, Bash, Agent, SendMessage, TaskList, TeamCreate, CronCreate, Skill
---

# Boot Sequence

You are the CEO. Follow these steps in order.

## Telegram Architecture (IMPORTANT — read first)

You do NOT have the `--channels plugin:telegram` MCP tool. Instead, Telegram is decoupled:

- **Receiving:** A polling daemon runs in a separate tmux window, writing messages to `.claude/telegram/inbox/` as JSON files. Messages are never lost because they hit disk immediately.
- **Checking inbox:** Run `bash .claude/scripts/telegram-check-inbox.sh` to read new messages. This drains all pending messages and moves them to `processed/`. Use `--peek` to read without marking as processed, `--count` to just get the count.
- **Sending:** Read `.claude/ceoloop.json` for the founder's `chat_id`, then run `bash .claude/scripts/telegram-send.sh "<chat_id>" "<message>"`.
- **Health:** Run `bash .claude/scripts/telegram-health.sh --verbose` to check bot API status.

Set up a `/loop` to check the inbox regularly (see step 8).

## 1. Read Config

Read `.claude/ceoloop.json` for project configuration:
- `project_name` — the project name (used for team name, greetings)
- `founder_chat_id` — Telegram chat ID for sending messages to the founder
- `transport` — messaging transport type

If the file doesn't exist, warn and use defaults.

## 2. Read Memory

Read `MEMORY.md` and key memory files (`project_state.md`, `project_goals.md`, `project_team.md`) if they exist, to restore project state. If no memory exists, this is a fresh boot.

## 3. Check Task Backlog

Run `TaskList` to check for existing tasks. Note any `in_progress` or `pending` tasks.

## 4. Discover Agents

Read `.claude/agents/` to discover which agent definitions exist. List all `*.md` files.

If NO agent definitions exist:
- This is a fresh project with no team yet
- Read the project directory (README, CLAUDE.md, docs, package.json, etc.) to understand what this project does
- Propose which agents are needed based on the project type and stack
- Send the proposal to the founder via Telegram and wait for approval
- Skip to step 8 (set up schedules for inbox polling) so you stay responsive while waiting

If agent definitions exist, proceed to step 5.

## 5. Create Team

If the `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` environment variable is set:
- Use `TeamCreate` to create one persistent team named after the project (from `ceoloop.json`)
- Spawn all discovered agents as teammates

For each agent file in `.claude/agents/`:
- Use the filename (without `.md`) as the agent `name`
- Use the file path as `definition_file`
- Spawn with `run_in_background: true`
- If the agent definition mentions `isolation: worktree`, add that param

Skip any agent named `ceo` (that's you).

If `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS` is not set, spawn agents as regular background sub-agents instead.

## 6. Verify Infrastructure

Run these checks in parallel:
- **Chrome CDP**: `curl -s --max-time 3 http://127.0.0.1:9222/json/version` — if it fails, note it (not all projects need Chrome)
- **Telegram send**: Send a boot message to the founder via `bash .claude/scripts/telegram-send.sh "<chat_id>" "CEO agent online. System booted."` — confirms sending works
- **Telegram inbox**: `bash .claude/scripts/telegram-check-inbox.sh --count` — confirms inbox is accessible

## 7. Resume Tasks

For any `in_progress` or `pending` task from step 3:
- Identify which agent owns it
- SendMessage to that agent with context and instructions to continue
- If unowned, assign to the right agent based on domain

## 8. Set Up Schedules

Set up recurring cycles using `/loop`. Each cycle sends a one-line message to the agent telling them to run their recurring cycle. Agent definitions contain the full cycle instructions.

**CRITICAL — Telegram inbox check (every 2 minutes):**
```
/loop 2m Check Telegram inbox: run `bash .claude/scripts/telegram-check-inbox.sh`. If there are messages, read them and act on each one (delegate to agents or respond directly via telegram-send.sh).
```

**Agent cycles (staggered):**
For each discovered agent, set up a recurring cycle. Stagger the intervals to avoid simultaneous firing. Use these defaults unless the agent definition specifies otherwise:
- Code/tech agents: every 1h
- Content/marketing agents: every 1h
- Intelligence/research agents: every 1h
- Video/media agents: every 3h

```
/loop 1h SendMessage to <agent_name>: run your recurring cycle
```

**Digest (every 6 hours):**
Read agent logs from the directory specified in `.claude/ceoloop.json` `logs_dir` field (default: `.claude/logs/`).
```
/loop 6h Digest: read agent logs from the logs_dir configured in .claude/ceoloop.json (default: .claude/logs/), project state, and task list. Summarize team activity, progress, blockers, and priorities. Send to founder via telegram-send.sh.
```

Stagger the cron minutes (e.g. :07, :37, :43, :13) to avoid simultaneous firing.

## 9. Report to Founder

Send a Telegram message via `bash .claude/scripts/telegram-send.sh "<chat_id>" "<message>"`:
- Team created: list all spawned agents
- Infrastructure status (Chrome CDP, Telegram daemon)
- Number of resumed tasks (if any)
- Schedules active (including 2-min inbox check)
- "Ready for instructions."

## 10. Dispatch First Cycles

SendMessage to each agent: "run your recurring cycle"

Then check the Telegram inbox for any messages that arrived during boot. Delegate everything — never do work directly.
