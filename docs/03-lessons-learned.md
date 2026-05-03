# Lessons Learned

> Hard-won knowledge from running a Claude Discord bot in production. These are organized by severity and frequency.

---

## Lesson 1: Kill Duplicates, Preserve One

**Severity:** CRITICAL  
**Frequency:** Recurring (4+ incidents)

### Problem
When fixing duplicate bot responses, the instinct is to kill ALL bot processes. This takes the service offline.

### The Incident (2026-04-12)
- User reported 4x duplicate responses to every Discord message
- Investigation found 4 instances of `discord-claude-code-bot` running
- Killed all 4 instances + orphaned `claude -p` processes
- Result: Bot went completely offline
- Had to restart a single instance manually

### Root Cause
- Multiple bot instances started from previous sessions without cleanup
- Each instance received Discord gateway events independently
- Each spawned its own `claude -p` process to respond

### Fix Procedure
```bash
# 1. Check current instances
ps aux | grep "tsx src/index" | grep -v grep

# 2. Kill ALL instances (nuclear option - use with caution)
pkill -9 -f "tsx src/index.ts"

# 3. Restart ONE instance via systemd
systemctl --user restart discord-claude-ubuntu.service

# 4. Verify single instance
ps aux | grep "tsx src/index" | grep -v grep | wc -l  # Should be 1
```

### Prevention
- Before starting any bot, always check for existing processes
- Use systemd exclusively (see Lesson 3)
- Never assume "bot is down" without checking process list

---

## Lesson 2: Systemd Restart=always Causes Duplicates

**Severity:** CRITICAL  
**Frequency:** 2 incidents

### Problem
Systemd service configured with `Restart=always` and `RestartSec=10` caused runaway process spawning.

### The Incident
- Bot crashed or exited rapidly
- Systemd restarted it every 10 seconds
- Old processes didn't die cleanly
- Result: 4-5 bot instances accumulated over hours

### The Fix
```bash
# Stop and disable the runaway service
systemctl --user stop discord-claude-ubuntu.service
systemctl --user disable discord-claude-ubuntu.service

# Kill all duplicates
pkill -9 -f "tsx src/index.ts"

# Recreate service with correct settings
```

**Service file change:**
```ini
# WRONG
Restart=always
RestartSec=10

# CORRECT
Restart=on-failure
RestartSec=10
```

### Prevention
- Never use `Restart=always` without proper exit code handling
- `Restart=on-failure` only restarts when the process exits with non-zero code
- Monitor process count: `pgrep -f "tsx src/index" | wc -l` should be 1

---

## Lesson 3: Systemd Only — Never Manual Start

**Severity:** CRITICAL  
**Frequency:** Weekly recurrence

### Problem
The bot is managed by systemd. Manual `npm start` or `nohup` creates a second instance. Systemd then auto-restarts on failure, creating a third.

### The Incident (2026-04-12)
- User ran `npm start` manually while systemd was already running the bot
- Two instances responded to every message
- User then ran health check script which spawned a third
- Total: 3 instances, all responding to every message

### Correct Commands
```bash
# Start/restart (use this)
systemctl --user restart discord-claude-ubuntu.service

# Stop
systemctl --user stop discord-claude-ubuntu.service

# Check status
systemctl --user status discord-claude-ubuntu.service --no-pager

# View logs
journalctl --user -u discord-claude-ubuntu.service -f
```

### Forbidden Commands
```bash
# NEVER do these:
npm start                                # Creates duplicate
nohup npm start &                        # Creates detached duplicate
node --env-file=.env --import=tsx src/index.ts   # Same as npm start
```

### Prevention
- Document the systemd-only rule prominently
- Add process check to any startup script
- Use `run-bot.sh` wrapper that checks for existing PID before starting

---

## Lesson 4: Health Check Mismatch Spawns Duplicates

**Severity:** HIGH  
**Frequency:** 1 incident

### Problem
Health check cron was looking for `dist/index.js` but the bot runs via `tsx src/index.ts`. The health check always thought the bot was "down" and started a new instance every interval.

### The Incident
- Health check ran every 15 minutes
- It checked: `pgrep -f "discord-claude-code-bot/dist/index"`
- Actual process: `tsx src/index.ts`
- Health check found nothing → started new instance
- Over 8 hours: 4 extra instances spawned
- Each instance added 1 more duplicate response

### The Fix
```bash
# WRONG health check
if ! pgrep -f "discord-claude-code-bot/dist/index" > /dev/null; then
    nohup node --env-file=.env dist/index.js &
fi

# CORRECT health check
if ! pgrep -f "tsx src/index.ts" > /dev/null; then
    systemctl --user restart discord-claude-ubuntu.service
fi
```

### Prevention
- Health checks must match actual process names
- Use systemd for restarts, not `nohup`
- Verify health check logic with `pgrep` before deploying
- Consider disabling old compiled `dist/index.js` to prevent accidental execution

---

## Lesson 5: Session Token Limit Blocks Bot

**Severity:** HIGH  
**Frequency:** Monthly

### Problem
Bot stops responding when session files reach 60k/60k tokens. Auto-compaction fails during tool loops.

### The Incident (2026-04-11)
- Bot stopped responding in Discord
- Session files maxed at 60k tokens
- Error: "Agent couldn't generate a response. Note: some tool actions may have already been executed"
- No automatic recovery

### The Fix
```bash
# 1. Clear session files
rm ~/.claude/projects/*/*.jsonl
rm ~/.claude/projects/*/*.lock

# 2. Clear thread database (start fresh)
rm threads.db

# 3. Restart bot
systemctl --user restart discord-claude-ubuntu.service
```

### Prevention
- Monitor token usage in session files proactively
- Clear sessions when approaching 50k tokens
- Consider implementing automatic rotation at 50k threshold
- Set up monitoring alert at 45k tokens

---

## Lesson 6: Context Overflow in Discord Bot

**Severity:** HIGH  
**Frequency:** 1 incident

### Problem
Bot stopped responding. Session file bloated to 448KB with only 186 lines (massive JSON entries causing context overflow).

### The Incident (2026-04-11)
- Error: "Agent couldn't generate a response"
- Session file: `~/.claude/projects/<cwd>/<uuid>.jsonl`
- Size: 448KB (normally ~10-50KB)
- Lines: 186 (massive tool result JSON per line)
- Auto-compaction failed during tool loop

### The Fix
```bash
# 1. Backup before modification
cp session.jsonl session.jsonl.bak

# 2. Truncate to minimal state
# Keep only: session header + system reset message
# Result: 2 lines, ~4KB

# 3. Restart bot
systemctl --user restart discord-claude-ubuntu.service
```

### Prevention
- Monitor session file sizes regularly (alert at 100KB)
- Implement automatic rotation at 100KB threshold
- Review bot tool usage — excessive tool results bloat sessions

---

## Lesson 7: Stuck claude -p Processes Block New Messages

**Severity:** MEDIUM  
**Frequency:** Weekly

### Problem
`claude -p` subprocesses sometimes get stuck (high CPU, unresponsive), blocking new messages with "Previous task still running. Use /stop first."

### Symptoms
- Discord bot returns: "Previous task still running. Use /stop first."
- `claude -p` process consuming 100%+ CPU for extended time
- Process running >10 minutes is likely stuck

### The Fix
```bash
# 1. Identify stuck process
ps aux | grep "claude -p" | grep -v grep

# 2. Try graceful kill
kill <PID>
sleep 3

# 3. Force kill if still running
kill -9 <PID>

# 4. Verify
ps aux | grep "claude -p" | grep -v grep
```

### Thresholds
| State | Runtime | CPU | Action |
|-------|---------|-----|--------|
| Normal | 1-5 min | <50% | None |
| Warning | 5-10 min | 50-90% | Monitor |
| Stuck | >10 min | >90% | Kill |

### Prevention
- Implement `/stop` slash command (already in bot)
- Add cron job to auto-kill stuck processes every 15 minutes
- Monitor with `scripts/kill-stuck-sessions.sh`
- Never kill the bot itself (`tsx src/index.ts`), only `claude -p` children

---

## Lesson 8: Multiple Discord Systems Can Interfere

**Severity:** MEDIUM  
**Frequency:** 1 incident

### Problem
Two separate Discord systems running simultaneously caused confusion about which was responsible for auto-responses.

### The Systems
1. **Official MCP Discord Plugin** (`server.ts`) — integrated into Claude session via MCP tools. Provides `mcp_discord_reply`. Does NOT auto-respond.
2. **discord-claude-code-bot** (Node.js) — standalone bot that spawns `claude -p` processes. This IS the auto-responding bot.

### The Incident
- User thought MCP plugin was the problem when duplicates occurred
- Actually the standalone bot had spawned 4 instances
- MCP plugin was innocent (only provides tools)

### How to Distinguish
| Check | MCP Plugin | Standalone Bot |
|-------|-----------|----------------|
| Process name | `node server.ts` | `tsx src/index.ts` |
| Auto-responds? | No | Yes |
| Provides tools? | Yes (mcp_*) | No |
| When active | During Claude session | Always (daemon) |

### Prevention
- Document both systems clearly
- When debugging duplicates, check for `tsx src/index.ts` processes, not MCP
- MCP plugin is for tool use; standalone bot is for user chat

---

## Lesson 9: Session Files Lost on Restart

**Severity:** MEDIUM  
**Frequency:** Every system restart

### Problem
After laptop/server restart, Discord bot tries to resume sessions that no longer exist. Session files in `~/.claude/projects/` are lost on restart (or stored on tmpfs), but thread-to-session mappings persist in SQLite.

### Symptoms
```
stderr: No conversation found with session ID: ef7d06fe-c49a-44ed-ae00-65971379005d
```

### The Fix (Implemented in this repo)
The upstream bot doesn't handle this. We've implemented automatic stale session detection in `getOrCreate()`:

- When bot receives a message, checks if session file exists
- If missing (after restart), automatically creates fresh session ID
- User gets new session transparently

See [docs/07-stale-session-detection.md](docs/07-stale-session-detection.md) for technical details.

### Prevention
- Use this hardened version of the bot (includes stale session detection)
- Store session files on persistent storage (not tmpfs)
- Run cleanup on startup and per-message

---

## Lesson 10: Duplicate Prevention Requires Singleton Wrapper

**Severity:** MEDIUM  
**Frequency:** Ongoing risk

### Problem
Even with systemd, race conditions or manual interventions can spawn duplicates.

### The Fix
Create `run-bot.sh` singleton wrapper:

```bash
#!/bin/bash
PIDFILE=/tmp/discord-bot.pid

# Check if already running
if [ -f "$PIDFILE" ]; then
  OLD_PID=$(cat "$PIDFILE")
  if ps -p "$OLD_PID" > /dev/null 2>&1; then
    echo "Bot already running (PID: $OLD_PID)"
    exit 1
  fi
fi

# Start and record PID
node --env-file=.env --import=tsx src/index.ts &
echo $! > "$PIDFILE"
wait
rm -f "$PIDFILE"
```

### Prevention
- Use PID files for singleton enforcement
- Document systemd-only policy prominently
- Consider using `flock` for file-based locking

---

## Summary: The Most Important Rules

1. **Always use systemd** — Never `npm start` or `nohup`
2. **Kill duplicates, keep one** — Check process count before and after fixes
3. **Match health checks to actual processes** — `pgrep` must find the real process name
4. **Use `Restart=on-failure`** — Never `Restart=always`
5. **Monitor session sizes** — Clear before 60k token limit
6. **Auto-detect stale sessions** — Use this hardened bot version
7. **Kill stuck `claude -p`** — But never kill the bot itself
8. **Singleton enforcement** — PID files or systemd prevent race conditions
