# Auto-Sync to GitHub

> Automatically push local changes to `wilsonhoe/claude_discord` with secret sanitization.

---

## Overview

Three mechanisms ensure your repo stays in sync with GitHub without manual intervention:

| Mechanism | Trigger | Purpose |
|-----------|---------|---------|
| **Webhook Trigger** (File watcher) | Any file change in repo | Immediate sync when you edit docs |
| **Weekly Timer** (Systemd) | Every Monday 9:17 AM | Periodic backup of all changes |
| **Secret Sanitizer** (Pre-push) | Before every push | Blocks secrets from reaching GitHub |

---

## Quick Setup

```bash
cd ~/claude_discord

# 1. Make scripts executable
chmod +x scripts/*.sh

# 2. Install systemd user units
cp systemd/github-auto-push.timer ~/.config/systemd/user/
cp systemd/github-auto-push.service ~/.config/systemd/user/
cp systemd/webhook-trigger.service ~/.config/systemd/user/

# 3. Reload systemd
systemctl --user daemon-reload

# 4. Enable weekly timer
systemctl --user enable github-auto-push.timer
systemctl --user start github-auto-push.timer

# 5. Start file watcher (webhook trigger)
systemctl --user enable webhook-trigger.service
systemctl --user start webhook-trigger.service

# 6. Verify
systemctl --user list-timers
systemctl --user status webhook-trigger.service
```

---

## Scripts

### 1. `scripts/github-auto-push.sh`

Main auto-push script. Handles the full workflow:

1. Checks remote connectivity
2. Fetches latest changes from GitHub
3. Detects local changes (modified, new, deleted files)
4. Ignores potential secret files (`.env`, `.pem`, etc.)
5. Stages all safe changes
6. Runs secret sanitizer on staged files
7. Commits with auto-generated message
8. Pushes to `origin main`
9. Logs everything to `/tmp/github-auto-push.log`

**Usage:**
```bash
./scripts/github-auto-push.sh
```

**Commit message format:**
```
auto: weekly sync 2026-05-05

Files changed: 3

  - docs/02-setup-guide.md
  - README.md
  - scripts/new-script.sh

🤖 Auto-sync by systemd timer
```

### 2. `scripts/secret-sanitizer.sh`

Scans staged files for secrets and blocks push if found.

**Checks for:**
- Discord tokens (64-72 char alphanumeric)
- API keys (`sk-...`, `Bearer ...`)
- Wallet addresses (`0x...`, `bc1...`)
- Private keys (PEM format)
- Passwords in URLs (`user:pass@host`)
- AWS keys (`AKIA...`)
- Forbidden files (`.env`, `.pem`, `secrets/`)
- System paths that reveal structure (`/home/username/...`)

**Usage:**
```bash
# Manual scan
./scripts/secret-sanitizer.sh

# As git pre-push hook (recommended)
ln -sf ../../scripts/secret-sanitizer.sh .git/hooks/pre-push
```

**If false positive:**
```bash
# Skip sanitizer for one push
git push --no-verify
```

### 3. `scripts/webhook-trigger.sh`

File system watcher that triggers auto-push when files change.

**Requires:** `inotify-tools`
```bash
sudo apt install inotify-tools
```

**Usage:**
```bash
./scripts/webhook-trigger.sh start   # Start watching
./scripts/webhook-trigger.sh stop    # Stop watching
./scripts/webhook-trigger.sh status  # Check status
```

**Behavior:**
- Watches entire repo directory (excluding `.git/`, logs, `threads.db`)
- On change: waits 30 seconds for batching (multiple edits = one push)
- Then runs `github-auto-push.sh`
- Logs to `/tmp/github-webhook-trigger.log`

---

## Systemd Units

### Weekly Timer

`systemd/github-auto-push.timer`:
```ini
[Unit]
Description=Weekly GitHub auto-push for claude_discord

[Timer]
OnCalendar=Mon *-*-* 09:17:00
Persistent=true

[Install]
WantedBy=timers.target
```

`systemd/github-auto-push.service`:
```ini
[Unit]
Description=Auto-push claude_discord to GitHub

[Service]
Type=oneshot
WorkingDirectory=/home/user/claude_discord
ExecStart=/home/user/claude_discord/scripts/github-auto-push.sh
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
```

### Webhook Trigger Service

`systemd/webhook-trigger.service`:
```ini
[Unit]
Description=File watcher webhook trigger for claude_discord
After=network.target

[Service]
Type=simple
WorkingDirectory=/home/user/claude_discord
ExecStart=/home/user/claude_discord/scripts/webhook-trigger.sh start
ExecStop=/home/user/claude_discord/scripts/webhook-trigger.sh stop
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```

---

## What Gets Excluded

### Automatically Ignored (never staged)
| Pattern | Example |
|---------|---------|
| `.env` files | `.env`, `.env.local`, `.env.production` |
| Key files | `*.pem`, `*.key`, `*.p12` |
| Token files | `*.token`, `*.secret` |
| Database files | `threads.db`, `*.db-shm`, `*.db-wal` |
| Dependencies | `node_modules/` |

### Scanned and Flagged (blocks push)
| Pattern | Example |
|---------|---------|
| Discord tokens | `MTA0N...zE2OA` (64+ chars) |
| OpenAI keys | `sk-proj-...` |
| ETH wallets | `0x28d0...a1ba` |
| AWS keys | `AKIAIOSFODNN7EXAMPLE` |
| Private keys | `-----BEGIN RSA PRIVATE KEY-----` |
| URLs with credentials | `https://user:pass@host.com` |
| System paths | `/home/wls/discord-bot/.env` |

---

## Monitoring

### Check Timer Status
```bash
systemctl --user list-timers
# Shows: NEXT LEFT LAST PASSED UNIT ACTIVATES
# github-auto-push.timer Mon 09:17:00 2 days left - - github-auto-push.timer
```

### Check Webhook Trigger
```bash
systemctl --user status webhook-trigger.service
# Shows: Active: active (running)
```

### View Logs
```bash
# Auto-push logs
journalctl --user -u github-auto-push.service -n 50 --no-pager

# Webhook trigger logs
tail -f /tmp/github-webhook-trigger.log

# All sync logs
tail -f /tmp/github-auto-push.log /tmp/github-webhook-trigger.log
```

### Manual Trigger
```bash
# Trigger weekly timer immediately
systemctl --user start github-auto-push.service

# Trigger webhook manually
./scripts/webhook-trigger.sh stop && ./scripts/webhook-trigger.sh start
```

---

## Troubleshooting

### "Cannot connect to remote"
```bash
# Test GitHub auth
git ls-remote origin HEAD
# If fails: check SSH keys or personal access token
```

### "Secret sanitizer blocked the push"
```bash
# Review what was flagged
cat /tmp/github-auto-push.log

# Fix the issue, then retry
./scripts/github-auto-push.sh
```

### "No local changes to push"
```bash
# Check git status
git status

# If you expect changes but none detected:
# - File might be in .gitignore
# - File might be untracked and flagged as secret
```

### "inotifywait not found"
```bash
sudo apt install inotify-tools
systemctl --user restart webhook-trigger.service
```

---

## Security Best Practices

1. **Never disable sanitizer permanently** — If you use `--no-verify`, revert to normal immediately after
2. **Review auto-generated commits** — Check `git log` weekly to ensure no secrets slipped through
3. **Rotate tokens if leaked** — If a secret was accidentally pushed, rotate it immediately
4. **Use SSH keys for GitHub** — More secure than HTTPS with stored credentials
5. **Separate secrets repo** — Keep `.env` files in a private repo or password manager, never in this repo
