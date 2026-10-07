#!/usr/bin/env bash
# Copy a homeserver directory into this repo with secrets redacted.
# Usage: scripts/sanitize-copy.sh /path/to/homeserver [dest_dir]   (default dest: ./homeserver)
# Run on the server. ALWAYS review `git diff` before committing.
set -euo pipefail

SRC="${1:?usage: $0 /path/to/homeserver [dest]}"
DEST="$(cd "$(dirname "$0")/.." && pwd)/homeserver"; [ -n "${2:-}" ] && DEST="$2"
mkdir -p "$DEST"; DEST="$(cd "$DEST" && pwd)"

# 1. Copy only text-ish config; skip data, DBs, logs, media, keys, env files.
# Directories that are bulk, caches, app state or hold key material: never copied.
PRUNE='changedetection|node_modules|\.local|\.cache|\.cloakbrowser|cdn-cache|site-packages|Definitions|asp|plugins|telegram-desktop|state|\.git|cache|transcodes|MediaCover|Backups|backups|metadata|data|logs|nssdb|pki'
# Files that hold secrets or runtime data even though they look like config.
SKIP_FILES='(^|/)(secret\.txt|squid-passwords\.txt|.*[Cc]url.*\.txt|state\.json|manual-status\.json|history.*\.txt|last-checksum\.txt|.*-cache\.json|provider-cache\.json|.*\.env|\.env.*|acme\.json|wg.*\.conf)$'
(cd "$SRC" && find . -type f \( -name '*.yml' -o -name '*.yaml' -o -name '*.json' -o -name '*.xml' \
     -o -name '*.conf' -o -name '*.ini' -o -name '*.toml' -o -name '*.sh' -o -name '*.md' \
     -o -name 'Caddyfile' -o -name 'Dockerfile*' -o -name '*.cfg' -o -name '*.txt' \) -print0 2>/dev/null \
  | grep -zvE "(^|/)($PRUNE)(/|$)" | grep -zvE "$SKIP_FILES" \
  | xargs -0 -r cp --parents -t "$DEST" 2>/dev/null || true)
# Drop runtime blobs named by UUID/hash directories (changedetection watches etc.)
find "$DEST" -type f -regextype posix-extended -regex '.*/[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f-]{22}/.*' -delete 2>/dev/null || true
find "$DEST" -type d -empty -delete 2>/dev/null || true

# 2. Redact secrets in the copied files.
#    Group 1 = key, group 2 = separator; value replaced with REDACTED.
KEYS='api[_-]?key|apikey|secret|token|password|passwd|pass|auth|private[_-]?key|client[_-]?secret|jwt|cookie|webhook|salt|hash|username|user'
find "$DEST" -type f -print0 | while IFS= read -r -d '' f; do
  # YAML/ENV/INI style:  KEY: value | KEY=value | "key": "value"
  sed -E -i \
    -e "s#(^|[^A-Za-z0-9])([A-Za-z0-9_.-]*($KEYS)[A-Za-z0-9_.-]*[\"']?[[:space:]]*[:=][[:space:]]*)[\"']?[^\"'[:space:]#,]+[\"']?#\1\2REDACTED#I" \
    -e "s#(<[A-Za-z0-9_]*($KEYS)[A-Za-z0-9_]*>)[^<]+(</)#\1REDACTED\3#I" \
    -e "s#(-[[:space:]]*[A-Za-z0-9_]*($KEYS)[A-Za-z0-9_]*=)[^[:space:]]+#\1REDACTED#I" \
    "$f"
  # Long hex / base64-ish blobs (32+ chars) that are likely keys
  sed -E -i 's#\b[A-Fa-f0-9]{32,}\b#REDACTED_HEX#g' "$f"
  # Private IPs of public hosts, emails, domains are NOT touched: review manually.
done

# 3. Strip secrets from ${VAR} defaults: keep references, they are safe.
echo "Done. Copied to: $DEST"
echo "NEXT: review everything, then scan:"
echo "  git diff --no-index /dev/null $DEST | less"
echo "  gitleaks detect --no-git -s $DEST   (or: docker run --rm -v \"\$PWD:/p\" zricethezav/gitleaks detect --no-git -s /p/homeserver)"
echo "  grep -rniE 'REDACTED' $DEST | head   # confirm redactions landed"
