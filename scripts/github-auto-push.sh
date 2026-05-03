#!/bin/bash
# GitHub Auto-Push Script
# Commits any pending changes and pushes to origin
# Excludes secrets, tokens, and sensitive file locations
#
# Usage: ./github-auto-push.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

BRANCH="main"
REMOTE="origin"
LOG_FILE="/tmp/github-auto-push.log"

echo "=== GitHub Auto-Push ===" | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "$LOG_FILE"
echo "Repo: $(git remote get-url $REMOTE 2>/dev/null || echo 'unknown')" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

# Step 1: Check if this is a git repo
if [ ! -d .git ]; then
  echo "[ERROR] Not a git repository" | tee -a "$LOG_FILE"
  exit 1
fi

# Step 2: Check remote connectivity
echo "[CHECK] Testing remote connectivity..." | tee -a "$LOG_FILE"
if ! git ls-remote "$REMOTE" HEAD >/dev/null 2>&1; then
  echo "[ERROR] Cannot connect to remote. Check network or auth." | tee -a "$LOG_FILE"
  exit 1
fi
echo "[PASS] Remote accessible" | tee -a "$LOG_FILE"

# Step 3: Fetch latest changes
echo "[FETCH] Pulling latest changes..." | tee -a "$LOG_FILE"
git fetch "$REMOTE" "$BRANCH" 2>&1 | tee -a "$LOG_FILE"

# Step 4: Check for local changes
echo "[CHECK] Checking for local changes..." | tee -a "$LOG_FILE"
if git diff --quiet && git diff --cached --quiet && [ -z "$(git ls-files --others --exclude-standard)" ]; then
  echo "[INFO] No local changes to push" | tee -a "$LOG_FILE"
  echo "Everything up to date." | tee -a "$LOG_FILE"
  exit 0
fi

# Step 5: Check for untracked files that might contain secrets
echo "[SANITIZE] Checking untracked files..." | tee -a "$LOG_FILE"
untracked=$(git ls-files --others --exclude-standard)
for file in $untracked; do
  if echo "$file" | grep -qE '\.(env|pem|key|token|secret)$'; then
    echo "[WARNING] Ignoring potential secret file: $file" | tee -a "$LOG_FILE"
    echo "$file" >> .git/info/exclude 2>/dev/null || true
  fi
done

# Step 6: Stage changes (excluding sensitive patterns)
echo "[STAGE] Staging changes..." | tee -a "$LOG_FILE"
git add -A 2>&1 | tee -a "$LOG_FILE"

# Step 7: Check if there are staged changes after filtering
if git diff --cached --quiet; then
  echo "[INFO] No staged changes after sanitization" | tee -a "$LOG_FILE"
  exit 0
fi

# Step 8: Check for secrets in staged files
echo "[SCAN] Running secret sanitizer..." | tee -a "$LOG_FILE"
if [ -x "$REPO_ROOT/scripts/secret-sanitizer.sh" ]; then
  if ! "$REPO_ROOT/scripts/secret-sanitizer.sh" 2>&1 | tee -a "$LOG_FILE"; then
    echo "[ERROR] Secret sanitizer blocked the push" | tee -a "$LOG_FILE"
    echo "[ROLLBACK] Unstaging changes..." | tee -a "$LOG_FILE"
    git reset HEAD 2>&1 | tee -a "$LOG_FILE"
    exit 1
  fi
else
  echo "[WARNING] Secret sanitizer not found, skipping scan" | tee -a "$LOG_FILE"
fi

# Step 9: Check if behind remote
echo "[CHECK] Checking if behind remote..." | tee -a "$LOG_FILE"
LOCAL=$(git rev-parse @)
REMOTE_REF=$(git rev-parse "@{u}" 2>/dev/null || echo "")
BASE=$(git merge-base @ "@{u}" 2>/dev/null || echo "")

if [ "$LOCAL" != "$BASE" ] && [ -n "$REMOTE_REF" ]; then
  echo "[WARNING] Remote has changes we don't have. Attempting merge..." | tee -a "$LOG_FILE"
  if ! git merge "$REMOTE/$BRANCH" --no-edit 2>&1 | tee -a "$LOG_FILE"; then
    echo "[ERROR] Merge failed. Manual intervention required." | tee -a "$LOG_FILE"
    exit 1
  fi
fi

# Step 10: Commit with auto-generated message
echo "[COMMIT] Creating commit..." | tee -a "$LOG_FILE"
CHANGED_FILES=$(git diff --cached --name-only | head -20 | sed 's/^/  - /')
FILE_COUNT=$(git diff --cached --name-only | wc -l)

COMMIT_MSG="auto: weekly sync $(date '+%Y-%m-%d')

Files changed: $FILE_COUNT

$CHANGED_FILES

🤖 Auto-sync by systemd timer"

git commit -m "$COMMIT_MSG" 2>&1 | tee -a "$LOG_FILE"

# Step 11: Push to remote
echo "[PUSH] Pushing to $REMOTE/$BRANCH..." | tee -a "$LOG_FILE"
if git push "$REMOTE" "$BRANCH" 2>&1 | tee -a "$LOG_FILE"; then
  echo "" | tee -a "$LOG_FILE"
  echo "[SUCCESS] Push completed at $(date '+%H:%M:%S')" | tee -a "$LOG_FILE"
  echo "Files pushed: $FILE_COUNT" | tee -a "$LOG_FILE"
  exit 0
else
  echo "" | tee -a "$LOG_FILE"
  echo "[ERROR] Push failed" | tee -a "$LOG_FILE"
  exit 1
fi
