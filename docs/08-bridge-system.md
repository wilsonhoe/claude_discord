# Bridge Communication System

> How agents communicate through file-based bridges, Telegram INBOX/OUTBOX, and GitHub Live Chat.

---

## Overview

The coordination layer enables asynchronous communication between Claude and sub-agents (Lisa, Nyx, Kael, William). Three mechanisms are used:

| Mechanism | Latency | Persistence | Use Case |
|-----------|---------|-------------|----------|
| **File Bridge** | 5-15 min | File system | Primary agent delegation |
| **Telegram INBOX/OUTBOX** | 1-5 min | File system | Mobile notifications, fallback |
| **GitHub Live Chat** | 1 min (cron) | Git history | Long-form collaboration, audit trail |

---

## 1. File Bridge System

### Canonical Paths

```
~/.openclaw/workspace-lisa/BRIDGE_LISA.md
~/.openclaw/workspace-nyx/BRIDGE_NYX.md
~/.openclaw/workspace-kael/BRIDGE_KAEL.md
~/.openclaw/workspace-william/BRIDGE_WILLIAM.md
```

**Important:** These paths are canonical. Any deviation causes silent message loss.

### Bridge File Format

```markdown
# BRIDGE: Claude <-> Lisa
# Protocol: Append-only markdown. Each message = new section.
# Last updated: 2026-05-03
---

## Message from Claude
**Timestamp:** 2026-05-03T09:00:00Z
**Priority:** HIGH
**Mission:** Check GitHub bounties for Rust projects.
**Details:**
- Focus on projects with >$100 bounties
- Report total count and top 5
- Deadline: 30 minutes

---

## Message from Lisa
**Timestamp:** 2026-05-03T09:25:00Z
**Status:** COMPLETE
**Result:**
- Total bounties found: 103
- Top 5: [list]
- Total value: $515

---
```

### Protocol Rules

1. **Append-only** — Never edit existing sections; always append new `---` section
2. **Timestamp every message** — ISO 8601 format
3. **Include sender** — "Message from Claude" or "Message from Lisa"
4. **Status marker** — PENDING, IN_PROGRESS, COMPLETE, FAILED
5. **Priority** — LOW, MEDIUM, HIGH, CRITICAL
6. **Never delete** — Bridge file is audit trail; archive if too large

### Bridge Monitor

Each agent runs a bridge monitor that watches for file changes:

```bash
# Bridge monitor logic (pseudocode)
while true; do
  if [ bridge_file_modified ]; then
    read_new_sections
    process_messages
    write_response
  fi
  sleep 300  # 5 minutes
done
```

**Systemd service:**
```ini
[Unit]
Description=Lisa Bridge Monitor

[Service]
Type=simple
ExecStart=/home/user/.openclaw/scripts/bridge-monitor.sh lisa
Restart=always
RestartSec=60

[Install]
WantedBy=default.target
```

### Common Failure: Wrong Bridge Path

**Symptom:** Messages written but never read.

**Deprecated paths (NEVER USE):**
```
/home/user/bridge/LISA_TO_CLAUDE.md
/home/user/bridge/CLAUDE_TO_LISA.md
/tmp/bridge_*.md
```

**Fix:**
```bash
# Delete wrong files
rm /home/user/bridge/LISA_TO_CLAUDE.md 2>/dev/null
rm /home/user/bridge/CLAUDE_TO_LISA.md 2>/dev/null

# Recreate canonical bridge
touch ~/.openclaw/workspace-lisa/BRIDGE_LISA.md
```

---

## 2. Telegram INBOX/OUTBOX System

### File Paths

```
~/.openclaw/workspace-lisa/telegram-inbox.md
~/.openclaw/workspace-lisa/telegram-outbox.md
```

### Use Cases

- **Mobile notifications** — When Discord is unavailable
- **Fallback communication** — If bridge files fail
- **Urgent alerts** — Critical issues requiring immediate attention

### Format

```markdown
# Telegram INBOX — Lisa
---

## 2026-05-03 09:15 UTC
**From:** Claude
**Type:** NOTIFICATION
**Content:** System restart completed. All services online.

---
```

### Coordinator Integration

The coordinator cron fetches Discord messages and routes to INBOX:

```python
# discord_coordinator.py (pseudocode)
for message in discord_messages:
    if "[APPROVED]" in message.content:
        append_to_inbox("kael", message)
    elif "[URGENT]" in message.content:
        append_to_inbox("lisa", message)
```

---

## 3. GitHub Live Chat

### Repository Structure

```
beautiful-talking/
├── chat/
│   ├── LIVE-CHAT.md       # Active conversation
│   └── README.md          # Chat system docs
├── scripts/
│   ├── send-chat.sh       # One-command send
│   └── chat-sync.sh       # Auto-sync cron
├── sync/
│   ├── trigger-claude.md  # Notify Claude
│   └── trigger-lisa.md    # Notify Lisa
└── .github/
    └── workflows/
        └── sync.yml       # (Optional) GitHub Actions sync
```

### How It Works

1. **Agent writes message** to `chat/LIVE-CHAT.md`
2. **Commits and pushes** to GitHub
3. **Updates trigger file** (`sync/trigger-claude.md` or `sync/trigger-lisa.md`)
4. **Other agent's cron** (every 1 minute) pulls changes
5. **Bridge watcher** detects trigger file change
6. **Agent reads** new messages and replies

### Cron Configuration

```bash
# Claude's cron
* * * * * cd ~/beautiful-talking && ./scripts/chat-sync.sh

# chat-sync.sh
#!/bin/bash
git pull origin main
if [ trigger-file-changed ]; then
  notify-bridge
fi
```

### Advantages Over File Bridge

| Feature | File Bridge | GitHub Live Chat |
|---------|-------------|------------------|
| Persistence | Local only | Cloud (Git history) |
| Searchable | grep | Git log + GitHub search |
| Multi-agent | One bridge per pair | One chat for all |
| Mobile access | No | GitHub mobile app |
| Audit trail | File size limit | Infinite (git history) |
| Sync delay | 5-15 min | 1-2 min |

---

## 4. Communication Flow Examples

### Example 1: Simple Delegation

```
User (Discord): "Claude, research AI bounties"
Claude: writes to BRIDGE_LISA.md
  "Mission: Research AI bounties. Priority: HIGH."

[5 min later]
Lisa (bridge monitor): reads bridge
Lisa: executes research
Lisa: writes to BRIDGE_LISA.md
  "Status: COMPLETE. Found 15 bounties."

[5 min later]
Claude (bridge monitor): reads bridge
Claude (Discord): "Lisa found 15 bounties..."
```

### Example 2: Urgent Alert

```
System monitor: detects high CPU
System monitor: writes to telegram-inbox.md (all agents)
  "ALERT: CPU > 90% for 10 minutes"

Lisa (cron): reads inbox
Lisa: investigates
Lisa: writes to telegram-outbox.md
  "Found stuck claude -p process. Killed PID 12345."
```

### Example 3: Collaborative Architecture Design

```
Claude (GitHub): writes to chat/LIVE-CHAT.md
  "Proposing Redis for bridge system..."
git push

[Lisa pulls]
Lisa: replies in chat/LIVE-CHAT.md
  "Agreed. Suggest BullMQ for queue..."
git push

[Nyx pulls]
Nyx: replies...
git push

[Full conversation preserved in git history]
```

---

## 5. Bridge System Comparison

| Aspect | File Bridge | Telegram INBOX | GitHub Live Chat |
|--------|------------|----------------|------------------|
| **Speed** | Slow (5-15m) | Medium (1-5m) | Medium (1-2m) |
| **Reliability** | High (local FS) | High (local FS) | High (GitHub) |
| **Scalability** | Low (file locks) | Low (file locks) | High (Git) |
| **Auditability** | Low | Low | High |
| **Mobile** | No | Partial | Yes (GitHub app) |
| **Setup complexity** | Low | Low | Medium |
| **Best for** | Agent delegation | Alerts | Collaboration |

---

## 6. Migration Strategy

### Current State (2026-05-03)
- Primary: File bridges (Lisa, Nyx, Kael)
- Fallback: Telegram INBOX/OUTBOX
- Experimental: GitHub Live Chat

### Recommended Migration
1. **Phase 1** (Immediate): Delete deprecated bridge paths, enforce canonical
2. **Phase 2** (30 days): Move long-form collaboration to GitHub Live Chat
3. **Phase 3** (90 days): Evaluate Redis pub/sub for real-time bridge replacement
4. **Phase 4** (6 months): Deprecate file bridges, use Redis + GitHub Chat

---

## 7. Troubleshooting Bridge Issues

### Issue: Messages Not Crossing Bridge

```bash
# 1. Verify bridge file exists
ls -la ~/.openclaw/workspace-lisa/BRIDGE_LISA.md

# 2. Check file is being written
tail -20 ~/.openclaw/workspace-lisa/BRIDGE_LISA.md

# 3. Check bridge monitor is running
systemctl --user status lisa-bridge-monitor.service

# 4. Check monitor logs
journalctl --user -u lisa-bridge-monitor.service -n 50

# 5. Test manual write
echo "## Test
**From:** Claude
**Time:** $(date)
**Content:** Test message
---" >> ~/.openclaw/workspace-lisa/BRIDGE_LISA.md
# Wait 5 min, check if Lisa responds
```

### Issue: Bridge File Too Large

```bash
# Archive old bridge
cp BRIDGE_LISA.md BRIDGE_LISA.md.archive.$(date +%Y%m%d)

# Create new bridge with header only
head -5 BRIDGE_LISA.md > BRIDGE_LISA.md.new
mv BRIDGE_LISA.md.new BRIDGE_LISA.md
```

### Issue: GitHub Live Chat Sync Delay

```bash
# Manual sync
cd ~/beautiful-talking
git pull origin main

# Check trigger files
ls -la sync/
cat sync/trigger-lisa.md
```
