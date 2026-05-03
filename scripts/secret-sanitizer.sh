#!/bin/bash
# Secret Sanitizer - Pre-push hook
# Scans staged files for secrets, tokens, and sensitive paths
# Blocks push if secrets are found
#
# Usage: ./secret-sanitizer.sh [--auto-fix]

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXIT_CODE=0

# Patterns that indicate secrets
SECRET_PATTERNS=(
  # Discord tokens (64-72 char alphanumeric)
  '[A-Za-z0-9_-]{64,72}'
  # API keys (common prefixes)
  'sk-[a-zA-Z0-9]{20,}'
  'Bearer [a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+'
  # Wallet addresses (ETH/BTC)
  '0x[a-fA-F0-9]{40}'
  'bc1[a-zA-Z0-9]{25,62}'
  # Private keys
  '-----BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY-----'
  # Passwords in URLs
  '://[^/]+:[^/]+@'
  # AWS keys
  'AKIA[0-9A-Z]{16}'
  # Generic high-entropy strings that look like secrets
)

# Paths that should never be committed
FORBIDDEN_PATHS=(
  '.env'
  '.env.*'
  '*.pem'
  '*.key'
  'secrets/'
  'tokens/'
  'threads.db'
  '*.db-shm'
  '*.db-wal'
  'node_modules/'
)

# Absolute paths that reveal system structure (sanitize in docs)
SYSTEM_PATH_PATTERNS=(
  '/home/wls/'
  '/home/[a-z]+/'
  '/root/'
  '/etc/passwd'
)

echo "=== Secret Sanitizer ==="
echo "Scanning repository for secrets and sensitive data..."
echo ""

# Check 1: Forbidden files
for pattern in "${FORBIDDEN_PATHS[@]}"; do
  matches=$(find "$REPO_ROOT" -name "$pattern" -not -path "$REPO_ROOT/.git/*" 2>/dev/null || true)
  if [ -n "$matches" ]; then
    echo "[BLOCKED] Forbidden file pattern found: $pattern"
    echo "$matches"
    EXIT_CODE=1
  fi
done

# Check 2: Secrets in tracked files
if [ -d "$REPO_ROOT/.git" ]; then
  tracked_files=$(git -C "$REPO_ROOT" diff --cached --name-only 2>/dev/null || git -C "$REPO_ROOT" ls-files)

  for file in $tracked_files; do
    filepath="$REPO_ROOT/$file"
    [ -f "$filepath" ] || continue

    # Skip binary files
    if file "$filepath" | grep -q 'binary'; then
      continue
    fi

    for pattern in "${SECRET_PATTERNS[@]}"; do
      matches=$(grep -n -E "$pattern" "$filepath" 2>/dev/null | head -5 || true)
      if [ -n "$matches" ]; then
        echo "[WARNING] Potential secret in $file:"
        echo "$matches"
        echo ""
        EXIT_CODE=1
      fi
    done
  done
fi

# Check 3: System paths in markdown docs
md_files=$(find "$REPO_ROOT" -name '*.md' -not -path "$REPO_ROOT/.git/*" 2>/dev/null)
for file in $md_files; do
  for pattern in "${SYSTEM_PATH_PATTERNS[@]}"; do
    matches=$(grep -n "$pattern" "$file" 2>/dev/null | head -3 || true)
    if [ -n "$matches" ]; then
      echo "[INFO] System path found in $file (review if sensitive):"
      echo "$matches"
      echo ""
    fi
  done
done

if [ $EXIT_CODE -ne 0 ]; then
  echo ""
  echo "[FAIL] Secret sanitizer found issues. Push blocked."
  echo "Fix the issues above before pushing."
  echo "If these are false positives, use: git push --no-verify"
  exit 1
else
  echo "[PASS] No secrets or forbidden files detected."
  exit 0
fi
