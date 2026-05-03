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
See [docs/09-health-monitoring.md](docs/09-health-monitoring.md) for cron-based stuck process killer.

### Prevention
- Implement `/stop` command in your bot
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

### Fix (Automatic — Implemented)
If your bot has stale session detection (see [docs/07-stale-session-detection.md](docs/07-stale-session-detection.md)):
- Bot automatically detects missing session file
- Deletes stale mapping
- Creates fresh session
- User gets new session transparently

### Prevention
- Implement `isSessionValid()` + `cleanupStaleSessions()` in bot code
- Store session files on persistent storage (not tmpfs)
- Run cleanup on startup and per-message

---

## Issue 5: Agent (Lisa/Nyx/Kael) Stopped Responding

### Symptoms
- Agent not replying in Discord
- No error messages visible
- Other agents still working

### Diagnosis
```bash
# Check agent-specific bot process
ps aux | grep "tsx src/index" | grep -v grep
# Check for agent-specific env file processes

# Check agent session files
ls -lh ~/.openclaw/agents/<agent>/sessions/

# Check session size
wc -c ~/.openclaw/agents/<agent>/sessions/*.jsonl

# Check token count (if available)
grep -c "" ~/.openclaw/agents/<agent>/sessions/*.jsonl
```

### Common Causes & Fixes

**A. Session token limit (60k/60k)**
```bash
# Clear session files
rm ~/.openclaw/agents/<agent>/sessions/*.jsonl
rm ~/.openclaw/agents/<agent>/sessions/*.lock

# Remove Discord entries from sessions.json
# Edit: ~/.openclaw/agents/<agent>/sessions.json

# Restart agent gateway
systemctl --user restart openclaw-gateway-<agent>.service
```

**B. Context overflow (huge session file)**
```bash
# Backup
mv session.jsonl session.jsonl.bak

# Create minimal session
echo '{"type":"header","version":"1"}' > session.jsonl
echo '{"type":"system","text":"System reset. Agent ready."}' >> session.jsonl

# Restart gateway
systemctl --user restart openclaw-gateway-<agent>.service
```

**C. Bot process crashed**
```bash
systemctl --user restart discord-<agent>.service
```

---

## Issue 6: Bridge Messages Not Being Read

### Symptoms
- Claude writes to bridge file
- Lisa never responds
- Bridge file keeps growing with Claude's messages

### Diagnosis
```bash
# Verify bridge file exists at CORRECT path
ls -la ~/.openclaw/workspace-lisa/BRIDGE_LISA.md

# Check if wrong bridge file exists (deprecated)
ls -la /home/user/bridge/LISA_TO_CLAUDE.md 2>/dev/null && echo "WRONG FILE EXISTS"

# Check bridge monitor status
systemctl --user status lisa-bridge-monitor.service --no-pager

# Check bridge monitor logs
journalctl --user -u lisa-bridge-monitor.service -n 20 --no-pager
```

### Fix

**Step 1: Delete wrong bridge files**
```bash
rm /home/user/bridge/LISA_TO_CLAUDE.md 2>/dev/null
rm /home/user/bridge/CLAUDE_TO_LISA.md 2>/dev/null
```

**Step 2: Verify correct bridge file**
```bash
cat ~/.openclaw/workspace-lisa/BRIDGE_LISA.md
```

**Step 3: Restart bridge monitor**
```bash
systemctl --user restart lisa-bridge-monitor.service
```

**Step 4: Send test message**
```bash
echo "## Test Message
**From:** Claude
**Time:** $(date)
**Content:** If you read this, bridge is working.
---" >> ~/.openclaw/workspace-lisa/BRIDGE_LISA.md
```

### Prevention
- Delete deprecated bridge paths after migration
- Document canonical paths in agent training materials
- Consider using GitHub Live Chat instead of file bridges

---

## Issue 7: Systemd Service Fails to Start

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
cd ~/discord-claude-code-bot && node --env-file=.env --import=tsx src/index.ts
# (Ctrl+C after verifying error)
```

### Common Causes & Fixes

**A. .env file missing or invalid**
```bash
# Verify .env exists
ls -la ~/discord-claude-code-bot/.env

# Verify token format
grep DISCORD_BOT_TOKEN ~/discord-claude-code-bot/.env
# Should show: DISCORD_BOT_TOKEN=<64-char string>
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
chmod 600 ~/discord-claude-code-bot/threads.db
# Or delete to recreate
rm ~/discord-claude-code-bot/threads.db
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

## Issue 8: Slash Commands Not Appearing

### Symptoms
- Type `/` in Discord, bot commands don't show
- Commands were working before but disappeared

### Fix
```bash
# Re-register slash commands
# This requires running the bot's command registration logic
# Usually happens automatically on first start

# Force re-registration by deleting bot from server and re-inviting
# Or use Discord Developer Portal → Bot → OAuth2 → regenerate URL

# Alternative: Some bots have a /sync command or registration script
# Check bot source for registerCommands() function
```

### Prevention
- Ensure `applications.commands` scope is in OAuth2 URL
- Bot needs "Use Application Commands" permission
- Commands may take up to 1 hour to propagate globally

---

## Issue 9: High CPU Usage from Bot

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

## Issue 10: Agent Claims Task Complete But No File Exists

### Symptoms
- Agent: "I've created the file at /path/to/file.md"
- `ls /path/to/file.md` → No such file or directory
- Agent may double down on claim or admit error

### Diagnosis
```bash
# Verify file non-existence
ls -la /path/to/file.md

# Check if file exists elsewhere
find /home/user -name "file.md" 2>/dev/null

# Check agent logs for actual commands executed
journalctl --user -u discord-lisa.service -n 100 --no-pager | grep -i "write\|create\|save"
```

### Fix
- Ask agent to re-execute with explicit path
- Use absolute paths in all instructions
- Implement grounding framework: require `ls` confirmation after file creation

### Prevention
- Grounding Framework: agents must provide evidence for factual claims
- Add file existence checks in agent logic before reporting success
- Use `test -f` or `fs.existsSync()` as validation step

---

## Quick Reference: Emergency Commands

```bash
# KILL ALL BOTS (emergency reset)
pkill -9 -f "tsx src/index.ts"
pkill -9 -f "claude -p"

# RESTART ALL SERVICES
systemctl --user restart discord-claude-ubuntu.service
systemctl --user restart discord-lisa.service
systemctl --user restart discord-nyx.service
systemctl --user restart discord-kael.service

# CHECK ALL STATUSES
systemctl --user status discord-claude-ubuntu.service --no-pager
systemctl --user status discord-lisa.service --no-pager

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
| Stuck task | /stop or kill PID | Check agent session size |
| Session error | Clear DB mapping | Implement auto-cleanup |
| Bridge lost | Delete wrong paths | Migrate to GitHub Live Chat |
| Agent down | Restart agent service | Clear agent sessions |
| High CPU | Kill stuck claude -p | Check for runaway cron |
