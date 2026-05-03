# Setup Guide

> From zero to a running Claude Discord bot.

---

## Prerequisites

- Linux server or VM (Ubuntu 22.04+ recommended)
- Node.js >= 18
- Git
- Claude Code CLI installed (`claude` command available)
- Discord account with Developer Portal access

---

## Step 1: Clone This Repository

```bash
git clone https://github.com/wilsonhoe/claude_discord.git
cd claude_discord

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
DISCORD_TOKEN=<your-discord-bot-token>

# Optional but recommended
DEFAULT_CWD=/home/youruser/projects       # Default working directory
CLAUDE_BIN=claude                           # Claude CLI command
GUILD_ID=<your-discord-server-id>           # Restrict slash commands to guild
```

**Security:**
- Never commit `.env`
- Add `.env` to `.gitignore` (already done)
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
WorkingDirectory=/home/youruser/claude_discord
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

## Step 7: Health Monitoring Setup

### 7.1 Health Check Script

The `scripts/` directory contains:

```bash
# duplicate-check.sh — Check for duplicate bot instances
# kill-stuck-sessions.sh — Kill stuck claude -p processes
```

Install them:

```bash
chmod +x scripts/*.sh
sudo cp scripts/duplicate-check.sh /usr/local/bin/
sudo cp scripts/kill-stuck-sessions.sh /usr/local/bin/
```

### 7.2 Cron Schedule

```bash
# Edit crontab
crontab -e

# Add:
*/15 * * * * /usr/local/bin/kill-stuck-sessions.sh
*/5 * * * * /usr/local/bin/duplicate-check.sh
0 * * * * * systemctl --user status discord-claude-ubuntu.service --no-pager >> /tmp/bot-status.log
```

---

## Step 8: Verification Checklist

- [ ] Bot responds to @mentions in threads
- [ ] Single instance running (check `ps aux`)
- [ ] Systemd service active (`systemctl --user status`)
- [ ] SQLite database created and writable
- [ ] Session files created in `~/.claude/projects/`
- [ ] Slash commands registered (`/help`, `/new`)
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
