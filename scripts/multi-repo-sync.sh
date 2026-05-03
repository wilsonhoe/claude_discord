#!/bin/bash
# Multi-Repo GitHub Auto-Sync
# Scans all local git repos under $HOME, filters for wilsonhoe/* remotes,
# runs secret sanitization, auto-commits, and pushes.
#
# Usage: ./multi-repo-sync.sh [--dry-run]

set -euo pipefail

HOME_DIR="${HOME}"
LOG_DIR="${HOME}/.local/share/github-auto-sync"
LOG_FILE="${LOG_DIR}/multi-repo-sync-$(date +%Y%m%d-%H%M%S).log"
MAX_DEPTH=3
DRY_RUN=false

# Repos to skip (forks, large deps, private, or known problematic)
SKIP_REPOS=(
  "ComfyUI"                          # Large dependency, not ours
  "self-hosted-ai-starter-kit"       # Upstream project
  "SifNode"                          # Fork
  "PrivacyLayer"                     # Fork
  "Stellar-Guilds"                   # Fork
  ".gstack"                          # Private/session memory
  "gstack-brain-wls"                 # Private
  "Digital-Brain"                    # Private
)

# Secret patterns (shared with secret-sanitizer.sh)
SECRET_PATTERNS=(
  '[A-Za-z0-9_-]{64,72}'
  'sk-[a-zA-Z0-9]{20,}'
  'Bearer [a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'
  '0x[a-fA-F0-9]{40}'
  'bc1[a-zA-Z0-9]{25,62}'
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  'AKIA[0-9A-Z]{16}'
)

mkdir -p "$LOG_DIR"

echo "=== Multi-Repo GitHub Auto-Sync ===" | tee -a "$LOG_FILE"
echo "Time: $(date '+%Y-%m-%d %H:%M:%S %Z')" | tee -a "$LOG_FILE"
echo "Dry-run: $DRY_RUN" | tee -a "$LOG_FILE"
echo "Max depth: $MAX_DEPTH" | tee -a "$LOG_FILE"
echo "Skip list: ${SKIP_REPOS[*]}" | tee -a "$LOG_FILE"
echo "" | tee -a "$LOG_FILE"

if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
fi

# --- Helper: check if repo should be skipped ---
should_skip() {
  local repo_name="$1"
  for skip in "${SKIP_REPOS[@]}"; do
    if [ "$repo_name" = "$skip" ]; then
      return 0
    fi
  done
  return 1
}

# --- Helper: secret scan on staged files ---
scan_secrets() {
  local repo_path="$1"
  local exit_code=0

  # Get staged + tracked files
  local files
  files=$(git -C "$repo_path" diff --cached --name-only 2>/dev/null || git -C "$repo_path" ls-files)

  for file in $files; do
    # Skip lock files and package metadata (legitimate long hashes)
    if echo "$file" | grep -qE '(package-lock\.json|package\.json|yarn\.lock|pnpm-lock\.yaml|composer\.lock|Cargo\.lock|poetry\.lock|go\.sum)$'; then
      continue
    fi
    local filepath="$repo_path/$file"
    [ -f "$filepath" ] || continue
    if file "$filepath" | grep -q 'binary'; then continue; fi

    for pattern in "${SECRET_PATTERNS[@]}"; do
      if grep -n -E "$pattern" "$filepath" >/dev/null 2>&1; then
        echo "  [BLOCKED] Potential secret in $file" | tee -a "$LOG_FILE"
        exit_code=1
      fi
    done
  done

  # Check for forbidden file types
  local untracked
  untracked=$(git -C "$repo_path" ls-files --others --exclude-standard 2>/dev/null || true)
  for file in $untracked; do
    if echo "$file" | grep -qE '\.(env|pem|key|token|secret)$'; then
      echo "  [BLOCKED] Forbidden file: $file" | tee -a "$LOG_FILE"
      exit_code=1
    fi
  done

  return $exit_code
}

# --- Main sync loop ---
TOTAL=0
SYNCED=0
SKIPPED=0
FAILED=0

while IFS= read -r gitdir; do
  repo_path="$(dirname "$gitdir")"
  repo_name="$(basename "$repo_path")"
  TOTAL=$((TOTAL + 1))

  # Skip if in skip list
  if should_skip "$repo_name"; then
    echo "[$repo_name] SKIP — in skip list" | tee -a "$LOG_FILE"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Check if it has a wilsonhoe GitHub remote (matches both HTTPS and SSH formats)
  remote_url=$(git -C "$repo_path" remote get-url origin 2>/dev/null || echo "")
  if ! echo "$remote_url" | grep -qE "github\.com[/:]wilsonhoe"; then
    echo "[$repo_name] SKIP — not a wilsonhoe repo (remote: ${remote_url:-none})" | tee -a "$LOG_FILE"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  echo "" | tee -a "$LOG_FILE"
  echo "[$repo_name] Checking..." | tee -a "$LOG_FILE"

  # Check for local changes
  if git -C "$repo_path" diff --quiet && git -C "$repo_path" diff --cached --quiet && [ -z "$(git -C "$repo_path" ls-files --others --exclude-standard)" ]; then
    echo "  [INFO] No changes" | tee -a "$LOG_FILE"
    continue
  fi

  # Stage changes
  echo "  [STAGE] Adding changes..." | tee -a "$LOG_FILE"
  if [ "$DRY_RUN" = false ]; then
    git -C "$repo_path" add -A 2>&1 | tee -a "$LOG_FILE"
  fi

  # Secret scan
  echo "  [SCAN] Running secret sanitizer..." | tee -a "$LOG_FILE"
  if ! scan_secrets "$repo_path"; then
    echo "  [ERROR] Secret sanitizer blocked push for $repo_name" | tee -a "$LOG_FILE"
    git -C "$repo_path" reset HEAD 2>/dev/null || true
    FAILED=$((FAILED + 1))
    continue
  fi

  # Check if still staged after scan
  if git -C "$repo_path" diff --cached --quiet; then
    echo "  [INFO] No staged changes after sanitization" | tee -a "$LOG_FILE"
    continue
  fi

  # Commit
  file_count=$(git -C "$repo_path" diff --cached --name-only | wc -l)
  commit_msg="auto: weekly sync $(date '+%Y-%m-%d')

Files changed: $file_count
Repo: $repo_name

🤖 Auto-sync by multi-repo sync"

  echo "  [COMMIT] $file_count files" | tee -a "$LOG_FILE"
  if [ "$DRY_RUN" = false ]; then
    git -C "$repo_path" commit -m "$commit_msg" 2>&1 | tee -a "$LOG_FILE"
  fi

  # Fetch & merge remote changes
  echo "  [FETCH] Pulling latest from origin..." | tee -a "$LOG_FILE"
  if [ "$DRY_RUN" = false ]; then
    git -C "$repo_path" fetch origin 2>&1 | tee -a "$LOG_FILE"
    if ! git -C "$repo_path" merge-base --is-ancestor HEAD origin/main 2>/dev/null; then
      echo "  [MERGE] Remote has changes, merging..." | tee -a "$LOG_FILE"
      git -C "$repo_path" merge origin/main --no-edit 2>&1 | tee -a "$LOG_FILE" || {
        echo "  [ERROR] Merge failed for $repo_name" | tee -a "$LOG_FILE"
        FAILED=$((FAILED + 1))
        continue
      }
    fi
  fi

  # Push
  echo "  [PUSH] Pushing to origin..." | tee -a "$LOG_FILE"
  if [ "$DRY_RUN" = false ]; then
    if git -C "$repo_path" push origin "$(git -C "$repo_path" branch --show-current)" 2>&1 | tee -a "$LOG_FILE"; then
      echo "  [SUCCESS] $repo_name synced" | tee -a "$LOG_FILE"
      SYNCED=$((SYNCED + 1))
    else
      echo "  [ERROR] Push failed for $repo_name" | tee -a "$LOG_FILE"
      FAILED=$((FAILED + 1))
    fi
  else
    echo "  [DRY-RUN] Would push $repo_name" | tee -a "$LOG_FILE"
    SYNCED=$((SYNCED + 1))
  fi

done < <(find "$HOME_DIR" -maxdepth "$MAX_DEPTH" -type d -name .git 2>/dev/null)

# --- Summary ---
echo "" | tee -a "$LOG_FILE"
echo "=== Sync Complete ===" | tee -a "$LOG_FILE"
echo "Total repos scanned: $TOTAL" | tee -a "$LOG_FILE"
echo "Synced:              $SYNCED" | tee -a "$LOG_FILE"
echo "Skipped:             $SKIPPED" | tee -a "$LOG_FILE"
echo "Failed:              $FAILED" | tee -a "$LOG_FILE"
echo "Log:                 $LOG_FILE" | tee -a "$LOG_FILE"

if [ $FAILED -gt 0 ]; then
  exit 1
fi
