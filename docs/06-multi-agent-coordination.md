# Multi-Agent Coordination

> How Lisa, Nyx, Kael, and William Discord bots are configured, isolated, and orchestrated.

---

## Agent Overview

| Agent | Discord Handle | Role | Primary Platform |
|-------|---------------|------|----------------|
| **Claude (Ubuntu)** | `Claude_ubuntu#9135` | Team Lead, orchestrator, primary interface | Claude Code CLI + Discord |
| **Lisa** | `Lisa#7140` | Executor, researcher, bounty hunter | OpenClaw + Discord |
| **Nyx** | `Nyx_Growth#1299` | Growth, marketing, outreach | OpenClaw + Discord |
| **Kael** | `Kael_Executor#8338` | Executor, technical tasks | OpenClaw + Discord |
| **William** | `William#xxxx` | Coder, developer | OpenClaw + Discord |

---

## Architecture: Single Codebase, Multiple Identities

All agent bots run from the **same codebase** with two critical per-agent overrides:

### 1. THREADS_DB_PATH

Each agent has its own SQLite database to prevent session collisions:

```
data/
├── claude-threads.db     # Claude_ubuntu
├── lisa-threads.db       # Lisa
├── nyx-threads.db        # Nyx
├── kael-threads.db       # Kael
└── william-threads.db    # William
```

**Why isolation matters:**
- If all agents shared one database, thread IDs would collide
- Session mappings would overwrite each other
- Agent A could resume Agent B's session (security risk)

### 2. AGENT_SYSTEM_PROMPT

Each agent has a distinct identity and role:

**Claude:**
```
You are Claude, an AI assistant running on Ubuntu. You are the team lead
for a multi-agent system. You coordinate Lisa, Nyx, and Kael. You help
users with software engineering tasks and delegate execution to your team.
```

**Lisa:**
```
You are Lisa, an AI executor agent. Your role is to carry out tasks
assigned by Claude. You are efficient, thorough, and report results
clearly. You specialize in research, data gathering, and bounty hunting.
```

**Nyx:**
```
You are Nyx, an AI growth agent. Your role is marketing, outreach,
and community engagement. You help expand the team's presence and find
new opportunities.
```

**Kael:**
```
You are Kael, an AI executor agent. Your role is to execute technical
tasks and provide detailed reports. You are precise and methodical.
```

---

## File Structure

```
discord-claude-code-bot/
├── src/
│   ├── index.ts           # Main entry (reads env vars)
│   ├── threads.ts         # Database operations
│   ├── commands.ts        # Slash commands
│   └── types.ts           # TypeScript types
├── data/                  # Per-agent databases (created at runtime)
├── .env                   # Claude bot credentials
├── lisa.env               # Lisa bot credentials
├── nyx.env                # Nyx bot credentials
├── kael.env               # Kael bot credentials
├── start-agent.sh         # Generic agent starter
└── package.json
```

---

## Starting Agents

### Individual Start

```bash
cd ~/discord-claude-code-bot

# Start specific agent
./start-agent.sh lisa
./start-agent.sh nyx
./start-agent.sh kael
```

**start-agent.sh:**
```bash
#!/bin/bash
AGENT=$1
if [ -z "$AGENT" ]; then
  echo "Usage: ./start-agent.sh <agent-name>"
  exit 1
fi

ENV_FILE="${AGENT}.env"
if [ ! -f "$ENV_FILE" ]; then
  echo "Error: $ENV_FILE not found"
  exit 1
fi

mkdir -p data
node --env-file="$ENV_FILE" --import=tsx src/index.ts
```

### Systemd Services

**discord-lisa.service:**
```ini
[Unit]
Description=Lisa Discord Bot
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/user/discord-claude-code-bot
ExecStart=/home/user/discord-claude-code-bot/start-agent.sh lisa
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

**Enable all:**
```bash
systemctl --user daemon-reload
systemctl --user enable discord-lisa.service
systemctl --user enable discord-nyx.service
systemctl --user enable discord-kael.service

systemctl --user start discord-lisa.service
systemctl --user start discord-nyx.service
systemctl --user start discord-kael.service
```

---

## Orchestrator Configuration

The orchestrator tracks all agents and their status:

```json
{
  "agents": [
    {
      "name": "claude",
      "discord_handle": "Claude_ubuntu#9135",
      "service": "discord-claude-ubuntu.service",
      "db_path": "data/claude-threads.db",
      "role": "team_lead"
    },
    {
      "name": "lisa",
      "discord_handle": "Lisa#7140",
      "service": "discord-lisa.service",
      "db_path": "data/lisa-threads.db",
      "role": "executor"
    },
    {
      "name": "nyx",
      "discord_handle": "Nyx_Growth#1299",
      "service": "discord-nyx.service",
      "db_path": "data/nyx-threads.db",
      "role": "growth"
    },
    {
      "name": "kael",
      "discord_handle": "Kael_Executor#8338",
      "service": "discord-kael.service",
      "db_path": "data/kael-threads.db",
      "role": "executor"
    }
  ]
}
```

---

## Communication Patterns

### Pattern 1: Direct Delegation (Bridge)

```
User -> Claude: "Lisa, check GitHub bounties"
Claude -> BRIDGE_LISA.md: "Mission: Check GitHub bounties"
Lisa (bridge monitor) -> reads bridge
Lisa -> executes task
Lisa -> BRIDGE_LISA.md: "Result: 103 bounties found..."
Claude -> reads bridge
Claude -> Discord: "Lisa found 103 bounties..."
```

### Pattern 2: Broadcast (Coordinator Cron)

```
Discord #command_center -> New message with [APPROVED] tag
discord_coordinator.py -> fetches message
-> routes to Kael's INBOX (kael-inbox.md)
Kael -> reads INBOX
Kael -> executes approved task
Kael -> OUTBOX: "Task complete: ..."
```

### Pattern 3: Direct Agent Chat

```
User -> Discord thread with Lisa
Lisa bot -> spawns Lisa agent session
Lisa agent -> responds directly in thread
```

### Pattern 4: GitHub Live Chat

```
Claude -> chat/LIVE-CHAT.md: "Discussion about architecture..."
git commit && git push
Lisa (cron sync) -> git pull
Lisa -> reads chat/LIVE-CHAT.md
Lisa -> replies in chat/LIVE-CHAT.md
git commit && git push
Claude (cron sync) -> git pull
```

---

## Isolation Strategy

### Process Isolation
- Each agent runs as separate Node.js process
- Separate systemd services
- Independent crash domains (one agent down doesn't affect others)

### Data Isolation
- Separate SQLite databases per agent
- Separate session file directories (if using different cwd)
- Separate `.env` files for credentials

### Communication Isolation
- Each agent has its own bridge file
- INBOX/OUTBOX files are per-agent
- No shared memory or global state

---

## Troubleshooting Multi-Agent Issues

### Issue: Agents Responding as Wrong Identity

**Symptom:** Lisa responds with Claude's personality, or vice versa.

**Cause:** Wrong `AGENT_SYSTEM_PROMPT` loaded, or shared database.

**Fix:**
```bash
# Verify env file
grep AGENT_SYSTEM_PROMPT lisa.env

# Verify database isolation
ls -la data/lisa-threads.db
ls -la data/claude-threads.db
# Should be different files

# Restart specific agent
systemctl --user restart discord-lisa.service
```

### Issue: Agent Sessions Interfering

**Symptom:** Claude sees Lisa's conversation context, or vice versa.

**Cause:** Same `cwd` or same session UUID.

**Fix:**
```bash
# Ensure different working directories
# Claude: --cwd /home/user/projects/claude
# Lisa: --cwd /home/user/projects/lisa

# Clear and rebuild databases
rm data/*.db
systemctl --user restart discord-claude-ubuntu.service
systemctl --user restart discord-lisa.service
```

### Issue: Agent Bot Won't Start

**Symptom:** `systemctl --user start discord-lisa.service` fails.

**Diagnosis:**
```bash
journalctl --user -u discord-lisa.service -n 50 --no-pager

# Check if token is valid
grep DISCORD_BOT_TOKEN lisa.env
# Verify token in Discord Developer Portal
```

**Fix:**
- Verify `.env` file exists and is readable
- Check that `data/` directory is writable
- Ensure token is for correct bot application (Lisa, not Claude)

---

## Scaling to More Agents

To add a new agent (e.g., "Zara"):

1. **Create Discord application** for Zara
2. **Create `zara.env`** with new token and prompt
3. **Update `start-agent.sh`** (no change needed — it's generic)
4. **Create `discord-zara.service`** systemd file
5. **Create bridge file:** `~/.openclaw/workspace-zara/BRIDGE_ZARA.md`
6. **Update orchestrator.json** with Zara entry
7. **Enable and start:**
   ```bash
   systemctl --user daemon-reload
   systemctl --user enable discord-zara.service
   systemctl --user start discord-zara.service
   ```

Total setup time: ~10 minutes per agent.
