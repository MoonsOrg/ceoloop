# CEOLoop

Run your entire company from one Telegram bot. A thin wrapper over Claude Code Agent Teams — goal-driven autonomous operation.

```
You: "Increase revenue"

CEO reads your project -> proposes teammates -> you approve ->
C-levels claim work from the shared task list -> you get a daily digest.
The system runs indefinitely — learning, adapting, improving.
```

## Quick Start

```bash
# Install (once)
curl -fsSL https://raw.githubusercontent.com/MoonsOrg/ceoloop/main/install.sh | bash

# Set up a project
cd ~/dev/my-project
ceoloop init

# Launch
ceoloop start
```

Message your Telegram bot with a goal. The CEO reads your project, proposes an org chart, and starts working.

## Prerequisites

- [Claude Code](https://claude.ai/code) with a Pro or Max subscription
- macOS (uses tmux + launchd)
- A Telegram bot (create one via [@BotFather](https://t.me/BotFather) in 2 minutes)
- `tmux` and `jq` (`brew install tmux jq`)

## How It Works

CEOLoop installs into any project directory. A CEO agent (the Lead) boots up, reads your codebase, and proposes which C-level teammates are needed. You approve via Telegram. Teammates self-claim work from a shared task list. Each teammate has its own session and context.

You set goals, not tasks. The CEO figures out what to do, delegates it, measures results, and adapts.

### Architecture

```
You (Telegram)
  -> Polling daemon (writes messages to disk every 5s)
       -> CEO (Lead Agent — persistent, always responsive)
            |
            +-- Shared Task List
            |   Tasks are claimed by whichever teammate is available
            |
            +-- CTO (Teammate — own session, own context)
            |   Claims: code tasks, builds, architecture, bugs
            |
            +-- CMO (Teammate — own session, own context)
            |   Claims: content, social, GTM, analytics
            |
            +-- [More teammates added dynamically]
                Founder says "hire a CFO" -> CEO proposes -> approved -> spawned
```

**Key design decisions:**
- **CEO never blocks.** Every task goes to a teammate. The CEO stays idle and responsive to Telegram at all times. Enforced by hooks that prevent the CEO from running builds, editing code, or spawning foreground agents.
- **Telegram is decoupled.** A polling daemon captures messages to disk every 5 seconds. The CEO reads them on a schedule. Messages are never lost, even when the CEO is mid-turn.
- **No custom agent runtime.** Uses Claude Code's native Agent Teams. The wrapper is: CLI + Telegram scripts + enforcement hooks + a boot skill.
- **Goal-driven.** You say "increase revenue." The CEO breaks it into objectives, delegates, measures, adjusts. Indefinitely.
- **Teammates are dynamic.** CEO proposes C-levels after reading the project. The team grows with the project.

## Installation

### Global Install

One command installs the `ceoloop` CLI:

```bash
curl -fsSL https://raw.githubusercontent.com/MoonsOrg/ceoloop/main/install.sh | bash
```

This clones the repo to `~/.ceoloop/` and adds `ceoloop` to your PATH.

### Per-Project Setup

```bash
cd ~/dev/my-project
ceoloop init
```

The wizard asks for:
1. **Project name** (used for tmux session, logs, LaunchAgent)
2. **Telegram bot token** (from @BotFather)
3. **Your Telegram user ID** (send /start to @userinfobot to get it)

This creates the `.claude/` infrastructure in your project:

```
.claude/
  ceoloop.json          # Project config
  telegram/
    .env                # Bot token (chmod 600)
    access.json         # Sender allowlist
  agents/               # Your agent definitions (empty — CEO proposes them)
  hooks/                # CEO enforcement hooks
  scripts/              # Telegram daemon, send, poll, health scripts
  skills/boot/SKILL.md  # CEO boot sequence
  logs/                 # Agent logs (created at runtime)
  settings.json         # Permissions, hooks config
```

### Launch

```bash
ceoloop start
```

This starts a tmux session with two windows:
- **daemon**: Telegram polling daemon (captures messages to disk)
- **ceo**: Claude Code CEO agent (processes messages, delegates work)

## CLI Commands

```bash
ceoloop init          # Interactive setup in current project
ceoloop start         # Launch daemon + CEO in tmux
ceoloop stop          # Kill everything cleanly
ceoloop status        # Check what's running
ceoloop restart       # Stop then start
ceoloop install       # Auto-start on boot (macOS LaunchAgent, daily 4am restart)
ceoloop uninstall     # Remove auto-start
ceoloop update        # Pull latest, re-copy core files to current project
ceoloop update --all  # Update all registered projects
ceoloop version       # Print version
```

## Agent Definitions

The CEO proposes agents after reading your project. You can also define them manually at `.claude/agents/`:

```markdown
---
name: cto
description: CTO — codebase, architecture, builds, deploys
model: opus
tools: Read, Write, Edit, Bash, Glob, Grep, Agent, WebFetch, WebSearch
---

You are the CTO. Your domain is everything technical.

## Rules
- Read code before editing
- Prefer minimal changes
```

The CEO discovers agents from `.claude/agents/*.md` on boot and spawns them as teammates.

## Updates

```bash
# Update ceoloop core (hooks, scripts, boot skill) for current project
ceoloop update

# Update all projects that use ceoloop
ceoloop update --all
```

Updates re-copy core files (hooks, scripts, boot skill) from `~/.ceoloop/core/` into your project. Your agent definitions, Telegram config, logs, and settings are never touched.

## What the CEO Does

### On First Boot
1. Reads your project — codebase, docs, config, git history
2. Proposes which C-level teammates are needed
3. Waits for your approval via Telegram
4. Spawns approved teammates with standing responsibilities

### Ongoing
- **Inbox check every 2 min:** Reads Telegram messages, delegates or responds
- **Heartbeat every 30 min:** Checks goals, adds tasks for teammates
- **Agent cycles every 1h:** Tells each teammate to run their recurring work
- **Daily digest every 6h:** Summarizes team activity, progress, blockers

### What You Control
- Set and change goals anytime via Telegram
- Approve/reject teammate proposals
- Override any decision
- Add or remove teammates ("hire a CTO", "fire the CMO")

## Security

### Honest Assessment

CEOLoop runs with `--dangerously-skip-permissions`. This is unavoidable — Telegram bots have no interactive terminal to approve tool calls. Every autonomous agent system has this same requirement.

### What We Do About It

| Layer | Protection |
|---|---|
| **Network** | Outbound polling only. Zero exposed ports. |
| **Auth** | Telegram sender allowlist. Only your user ID can send commands. |
| **Secrets** | Bot token in `.env` (chmod 600). Passed via curl config files, never in process arguments. |
| **CEO constraints** | Hooks prevent CEO from editing code, running builds, or spawning foreground agents. |
| **Session recycling** | LaunchAgent restarts daily at 4am. Fresh context. |
| **No registry** | No third-party skill/plugin downloads. Local files only. |
| **Input validation** | All JSON constructed via `jq`. No shell injection in message processing. |

### Recommendations

- Run on a dedicated user account if possible
- Don't store sensitive credentials on the same machine
- Review the daily digest — it includes roster changes
- Monitor `.claude/logs/` periodically

## File Structure

After `ceoloop init`:

```
.claude/
  ceoloop.json              # {"project": "myapp", "founder_chat_id": "123..."}
  telegram/
    .env                    # TELEGRAM_BOT_TOKEN=...
    access.json             # {"dmPolicy": "allowlist", "allowFrom": ["123..."]}
    inbox/                  # Incoming messages (JSON, auto-created)
    processed/              # Processed messages (auto-cleaned after 7 days)
  agents/                   # Agent definitions (.md files with frontmatter)
  hooks/
    block-ceo-bash.sh       # Prevents CEO from running builds/deploys
    block-ceo-code-edits.sh # Prevents CEO from editing source code
    enforce-background-agents.sh  # Prevents CEO from spawning foreground agents
  scripts/
    telegram-daemon.sh      # Continuous 5s polling daemon
    telegram-poll.sh        # Dual-fetch poll with dedup
    telegram-send.sh        # Secure message sending
    telegram-check-inbox.sh # Drain and process inbox
    telegram-health.sh      # Bot API health check
  skills/
    boot/SKILL.md           # CEO boot sequence (10 steps)
  logs/                     # Agent logs (auto-created from agent definitions)
  settings.json             # Permissions, hooks, deny rules
```

## Cost

- **Claude Pro/Max**: $20-100/mo (subscription includes all agent calls)
- **Telegram bot**: free
- **Everything else**: free (tmux, launchd, jq are OS-level)

## Troubleshooting

### CEO doesn't respond to Telegram

1. `ceoloop status` — check if it's running
2. `tmux attach -t {project}-ceo` — see what the CEO is doing
3. Check `.claude/telegram/.env` has a valid bot token
4. The daemon polls every 5s and the CEO checks inbox every 2min

### Session dies after laptop sleep

The tmux session survives sleep. If the Claude process inside it dies:
- `ceoloop restart`
- Or install the LaunchAgent: `ceoloop install` (auto-restarts daily at 4am)

### "No .claude/ceoloop.json found"

You need to run `ceoloop init` in your project directory first.

## Uninstall

```bash
ceoloop stop
ceoloop uninstall          # Remove LaunchAgent

# Remove from your project
rm -rf .claude/scripts/ .claude/hooks/ .claude/skills/ .claude/telegram/ .claude/logs/
rm -f .claude/ceoloop.json .claude/settings.json
```

Your project code is never modified — CEOLoop only creates files in `.claude/`.

## License

MIT
