# Auto-Sync to GitHub

> Automatically push local changes to GitHub with secret sanitization. Works for a single repo or all your repos.

---

## Two Modes

| Mode | Use Case | Script | Timer |
|------|----------|--------|-------|
| **Single-repo** | Sync only `claude_discord` | `github-auto-push.sh` | `github-auto-push.timer` |
| **Multi-repo** | Sync ALL `wilsonhoe/*` repos | `multi-repo-sync.sh` | `multi-repo-sync.timer` |

Use **multi-repo** if you maintain multiple GitHub repositories locally. Use **single-repo** if you only care about this one.

---

## Multi-Repo Sync (Recommended)

### What It Does

Scans `$HOME` for all git repositories, finds those with `github.com/wilsonhoe/*` remotes, and syncs each one:

1. **Auto-discovers repos** — Finds `.git` directories up to depth 3
2. **Skips forks & deps** — ComfyUI, SifNode, PrivacyLayer, Stellar-Guilds, private repos
3. **Sanitizes each repo** — Runs secret scan before every push
4. **Auto-commits** — Generic commit message with file count and repo name
5. **Fetches & merges** — Pulls remote changes first, handles conflicts
6. **Pushes** — Sends to `origin` on current branch
7. **Logs everything** — Per-repo status in `~/.local/share/github-auto-sync/`

### Quick Setup

```bash
cd ~/claude_discord
chmod +x scripts/*.sh

# Install multi-repo timer
cp systemd/multi-repo-sync.timer ~/.config/systemd/user/
cp systemd/multi-repo-sync.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now multi-repo-sync.timer

# Verify
systemctl --user list-timers
# Shows: multi-repo-sync.timer Mon 09:17:00 ...
```

### Dry Run (Test Before Enabling)

```bash
cd ~/claude_discord
./scripts/multi-repo-sync.sh --dry-run
```

This shows which repos would be synced without actually committing or pushing.

### Skipped Repos (Hardcoded)

| Repo | Reason |
|------|--------|
| `ComfyUI` | Large upstream dependency |
| `self-hosted-ai-starter-kit` | Upstream project |
| `SifNode` | Fork |
| `PrivacyLayer` | Fork |
| `Stellar-Guilds` | Fork |
| `.gstack` | Private session memory |
| `gstack-brain-wls` | Private |
| `Digital-Brain` | Private |

Add more to the `SKIP_REPOS` array in `scripts/multi-repo-sync.sh`.

### Logs

```bash
# Latest sync log
ls -lt ~/.local/share/github-auto-sync/ | head -5

# View last sync
tail -50 ~/.local/share/github-auto-sync/multi-repo-sync-$(date +%Y%m%d)*.log

# All syncs via journal
journalctl --user -u multi-repo-sync.service -n 100 --no-pager
```

---

## Single-Repo Sync

Use this if you only want to sync `claude_discord` and nothing else.

### Quick Setup

```bash
cd ~/claude_discord
chmod +x scripts/*.sh

# Install single-repo timer + webhook
cp systemd/github-auto-push.timer ~/.config/systemd/user/
cp systemd/github-auto-push.service ~/.config/systemd/user/
cp systemd/webhook-trigger.service ~/.config/systemd/user/

systemctl --user daemon-reload
systemctl --user enable --now github-auto-push.timer
systemctl --user enable --now webhook-trigger.service
```

### Scripts

#### `scripts/github-auto-push.sh`

Main auto-push script for one repo:

1. Checks remote connectivity
2. Fetches latest changes from GitHub
3. Detects local changes
4. Ignores potential secret files (`.env`, `.pem`, etc.)
5. Stages all safe changes
6. Runs secret sanitizer on staged files
7. Commits with auto-generated message
8. Pushes to `origin main`
9. Logs everything to `/tmp/github-auto-push.log`

#### `scripts/secret-sanitizer.sh`

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

# As git pre-push hook
ln -sf ../../scripts/secret-sanitizer.sh .git/hooks/pre-push
```

**If false positive:**
```bash
git push --no-verify
```

#### `scripts/webhook-trigger.sh`

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

### Check Timers
```bash
systemctl --user list-timers
# Shows: NEXT LEFT LAST PASSED UNIT ACTIVATES
# multi-repo-sync.timer     Mon 09:17:00 2 days left
# github-auto-push.timer    Mon 09:17:00 2 days left
```

### Check Services
```bash
systemctl --user status multi-repo-sync.service
systemctl --user status webhook-trigger.service
```

### View Logs
```bash
# Multi-repo logs
ls -lt ~/.local/share/github-auto-sync/
journalctl --user -u multi-repo-sync.service -n 50 --no-pager

# Single-repo logs
journalctl --user -u github-auto-push.service -n 50 --no-pager
tail -f /tmp/github-webhook-trigger.log
```

### Manual Trigger
```bash
# Multi-repo sync now
systemctl --user start multi-repo-sync.service

# Single-repo sync now
systemctl --user start github-auto-push.service

# Webhook restart
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
cat ~/.local/share/github-auto-sync/multi-repo-sync-*.log

# Fix the issue, then retry
./scripts/multi-repo-sync.sh
```

### "No local changes to push"
```bash
# Check git status in each repo
cd ~/repo-name && git status

# If you expect changes but none detected:
# - File might be in .gitignore
# - File might be untracked and flagged as secret
```

### "Merge failed"
```bash
# Manual intervention needed
cd ~/repo-name
git status
# Resolve conflicts, then:
git add -A && git commit -m "merge: resolve conflicts"
git push origin main
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
5. **Separate secrets repo** — Keep `.env` files in a private repo or password manager, never in public repos
6. **Check skip list** — Review `SKIP_REPOS` in `multi-repo-sync.sh` when you add new repos
