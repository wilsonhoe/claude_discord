# Claude Discord Bot

> A Discord bot that integrates Claude Code CLI, allowing you to interact with Claude directly from Discord threads.
>
> **Repository:** https://github.com/wilsonhoe/claude_discord
> **Upstream:** https://github.com/fredchu/discord-claude-code-bot
> **Last Updated:** 2026-05-03

---

## Table of Contents

- [Quick Start](#quick-start)
- [What Is This](#what-is-this)
- [Features](#features)
- [Documentation Index](#documentation-index)
- [Repository Structure](#repository-structure)
- [Safety & Secrets Policy](#safety--secrets-policy)

---

## Quick Start

```bash
# 1. Clone this repo
git clone https://github.com/wilsonhoe/claude_discord.git
cd claude_discord

# 2. Install dependencies
npm install

# 3. Configure environment
cp .env.example .env
# Edit .env: add your DISCORD_TOKEN, DEFAULT_CWD, etc.

# 4. Start the bot via systemd (NEVER manually)
systemctl --user start discord-claude-ubuntu.service

# 5. Verify single instance
ps aux | grep "tsx src/index" | grep -v grep | wc -l   # should be 1

# 6. Health check
systemctl --user status discord-claude-ubuntu.service --no-pager
```

**Critical Rule:** Always use `systemctl` to manage the bot. Never `npm start` or `nohup` directly — this creates duplicate instances and duplicate Discord responses. See [docs/03-lessons-learned.md](docs/03-lessons-learned.md).

---

## What Is This

This repository contains:

1. **Complete source code** of the Discord bot (forked from [fredchu/discord-claude-code-bot](https://github.com/fredchu/discord-claude-code-bot))
2. **Hardened modifications** — stale session auto-detection, duplicate prevention
3. **Production documentation** — every issue encountered and how to fix it

**Two distinct Discord systems cooperate:**

| System | Type | Role | Auto-Responds |
|--------|------|------|--------------|
| **discord-claude-code-bot** | Standalone Node.js bot | User-facing bot | Yes |
| **MCP Discord Plugin** | In-process MCP tools | Tool provider for Claude session | No |

---

## Features

- **Thread-based sessions** — Each Discord thread maps to a persistent Claude session
- **SQLite persistence** — Thread-to-session mappings survive bot restarts
- **Stale session auto-detection** — Automatically recovers from "No conversation found" errors
- **Streaming responses** — Live "thinking..." indicators while Claude works
- **Attachment support** — Upload files to Discord, Claude reads them
- **Slash commands** — `/help`, `/new`, `/model`, `/cd`, `/stop`, `/sessions`, `/resume-local`, `/handback`
- **Local session resume** — Hand off between terminal and Discord seamlessly
- **Message chunking** — Long responses split into Discord-friendly chunks
- **Button interactions** — AskUserQuestion rendered as Discord buttons

---

## Documentation Index

| Doc | What You'll Learn |
|-----|-------------------|
| [docs/01-architecture.md](docs/01-architecture.md) | System architecture, data flow, component interactions |
| [docs/02-setup-guide.md](docs/02-setup-guide.md) | Step-by-step setup from zero to running bot |
| [docs/03-lessons-learned.md](docs/03-lessons-learned.md) | Hard-won lessons from production incidents |
| [docs/04-swot-analysis.md](docs/04-swot-analysis.md) | Strengths, Weaknesses, Opportunities, Threats |
| [docs/05-troubleshooting.md](docs/05-troubleshooting.md) | Every known issue and exact fix procedure |
| [docs/07-stale-session-detection.md](docs/07-stale-session-detection.md) | Technical deep dive: auto-cleanup implementation |
| [docs/09-health-monitoring.md](docs/09-health-monitoring.md) | Cron jobs, health checks, and monitoring stack |
| [docs/10-auto-sync.md](docs/10-auto-sync.md) | Auto-sync to GitHub with secret sanitization |

---

## Repository Structure

```
claude_discord/
├── README.md              # This file
├── CHANGELOG.md           # Upstream changelog
├── LICENSE                # MIT License (upstream)
├── package.json           # Dependencies
├── tsconfig.json          # TypeScript config
├── .env.example           # Environment template
├── .gitignore             # Git ignore rules
├── src/
│   └── index.ts           # Main bot source code
├── docs/                  # Documentation
│   ├── 01-architecture.md
│   ├── 02-setup-guide.md
│   ├── 03-lessons-learned.md
│   ├── 04-swot-analysis.md
│   ├── 05-troubleshooting.md
│   ├── 07-stale-session-detection.md
│   └── 09-health-monitoring.md
├── scripts/               # Utility scripts
│   ├── duplicate-check.sh
│   ├── kill-stuck-sessions.sh
│   ├── start-bot.sh.example
│   ├── github-auto-push.sh      # Single-repo auto-push
│   ├── multi-repo-sync.sh       # Multi-repo auto-push (all wilsonhoe repos)
│   ├── secret-sanitizer.sh      # Blocks secrets in pushes
│   └── webhook-trigger.sh       # File watcher auto-push
├── systemd/               # Systemd units
│   ├── github-auto-push.timer   # Single-repo weekly timer
│   ├── github-auto-push.service # Single-repo weekly service
│   ├── multi-repo-sync.timer    # Multi-repo weekly timer
│   ├── multi-repo-sync.service  # Multi-repo weekly service
│   └── webhook-trigger.service  # File watcher service
└── docs/                  # Documentation
    ├── 01-architecture.md
    ├── 02-setup-guide.md
    ├── 03-lessons-learned.md
    ├── 04-swot-analysis.md
    ├── 05-troubleshooting.md
    ├── 07-stale-session-detection.md
    ├── 09-health-monitoring.md
    └── 10-auto-sync.md
```

---

## Key Principles

1. **Systemd Only** — The bot is managed exclusively by systemd. Manual starts create duplicates.
2. **Kill Duplicates, Preserve One** — When fixing duplicate responses, kill extra instances but leave one running.
3. **Auto-Heal Sessions** — Stale session mappings are detected and cleaned automatically on startup and per-message.
4. **Token Hygiene** — Session files are cleared proactively before hitting 60k token limits.

---

## Safety & Secrets Policy

This repository intentionally **excludes** the following:

- Discord bot tokens
- Claude API keys
- File paths to secret storage
- Specific guild/channel IDs where sensitive
- Session file contents containing conversation data

All secrets are managed via:
- `.env` file (not committed — see `.env.example` for template)
- Systemd environment files

**To use this bot:** Copy `.env.example` to `.env` and fill in your own secrets.

---

## License

Bot source code remains under its original MIT license at [fredchu/discord-claude-code-bot](https://github.com/fredchu/discord-claude-code-bot).
Documentation is provided as-is for educational and operational reference.
