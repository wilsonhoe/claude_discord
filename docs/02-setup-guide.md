# Setup Guide

> From zero to a running Claude Discord bot with multi-agent coordination.

---

## Prerequisites

- Linux server or VM (Ubuntu 22.04+ recommended)
- Node.js >= 18
- Git
- Claude Code CLI installed (`claude` command available)
- Discord account with Developer Portal access

---

## Step 1: Bot Source Code

```bash
# Clone the bot
git clone https://github.com/fredchu/discord-claude-code-bot.git
cd discord-claude-code-bot

# Install dependencies
npm install
```

---

## Step 2: Discord Application Setup

1. Go to [Discord Developer Portal](https://discord.com/developers/applications)
2. Create New Application → Name it (e.g., "Claude Ubuntu")
3. Navigate to **Bot** tab:
   - Click "Reset Token" → Copy token (save securely)
   - Enable **MESSAGE CONTENT INTENT** (Critical!)
   - Disable "Public Bot" if this is private
4. Navigate to **OAuth2 → URL Generator**:
   - Scopes: `bot`, `applications.commands`
   - Bot Permissions:
     - Send Messages
     - Read Message History
     - Use Slash Commands
     - Create Public Threads
     - Send Messages in Threads
     - Embed Links
     - Attach Files
     - Add Reactions
   - Copy generated URL and open in browser to invite bot to your server

---

## Step 3: Environment Configuration

Create `.env` in the bot root:

```bash
# Required
DISCORD_BOT_TOKEN=<your-discord-bot-token>

# Optional but recommended
CLAUDE_HOME=/home/youruser/.claude
THREADS_DB_PATH=threads.db
AGENT_SYSTEM_PROMPT="You are Claude, an AI assistant running on Ubuntu. You help users with software engineering tasks."
```

**Security:**
- Never commit `.env`
- Add `.env` to `.gitignore`
- Store backup tokens in a password manager

---

## Step 4: Systemd Service Setup

Create `~/.config/systemd/user/discord-claude-ubuntu.service`:

```ini
[Unit]
Description=Claude Discord Bot
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/youruser/discord-claude-code-bot
ExecStart=node --env-file=.env --import=tsx src/index.ts
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

**Important:** Use `Restart=on-failure`, NOT `Restart=always`. See [docs/03-lessons-learned.md](docs/03-lessons-learned.md).

Enable and start:

```bash
systemctl --user daemon-reload
systemctl --user enable discord-claude-ubuntu.service
systemctl --user start discord-claude-ubuntu.service
systemctl --user status discord-claude-ubuntu.service --no-pager
```

---

## Step 5: Verify Single Instance

```bash
# Should show exactly 1 process
ps aux | grep "tsx src/index" | grep -v grep | wc -l

# View logs
journalctl --user -u discord-claude-ubuntu.service -f
```

If you see more than 1 process, kill duplicates:

```bash
pkill -9 -f "tsx src/index.ts"
systemctl --user restart discord-claude-ubuntu.service
```

---

## Step 6: Discord Test

1. Create a thread in your Discord server
2. @mention the bot: `@Claude_ubuntu hello`
3. You should see:
   - "⏳ *Thinking...*" indicator
   - Response from Claude within 10-30 seconds

---

## Step 7: Multi-Agent Setup (Lisa, Nyx, Kael)

### 7.1 Create Additional Discord Applications

Repeat Step 2 for each agent:
- Lisa#7140
- Nyx_Growth#1299
- Kael_Executor#8338

### 7.2 Code Changes

The bot codebase supports multi-agent deployment with two changes to `src/index.ts`:

1. **THREADS_DB_PATH** — Override default `threads.db`:
   ```typescript
   const dbPath = process.env.THREADS_DB_PATH || "threads.db";
   ```

2. **AGENT_SYSTEM_PROMPT** — Override default system prompt:
   ```typescript
   const systemPrompt = process.env.AGENT_SYSTEM_PROMPT || defaultPrompt;
   ```

### 7.3 Per-Agent Environment Files

Create separate env files:

**lisa.env:**
```bash
DISCORD_BOT_TOKEN=<lisa-token>
THREADS_DB_PATH=data/lisa-threads.db
AGENT_SYSTEM_PROMPT="You are Lisa, an AI executor agent. Your role is to carry out tasks assigned by Claude. You are efficient, thorough, and report results clearly."
```

**nyx.env:**
```bash
DISCORD_BOT_TOKEN=<nyx-token>
THREADS_DB_PATH=data/nyx-threads.db
AGENT_SYSTEM_PROMPT="You are Nyx, an AI growth agent. Your role is marketing, outreach, and community engagement."
```

**kael.env:**
```bash
DISCORD_BOT_TOKEN=<kael-token>
THREADS_DB_PATH=data/kael-threads.db
AGENT_SYSTEM_PROMPT="You are Kael, an AI executor agent. Your role is to execute technical tasks and provide detailed reports."
```

### 7.4 Start Script

Create `start-agent.sh`:

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

### 7.5 Per-Agent Systemd Services

Create `~/.config/systemd/user/discord-lisa.service`:

```ini
[Unit]
Description=Lisa Discord Bot
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/youruser/discord-claude-code-bot
ExecStart=/home/youruser/discord-claude-code-bot/start-agent.sh lisa
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

Repeat for `discord-nyx.service` and `discord-kael.service`.

Enable all:

```bash
systemctl --user daemon-reload
systemctl --user enable discord-lisa.service discord-nyx.service discord-kael.service
systemctl --user start discord-lisa.service
systemctl --user start discord-nyx.service
systemctl --user start discord-kael.service
```

---

## Step 8: Bridge Setup (Agent Communication)

### 8.1 Create Bridge Directories

```bash
mkdir -p ~/.openclaw/workspace-lisa
mkdir -p ~/.openclaw/workspace-nyx
mkdir -p ~/.openclaw/workspace-kael
mkdir -p ~/.openclaw/workspace-william
```

### 8.2 Bridge Protocol Files

Create canonical bridge files:

```bash
# For Lisa
cat > ~/.openclaw/workspace-lisa/BRIDGE_LISA.md << 'EOF'
# BRIDGE: Claude <-> Lisa
# Protocol: Append-only markdown. Each message = new section.
# ---
EOF

# For other agents, repeat pattern
```

### 8.3 Bridge Monitor Configuration

Configure bridge monitor cron or systemd timer to watch for file changes:

```bash
# Example: Check bridge every 5 minutes
*/5 * * * * /home/youruser/.openclaw/scripts/bridge-monitor.sh lisa
```

---

## Step 9: Health Monitoring Setup

### 9.1 Health Check Script

Create `scripts/session-health-check.sh`:

```bash
#!/bin/bash
# Check for stuck claude -p processes
STUCK=$(ps aux | grep "claude -p" | grep -v grep | awk '{if ($3 > 90.0) print $2}')
for PID in $STUCK; do
  RUNTIME=$(ps -o etime= -p $PID | tr -d ' ')
  # Kill if running > 10 minutes
  if [[ "$RUNTIME" =~ ^[0-9]+-[0-9]+:[0-9]+:[0-9]+$ ]] || [[ "$RUNTIME" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    echo "Killing stuck process $PID (CPU > 90%, runtime: $RUNTIME)"
    kill -9 $PID
  fi
done
```

### 9.2 Duplicate Detection

```bash
#!/bin/bash
# Check for duplicate bot instances
COUNT=$(ps aux | grep "tsx src/index" | grep -v grep | wc -l)
if [ "$COUNT" -gt 1 ]; then
  echo "WARNING: $COUNT bot instances detected. Killing duplicates..."
  pkill -9 -f "tsx src/index.ts"
  systemctl --user restart discord-claude-ubuntu.service
fi
```

### 9.3 Cron Schedule

```bash
# Edit crontab
crontab -e

# Add:
*/15 * * * * /home/youruser/discord-claude-code-bot/scripts/session-health-check.sh
*/5 * * * * /home/youruser/discord-claude-code-bot/scripts/duplicate-check.sh
0 * * * * * systemctl --user status discord-claude-ubuntu.service --no-pager >> /tmp/bot-status.log
```

---

## Step 10: Verification Checklist

- [ ] Bot responds to @mentions in threads
- [ ] Single instance running (check `ps aux`)
- [ ] Systemd service active (`systemctl --user status`)
- [ ] SQLite database created and writable
- [ ] Session files created in `~/.claude/projects/`
- [ ] Slash commands registered (`/help`, `/new`)
- [ ] Lisa/Nyx/Kael bots start independently
- [ ] Bridge files are writable by Claude
- [ ] Health check scripts executable
- [ ] No duplicate processes after restart

---

## Common Setup Mistakes

| Mistake | Symptom | Fix |
|---------|---------|-----|
| MESSAGE CONTENT INTENT disabled | Bot doesn't see @mentions | Enable in Discord Developer Portal |
| Manual `npm start` instead of systemd | Duplicate responses | Stop manual process, use `systemctl` |
| Wrong `.env` file | "Invalid token" error | Verify token copied correctly |
| Missing `tsx` | "Cannot find module" | Run `npm install` |
| SQLite not writable | "database is locked" | Check file permissions on `threads.db` |
| Bridge wrong path | Messages silently lost | Use canonical `~/.openclaw/workspace-<agent>/` |
