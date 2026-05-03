# Troubleshooting Guide

> Every known issue with exact symptoms, root causes, and step-by-step fixes.

---

## Issue 1: Duplicate Responses to Every Message

### Symptoms
- User sends ONE message
- Bot replies 2-10 times with identical or similar responses
- Multiple "⏳ *Thinking...*" indicators appear

### Root Cause
Multiple instances of `discord-claude-code-bot` running simultaneously.

### Diagnosis
```bash
# Count bot instances
ps aux | grep "tsx src/index" | grep -v grep | wc -l

# Should be 1. If >1, you have duplicates.

# See all instances with details
ps aux | grep "tsx src/index" | grep -v grep

# Check systemd status
systemctl --user status discord-claude-ubuntu.service --no-pager

# Check for nohup/manual processes
ps aux | grep "nohup" | grep -v grep
ps aux | grep "node.*discord" | grep -v grep
```

### Fix (Exact Steps)

**Step 1: Kill ALL instances**
```bash
pkill -9 -f "tsx src/index.ts"
sleep 2
```

**Step 2: Verify none remain**
```bash
ps aux | grep "tsx src/index" | grep -v grep
# Should output nothing
```

**Step 3: Restart via systemd ONLY**
```bash
systemctl --user restart discord-claude-ubuntu.service
sleep 3
```

**Step 4: Verify single instance**
```bash
ps aux | grep "tsx src/index" | grep -v grep | wc -l
# Should output: 1
```

**Step 5: Check systemd status**
```bash
systemctl --user status discord-claude-ubuntu.service --no-pager
```

### Prevention
- Never use `npm start`, `nohup`, or manual node execution
- Always check process count before reporting issues
- Fix health check scripts to match actual process name

---

## Issue 2: Bot Not Responding to @mentions

### Symptoms
- @mention in thread produces no response
- Bot shows as online but silent
- No "⏳ *Thinking...*" indicator

### Diagnosis
```bash
# Check if bot process is running
ps aux | grep "tsx src/index" | grep -v grep

# Check systemd status
systemctl --user status discord-claude-ubuntu.service --no-pager

# Check logs for errors
journalctl --user -u discord-claude-ubuntu.service -n 50 --no-pager

# Verify Discord token validity
# (Try regenerating token in Developer Portal if suspicious)
```

### Common Causes & Fixes

**A. MESSAGE CONTENT INTENT disabled**
```
Symptom: Bot sees thread creation but not message content
Fix: Discord Developer Portal → Bot → MESSAGE CONTENT INTENT → Enable
```

**B. Invalid or expired token**
```
Symptom: "Authentication failed" in logs
Fix: Regenerate token in Developer Portal, update .env, restart
```

**C. Bot not in thread / wrong channel**
```
Symptom: No events logged for the thread
Fix: Ensure bot has "View Channel" and "Send Messages" permissions
```

**D. Bot crashed but systemd didn't restart**
```
Symptom: Process missing from ps aux
Fix: systemctl --user restart discord-claude-ubuntu.service
```

---

## Issue 3: "Previous task still running. Use /stop first."

### Symptoms
- User sends message in thread
- Bot responds with: "Previous task still running. Use /stop first."
- Previous `claude -p` process is stuck

### Diagnosis
```bash
# Find all claude -p processes
ps aux | grep "claude -p" | grep -v grep

# Check CPU and runtime
ps aux | grep "claude -p" | grep -v grep | awk '{print $2, $3, $10}'
# Columns: PID, CPU%, START_TIME
```

### Fix

**Option 1: Use /stop slash command**
```
User types: /stop
Bot kills the running claude -p process
```

**Option 2: Manual kill**
```bash
# Identify stuck PID
STUCK_PID=$(ps aux | grep "claude -p" | grep -v grep | awk '{print $2}')

# Graceful kill
kill $STUCK_PID
sleep 3

# Check if still running
ps -p $STUCK_PID > /dev/null 2>&1 && kill -9 $STUCK_PID

# Verify
ps aux | grep "claude -p" | grep -v grep
```

**Option 3: Automated health check**
Use `scripts/kill-stuck-sessions.sh` via cron every 15 minutes.

### Prevention
- Implement `/stop` command in your bot (already included)
- Add health check cron (every 15 min)
- Monitor for processes running >10 minutes

---

## Issue 4: "No conversation found with session ID: xxx"

### Symptoms
- Bot receives message in existing thread
- Error in logs: "No conversation found with session ID: ..."
- Bot may create a new session but user loses context

### Root Cause
Session file was deleted or lost (system restart, tmpfs, manual cleanup), but thread-to-session mapping still exists in SQLite.

### Fix (Manual)
```bash
# Option 1: Clear specific thread mapping
sqlite3 threads.db "DELETE FROM threads WHERE threadId = '<thread-id>';"

# Option 2: Clear all mappings (nuclear)
sqlite3 threads.db "DELETE FROM threads;"

# Restart bot
systemctl --user restart discord-claude-ubuntu.service
```

### Fix (Automatic — Included in this repo)
This hardened bot includes stale session detection:
- Bot automatically detects missing session file
- Deletes stale mapping
- Creates fresh session
- User gets new session transparently

See [docs/07-stale-session-detection.md](docs/07-stale-session-detection.md) for technical details.

### Prevention
- Use this hardened version of the bot
- Store session files on persistent storage (not tmpfs)

---

## Issue 5: Bot Stopped Responding Entirely

### Symptoms
- Bot not replying in Discord
- No error messages visible
- Process may or may not be running

### Diagnosis
```bash
# Check bot process
ps aux | grep "tsx src/index" | grep -v grep

# Check session sizes
du -sh ~/.claude/projects/*/*.jsonl 2>/dev/null | sort -rh | head -5

# Check logs for errors
journalctl --user -u discord-claude-ubuntu.service -n 100 --no-pager
```

### Common Causes & Fixes

**A. Session token limit (60k/60k)**
```bash
# Clear session files
rm ~/.claude/projects/*/*.jsonl
rm ~/.claude/projects/*/*.lock

# Clear thread database
rm threads.db

# Restart bot
systemctl --user restart discord-claude-ubuntu.service
```

**B. Context overflow (huge session file)**
```bash
# Find bloated session
find ~/.claude/projects -name "*.jsonl" -size +100k

# Truncate to minimal state
# (Backup first, then keep only header + system message)
```

**C. Bot process crashed**
```bash
systemctl --user restart discord-claude-ubuntu.service
```

---

## Issue 6: Systemd Service Fails to Start

### Symptoms
```bash
systemctl --user start discord-claude-ubuntu.service
# Returns: Failed to start ...
```

### Diagnosis
```bash
# Check status for error details
systemctl --user status discord-claude-ubuntu.service --no-pager

# Check journal logs
journalctl --user -u discord-claude-ubuntu.service -n 50 --no-pager

# Test manual execution (for debugging only)
cd ~/claude_discord && node --env-file=.env --import=tsx src/index.ts
# (Ctrl+C after verifying error)
```

### Common Causes & Fixes

**A. .env file missing or invalid**
```bash
# Verify .env exists
ls -la ~/claude_discord/.env

# Verify token format
grep DISCORD_TOKEN ~/claude_discord/.env
# Should show: DISCORD_TOKEN=<64-char string>
```

**B. Working directory incorrect in service file**
```bash
# Check WorkingDirectory in service file
grep WorkingDirectory ~/.config/systemd/user/discord-claude-ubuntu.service
# Should match actual bot location
```

**C. Permission denied on database**
```bash
# Fix ownership
chmod 600 ~/claude_discord/threads.db
# Or delete to recreate
rm ~/claude_discord/threads.db
```

**D. Node.js or tsx not found**
```bash
# Verify Node.js version
node --version  # Should be >=18

# Verify tsx
npx tsx --version

# If missing: npm install -g tsx
```

---

## Issue 7: Slash Commands Not Appearing

### Symptoms
- Type `/` in Discord, bot commands don't show
- Commands were working before but disappeared

### Fix
```bash
# Re-register slash commands
# This happens automatically on bot startup
# Just restart the bot:
systemctl --user restart discord-claude-ubuntu.service

# Or force re-registration by deleting bot from server and re-inviting
```

### Prevention
- Ensure `applications.commands` scope is in OAuth2 URL
- Bot needs "Use Application Commands" permission
- Commands may take up to 1 hour to propagate globally
- Using `GUILD_ID` in .env restricts commands to one server (faster)

---

## Issue 8: High CPU Usage from Bot

### Symptoms
- Server CPU at 100%
- `claude -p` or `tsx src/index.ts` consuming all CPU
- Bot responses are slow or timeout

### Diagnosis
```bash
# Find top CPU consumers
ps aux --sort=-%cpu | head -10

# Check if claude -p is stuck
ps aux | grep "claude -p" | grep -v grep

# Check bot process
ps aux | grep "tsx src/index" | grep -v grep
```

### Fix

**If `claude -p` is stuck:**
```bash
kill -9 <PID>
```

**If bot itself is stuck (rare):**
```bash
systemctl --user restart discord-claude-ubuntu.service
```

**If health check script is spawning repeatedly:**
```bash
# Check cron jobs
crontab -l | grep discord

# Disable aggressive health checks temporarily
# Fix health check logic (see Issue 1)
```

---

## Quick Reference: Emergency Commands

```bash
# KILL ALL BOTS (emergency reset)
pkill -9 -f "tsx src/index.ts"
pkill -9 -f "claude -p"

# RESTART SERVICE
systemctl --user restart discord-claude-ubuntu.service

# CHECK STATUS
systemctl --user status discord-claude-ubuntu.service --no-pager

# VIEW ALL LOGS
journalctl --user -u discord-claude-ubuntu.service -f

# CHECK FOR DUPLICATES
ps aux | grep "tsx src/index" | grep -v grep | wc -l

# DATABASE REPAIR
sqlite3 threads.db ".tables"
sqlite3 threads.db "SELECT COUNT(*) FROM threads;"
sqlite3 threads.db "DELETE FROM threads;"  # Clear all (nuclear)

# SESSION CLEANUP
rm ~/.claude/projects/*/*.jsonl 2>/dev/null
rm ~/.claude/projects/*/*.lock 2>/dev/null
```

---

## Escalation Path

| Issue | First Action | If Still Broken |
|-------|-----------|----------------|
| Duplicates | Kill all, systemd restart | Check health check scripts |
| No response | Check systemd status | Regenerate Discord token |
| Stuck task | /stop or kill PID | Check session size |
| Session error | Clear DB mapping | Use auto-cleanup bot |
| Bot down | Restart service | Check .env and dependencies |
| High CPU | Kill stuck claude -p | Check for runaway cron |
