# Health Monitoring & Operations

> Cron jobs, health checks, and monitoring stack for the Claude Discord multi-agent system.

---

## Monitoring Stack

| Component | Tool | Purpose |
|-----------|------|---------|
| Process monitoring | systemd + journalctl | Service health, logs |
| Duplicate detection | Custom shell script | Prevent duplicate bot instances |
| Stuck process killer | Custom shell script | Kill hung `claude -p` processes |
| Session health | Token count monitoring | Prevent 60k token limit |
| Bridge monitoring | systemd service | Detect bridge file changes |
| Cron scheduling | cron | Periodic health checks |
| Log aggregation | journalctl | Centralized logging |

---

## Systemd Services

### Core Bot Services

```ini
# discord-claude-ubuntu.service
[Unit]
Description=Claude Discord Bot
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/user/discord-claude-code-bot
ExecStart=node --env-file=.env --import=tsx src/index.ts
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

**Per-agent services:**
- `discord-lisa.service`
- `discord-nyx.service`
- `discord-kael.service`

### Bridge Monitor Services

```ini
# lisa-bridge-monitor.service
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

### Gateway Services (OpenClaw)

```ini
# openclaw-gateway-lisa.service
[Unit]
Description=OpenClaw Gateway for Lisa

[Service]
Type=simple
ExecStart=/home/user/.openclaw/bin/openclaw-gateway --agent lisa
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

---

## Cron Jobs

### Primary Schedule

```bash
# Edit: crontab -e

# Every 5 minutes: Discord coordinator (message routing)
*/5 * * * * /home/user/.openclaw/scripts/discord_coordinator.py

# Every 15 minutes: Stuck process monitor
*/15 * * * * /home/user/discord-claude-code-bot/scripts/session-health-check.sh

# Every 5 minutes: Duplicate bot detection
*/5 * * * * /home/user/discord-claude-code-bot/scripts/duplicate-check.sh

# Every hour: Bridge monitor (backup to systemd service)
0 * * * * /home/user/.openclaw/scripts/bridge-monitor.sh lisa
0 * * * * /home/user/.openclaw/scripts/bridge-monitor.sh nyx
0 * * * * /home/user/.openclaw/scripts/bridge-monitor.sh kael

# Every 15 minutes: Bridge trigger check
*/15 * * * * /home/user/.openclaw/scripts/bridge-trigger-check.sh

# Every minute: GitHub Live Chat sync
* * * * * cd /home/user/beautiful-talking && ./scripts/chat-sync.sh

# Daily at 3 AM: Session cleanup
0 3 * * * /home/user/.openclaw/scripts/session-cleanup.sh

# Daily at 9 AM SGT: Lisa standup trigger
0 1 * * * /home/user/.openclaw/scripts/trigger-lisa-standup.sh

# Weekly: Log rotation
0 0 * * 0 /home/user/.openclaw/scripts/rotate-logs.sh
```

### Cron Job Details

#### discord_coordinator.py
- Fetches messages from Discord #command_center
- Routes [APPROVED] tags to Kael's INBOX
- Routes general messages to appropriate agent INBOX
- Tracks message IDs in state file to prevent duplicates

#### session-health-check.sh
```bash
#!/bin/bash
# Kill stuck claude -p processes
STUCK=$(ps aux | grep "claude -p" | grep -v grep | awk '{if ($3 > 90.0) print $2}')
for PID in $STUCK; do
  RUNTIME=$(ps -o etime= -p $PID | tr -d ' ')
  # Kill if running > 10 minutes
  if [[ "$RUNTIME" =~ ^[0-9]+-[0-9]+:[0-9]+:[0-9]+$ ]] || \
     [[ "$RUNTIME" =~ ^[0-9]+:[0-9]+:[0-9]+$ ]]; then
    echo "$(date): Killing stuck process $PID (CPU > 90%, runtime: $RUNTIME)"
    kill -9 $PID
  fi
done
```

#### duplicate-check.sh
```bash
#!/bin/bash
# Check for duplicate bot instances
COUNT=$(ps aux | grep "tsx src/index" | grep -v grep | wc -l)
if [ "$COUNT" -gt 1 ]; then
  echo "$(date): WARNING: $COUNT bot instances detected. Killing duplicates..."
  pkill -9 -f "tsx src/index.ts"
  sleep 2
  systemctl --user restart discord-claude-ubuntu.service
fi
```

#### session-cleanup.sh
```bash
#!/bin/bash
# Clear old session files to prevent token limit
for agent in lisa nyx kael william; do
  AGENT_DIR="$HOME/.openclaw/agents/$agent/sessions"
  if [ -d "$AGENT_DIR" ]; then
    # Find and remove files older than 7 days
    find "$AGENT_DIR" -name "*.jsonl" -mtime +7 -delete
    echo "$(date): Cleaned old sessions for $agent"
  fi
done
```

---

## Health Check Commands

### Bot Status

```bash
# Check all bot services
for service in discord-claude-ubuntu discord-lisa discord-nyx discord-kael; do
  echo "=== $service ==="
  systemctl --user status $service.service --no-pager 2>&1 | head -5
  echo
done
```

### Process Count

```bash
# Count bot processes (should be 1 per agent)
ps aux | grep "tsx src/index" | grep -v grep | wc -l
# Expected: 4 (Claude + Lisa + Nyx + Kael)

# Count stuck claude -p processes
ps aux | grep "claude -p" | grep -v grep | wc -l
# Expected: 0-1 (should exit after completing task)
```

### Database Health

```bash
# Check SQLite databases
for db in ~/discord-claude-code-bot/data/*-threads.db; do
  echo "=== $(basename $db) ==="
  sqlite3 "$db" "SELECT COUNT(*) FROM threads;"
  sqlite3 "$db" "SELECT COUNT(*) FROM threads WHERE started = 1;"
done
```

### Session File Health

```bash
# Check session sizes
for agent in claude lisa nyx kael; do
  echo "=== $agent sessions ==="
  du -sh ~/.claude/projects/*/*.jsonl 2>/dev/null | head -5
  du -sh ~/.openclaw/agents/$agent/sessions/*.jsonl 2>/dev/null | head -5
done
```

### Bridge Health

```bash
# Check bridge files exist and are recent
for agent in lisa nyx kael william; do
  BRIDGE="$HOME/.openclaw/workspace-$agent/BRIDGE_$(echo $agent | tr '[:lower:]' '[:upper:]').md"
  if [ -f "$BRIDGE" ]; then
    echo "$agent: $(stat -c '%y' $BRIDGE)"
  else
    echo "$agent: MISSING"
  fi
done
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
journalctl --user -u "discord-*" -f

# Bridge monitor logs
journalctl --user -u lisa-bridge-monitor.service -n 100 --no-pager

# Gateway logs
journalctl --user -u openclaw-gateway-lisa.service -f
```

### Log Rotation

```bash
# Manual rotation
sudo logrotate -f /etc/logrotate.d/user-logs

# Custom logrotate config
/home/user/.claude/discord/logs/*.log {
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

## Alerts & Notifications

### Telegram Alerts

Critical issues trigger Telegram notifications:

```bash
# alert.sh
#!/bin/bash
MESSAGE="$1"
TELEGRAM_BOT_TOKEN=<token>
TELEGRAM_CHAT_ID=<chat_id>

curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
  -d "chat_id=$TELEGRAM_CHAT_ID" \
  -d "text=$MESSAGE"
```

**Alert triggers:**
- Duplicate bot instances detected
- Agent session token limit approaching
- Bridge monitor down for >15 minutes
- GitHub Live Chat sync failure

### Discord Alerts

Bot can self-report health issues to a #system-alerts channel:

```typescript
// In bot code
if (duplicateDetected) {
  alertChannel.send(`@admin WARNING: ${duplicateCount} bot instances detected`);
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
| Bridge latency | Timestamp diff | <15 min |
| Agent response time | Message timestamps | <30 min |
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

# 3. Restart all services
systemctl --user restart discord-claude-ubuntu.service
systemctl --user restart discord-lisa.service
systemctl --user restart discord-nyx.service
systemctl --user restart discord-kael.service

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

### Scenario 3: Agent Session Explosion

```bash
# Clear all agent sessions
for agent in lisa nyx kael william; do
  rm ~/.openclaw/agents/$agent/sessions/*.jsonl
  rm ~/.openclaw/agents/$agent/sessions/*.lock
done

# Restart gateways
systemctl --user restart openclaw-gateway-lisa.service
systemctl --user restart openclaw-gateway-nyx.service
systemctl --user restart openclaw-gateway-kael.service
```

---

## Operational Runbook

### Daily Checks (5 minutes)

```bash
#!/bin/bash
# daily-check.sh

echo "=== Bot Processes ==="
ps aux | grep "tsx src/index" | grep -v grep | wc -l
echo "Expected: 4"

echo "=== Stuck Processes ==="
ps aux | grep "claude -p" | grep -v grep | wc -l
echo "Expected: 0"

echo "=== Service Status ==="
for svc in discord-claude-ubuntu discord-lisa discord-nyx discord-kael; do
  systemctl --user is-active $svc.service
done

echo "=== Bridge Files ==="
ls -la ~/.openclaw/workspace-*/BRIDGE_*.md

echo "=== Session Sizes ==="
du -sh ~/.claude/projects/* 2>/dev/null | sort -rh | head -5
```

### Weekly Maintenance (30 minutes)

1. Review logs for errors: `journalctl --user -p err --since "1 week ago"`
2. Rotate logs
3. Clear old session files (>7 days)
4. Check disk usage: `df -h`
5. Verify backup integrity
6. Review and update documentation

### Monthly Review (1 hour)

1. Analyze duplicate incident frequency
2. Review token usage trends
3. Assess bridge latency
4. Update agent system prompts if needed
5. Test disaster recovery procedures
6. Review and prune cron jobs
