# Claude Discord Multi-Agent System

> Comprehensive documentation for a Claude Code CLI Discord bot serving as the coordination hub for a multi-agent AI team (Lisa, Nyx, Kael, William).
>
> **Repository:** https://github.com/wilsonhoe/claude_discord  
> **Last Updated:** 2026-05-03  
> **Status:** Production-Ready

---

## Table of Contents

- [Quick Start](#quick-start)
- [What Is This](#what-is-this)
- [Architecture Overview](#architecture-overview)
- [The Agent Team](#the-agent-team)
- [Documentation Index](#documentation-index)
- [Repository Structure](#repository-structure)
- [Key Principles](#key-principles)
- [Safety & Secrets Policy](#safety--secrets-policy)

---

## Quick Start

```bash
# 1. Clone the bot source (separate repo)
git clone https://github.com/fredchu/discord-claude-code-bot

# 2. Configure environment
cp .env.example .env
# Edit .env: add DISCORD_BOT_TOKEN, CLAUDE_API_KEY, etc.

# 3. Start the bot via systemd (NEVER manually)
systemctl --user start discord-claude-ubuntu.service

# 4. Verify single instance
ps aux | grep "tsx src/index" | grep -v grep | wc -l   # should be 1

# 5. Health check
systemctl --user status discord-claude-ubuntu.service --no-pager
```

**Critical Rule:** Always use `systemctl` to manage the bot. Never `npm start` or `nohup` directly — this causes duplicate instances and duplicate Discord responses. See [docs/03-lessons-learned.md](docs/03-lessons-learned.md).

---

## What Is This

This repository documents a production-grade Discord bot integration for **Claude Code CLI** that serves as:

1. **Primary Interface** — Users interact with Claude via Discord threads and @mentions
2. **Multi-Agent Orchestrator** — Routes commands to Lisa, Nyx, Kael, and William
3. **Session Bridge** — Persists Claude sessions across Discord threads with SQLite
4. **Health Monitor** — Auto-detects and recovers from stuck processes, stale sessions, and duplicates

**Two distinct Discord systems cooperate:**

| System | Type | Role | Auto-Responds |
|--------|------|------|--------------|
| **discord-claude-code-bot** | Standalone Node.js bot | User-facing bot | Yes |
| **MCP Discord Plugin** | In-process MCP tools | Tool provider for Claude session | No |

---

## Architecture Overview

```
Discord User
     |
     v
Discord Thread / @mention
     |
     v
+----------------------------------+
| discord-claude-code-bot          |
| (Node.js, discord.js)            |
| - SQLite session persistence     |
| - Stale session auto-cleanup     |
| - Duplicate instance prevention  |
+----------------------------------+
     |
     v
spawns: claude -p --resume <uuid>
     |
     v
+----------------------------------+
| Claude Code CLI Session          |
| - Executes commands              |
| - Writes to bridge files         |
| - Spawns sub-agents (Lisa/Nyx)   |
+----------------------------------+
     |
     v
+----------------------------------+
| Bridge / Coordination Layer      |
| - BRIDGE_LISA.md                 |
| - Telegram INBOX/OUTBOX          |
| - GitHub Live Chat (optional)    |
+----------------------------------+
     |
     v
Lisa / Nyx / Kael / William (OpenClaw agents)
```

**Session Persistence:**
- Each Discord thread maps to a unique Claude Code session UUID
- Mapping stored in SQLite (`threads.db`)
- Session files stored in `~/.claude/projects/<cwd>/`
- After system restart, stale mappings are auto-detected and cleaned

---

## The Agent Team

| Agent | Platform | Role | Discord Identity |
|-------|----------|------|-----------------|
| **Claude (Ubuntu)** | Claude Code CLI + Discord | Team Lead, orchestrator | `Claude_ubuntu#9135` |
| **Lisa** | OpenClaw / Discord | Executor, researcher | `Lisa#7140` |
| **Nyx** | OpenClaw / Discord | Growth, marketing | `Nyx_Growth#1299` |
| **Kael** | OpenClaw / Discord | Executor | `Kael_Executor#8338` |
| **William** | OpenClaw / Discord | Coder, developer | `William#xxxx` |

**Communication Patterns:**
- **Direct:** User @mentions Claude in Discord thread
- **Indirect:** Claude writes to bridge file → Lisa reads and acts
- **Broadcast:** Coordinator cron fetches all Discord messages, routes to agent INBOXes
- **Live Chat:** GitHub-based persistent chat for long-form collaboration

---

## Documentation Index

| Doc | What You'll Learn |
|-----|-------------------|
| [docs/01-architecture.md](docs/01-architecture.md) | Full system architecture, data flow, component interactions |
| [docs/02-setup-guide.md](docs/02-setup-guide.md) | Step-by-step setup from zero to running bot |
| [docs/03-lessons-learned.md](docs/03-lessons-learned.md) | 10+ hard-won lessons from production incidents |
| [docs/04-swot-analysis.md](docs/04-swot-analysis.md) | Strengths, Weaknesses, Opportunities, Threats |
| [docs/05-troubleshooting.md](docs/05-troubleshooting.md) | Every known issue and exact fix procedure |
| [docs/06-multi-agent-coordination.md](docs/06-multi-agent-coordination.md) | How Lisa/Nyx/Kael bots are configured and isolated |
| [docs/07-stale-session-detection.md](docs/07-stale-session-detection.md) | Technical deep dive: auto-cleanup implementation |
| [docs/08-bridge-system.md](docs/08-bridge-system.md) | Bridge files, protocols, and failure modes |
| [docs/09-health-monitoring.md](docs/09-health-monitoring.md) | Cron jobs, health checks, and monitoring stack |

---

## Repository Structure

```
claude_discord/
├── README.md                          # This file
├── docs/                              # Comprehensive documentation
│   ├── 01-architecture.md
│   ├── 02-setup-guide.md
│   ├── 03-lessons-learned.md
│   ├── 04-swot-analysis.md
│   ├── 05-troubleshooting.md
│   ├── 06-multi-agent-coordination.md
│   ├── 07-stale-session-detection.md
│   ├── 08-bridge-system.md
│   └── 09-health-monitoring.md
├── scripts/                           # Utility scripts (templates)
│   ├── start-bot.sh.example
│   ├── health-check.sh.example
│   └── kill-duplicates.sh
└── .github/                           # (Optional) workflows
```

> **Note:** This repository contains documentation and templates only. The actual bot source code lives at [fredchu/discord-claude-code-bot](https://github.com/fredchu/discord-claude-code-bot).

---

## Key Principles

1. **Systemd Only** — The bot is managed exclusively by systemd. Manual starts create duplicates.
2. **Kill Duplicates, Preserve One** — When fixing duplicate responses, kill extra instances but leave one running.
3. **Auto-Heal Sessions** — Stale session mappings are detected and cleaned automatically on startup and per-message.
4. **Bridge Protocol** — Agents must use canonical bridge file paths. Wrong paths cause silent message loss.
5. **Token Hygiene** — Session files are cleared proactively before hitting 60k token limits.
6. **One Instance Per Bot** — Each agent (Lisa, Nyx, Kael) has its own isolated database and systemd service.

---

## Safety & Secrets Policy

This repository intentionally **excludes** the following:

- Discord bot tokens
- API keys (Claude, OpenAI, etc.)
- Wallet addresses or cryptocurrency keys
- File paths to secret storage
- Specific guild/channel IDs where sensitive
- Session file contents containing conversation data

All secrets are managed via:
- `.env` files (not committed)
- Systemd environment files
- `~/.openclaw/secrets/` directory (outside repo)

**To use these docs:** Replace all `<PLACEHOLDER>` values with your own secrets.

---

## License

Documentation is provided as-is for educational and operational reference. Bot source code remains under its original license at [fredchu/discord-claude-code-bot](https://github.com/fredchu/discord-claude-code-bot).
