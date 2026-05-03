# Health Monitoring & Operations

> Cron jobs, health checks, and monitoring stack for the Claude Discord bot.

---

## Monitoring Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| Process monitoring | systemd + journalctl | Service health, logs |
| Duplicate detection | Custom shell script | Prevent duplicate bot instances |
| Stuck process killer | Custom shell script | Kill hung `claude -p` processes |
| Session health | Token count monitoring | Prevent 60k token limit |
| Cron scheduling | cron | Periodic health checks |
| Log aggregation | journalctl | Centralized logging |

---

## Systemd Services

### Core Bot Service

```ini
# discord-claude-ubuntu.service
[Unit]
Description=Claude Discord Bot
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/user/claude_discord
ExecStart=node --env-file=.env --import=tsx src/index.ts
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

**Enable and start:**
```bash
systemctl --user daemon-reload
systemctl --user enable discord-claude-ubuntu.service
systemctl --user start discord-claude-ubuntu.service
```

---

## Cron Jobs

### Primary Schedule

```bash
# Edit: crontab -e

# Every 15 minutes: Stuck process monitor
*/15 * * * * /usr/local/bin/kill-stuck-sessions.sh

# Every 5 minutes: Duplicate bot detection
*/5 * * * * /usr/local/bin/duplicate-check.sh

# Every hour: Log status
0 * * * * * systemctl --user status discord-claude-ubuntu.service --no-pager >> /tmp/bot-status.log

# Daily at 3 AM: Session cleanup
0 3 * * * /home/user/claude_discord/scripts/session-cleanup.sh

# Weekly: Log rotation
0 0 * * 0 /home/user/claude_discord/scripts/rotate-logs.sh
```

### Included Scripts

The `scripts/` directory contains:

- **duplicate-check.sh** — Counts `tsx src/index` processes. If >1, kills all and restarts via systemd.
- **kill-stuck-sessions.sh** — Finds `claude -p` processes with CPU >90% running >10 min, kills them.

Install them:
```bash
chmod +x scripts/*.sh
sudo cp scripts/duplicate-check.sh /usr/local/bin/
sudo cp scripts/kill-stuck-sessions.sh /usr/local/bin/
```

---

## Health Check Commands

### Bot Status

```bash
# Check service status
systemctl --user status discord-claude-ubuntu.service --no-pager

# Check process count (should be 1)
ps aux | grep "tsx src/index" | grep -v grep | wc -l

# Check stuck processes (should be 0)
ps aux | grep "claude -p" | grep -v grep | wc -l
```

### Database Health

```bash
# Check SQLite database
sqlite3 threads.db ".tables"
sqlite3 threads.db "SELECT COUNT(*) FROM threads;"
sqlite3 threads.db "SELECT COUNT(*) FROM threads WHERE started = 1;"
```

### Session File Health

```bash
# Check session sizes
du -sh ~/.claude/projects/* 2>/dev/null | sort -rh | head -5

# Find oversized sessions
find ~/.claude/projects -name "*.jsonl" -size +100k
```

---

## Log Aggregation

### Viewing Logs

```bash
# Real-time bot logs
journalctl --user -u discord-claude-ubuntu.service -f

# Recent errors only
journalctl --user -u discord-claude-ubuntu.service -p err -n 50 --no-pager

# All services combined
journalctl --user -f
```

### Log Rotation

```bash
# Manual rotation
sudo logrotate -f /etc/logrotate.d/user-logs

# Custom logrotate config
/home/user/claude_discord/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 644 user user
}
```

---

## Metrics to Track

| Metric | How to Measure | Target |
|--------|---------------|--------|
| Bot uptime | systemd status | >99% |
| Duplicate instances | `ps aux \| grep tsx` | 0 |
| Stuck processes | `ps aux \| grep "claude -p"` | 0 |
| Session token usage | `wc -c sessions/*.jsonl` | <50k |
| System load | `uptime` | <2.0 |
| Disk usage | `df -h` | <80% |

---

## Disaster Recovery

### Scenario 1: Total Bot Failure

```bash
# 1. Check what's running
ps aux | grep "tsx\|claude" | grep -v grep

# 2. Kill everything
pkill -9 -f "tsx src/index"
pkill -9 -f "claude -p"

# 3. Restart service
systemctl --user restart discord-claude-ubuntu.service

# 4. Verify
systemctl --user status discord-claude-ubuntu.service --no-pager
```

### Scenario 2: Database Corruption

```bash
# Backup corrupted DB
cp threads.db threads.db.corrupt.$(date +%Y%m%d%H%M%S)

# Delete and recreate (bot will create on startup)
rm threads.db

# Restart bot
systemctl --user restart discord-claude-ubuntu.service
```

### Scenario 3: Session Explosion

```bash
# Clear all session files
rm ~/.claude/projects/*/*.jsonl 2>/dev/null
rm ~/.claude/projects/*/*.lock 2>/dev/null

# Restart bot
systemctl --user restart discord-claude-ubuntu.service
```

---

## Operational Runbook

### Daily Checks (2 minutes)

```bash
#!/bin/bash
# daily-check.sh

echo "=== Bot Process ==="
ps aux | grep "tsx src/index" | grep -v grep | wc -l
echo "Expected: 1"

echo "=== Stuck Processes ==="
ps aux | grep "claude -p" | grep -v grep | wc -l
echo "Expected: 0"

echo "=== Service Status ==="
systemctl --user is-active discord-claude-ubuntu.service

echo "=== Session Sizes ==="
du -sh ~/.claude/projects/* 2>/dev/null | sort -rh | head -5
```

### Weekly Maintenance (15 minutes)

1. Review logs for errors: `journalctl --user -p err --since "1 week ago"`
2. Rotate logs
3. Clear old session files (>7 days)
4. Check disk usage: `df -h`
5. Verify backup integrity

### Monthly Review (30 minutes)

1. Analyze duplicate incident frequency
2. Review token usage trends
3. Assess bot latency
4. Update systemd service files if needed
5. Test disaster recovery procedures
