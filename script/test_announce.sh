#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLI="$ROOT_DIR/script/announce.py"
TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/nexora-announce-test.XXXXXX")"
trap 'rm -rf "$TMP_DIR"' EXIT

# 1. Valid bilingual publish --dry-run + --output
OUT_JSON="$TMP_DIR/publish.json"
python3 "$CLI" publish \
  --title "服务端维护通知" \
  --body "今晚凌晨 02:00 将例行升级节点路由。" \
  --kind maintenance \
  --badge "维护公告" \
  --title-en "Scheduled Maintenance" \
  --body-en "Node routes will be upgraded at 02:00." \
  --badge-en "Maintenance" \
  --action-title "查看状态" \
  --action-title-en "View Status" \
  --action-url "https://github.com/changmax9/nexora/releases" \
  --starts-at "2026-11-27T22:00:00+08:00" \
  --expires-at "2026-12-01T00:00:00Z" \
  --min-version "1.0.0" \
  --max-version "1.2.0" \
  --display-policy daily \
  --id "20261127-maint" \
  --dry-run \
  --output "$OUT_JSON" >/dev/null

python3 - "$OUT_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data["schemaVersion"] == 1
ann = data["announcement"]
assert ann["id"] == "20261127-maint"
assert ann["kind"] == "maintenance"
assert ann["displayPolicy"] == "daily"
assert ann["startsAt"] == "2026-11-27T14:00:00Z"
assert ann["expiresAt"] == "2026-12-01T00:00:00Z"
assert ann["minVersion"] == "1.0.0"
assert ann["maxVersion"] == "1.2.0"
assert ann["actionURL"] == "https://github.com/changmax9/nexora/releases"
assert ann["localizations"]["en"]["title"] == "Scheduled Maintenance"
assert ann["localizations"]["en"]["actionTitle"] == "View Status"
PY
echo "PASS: publish dry-run produces valid bilingual schema"

# 2. Clear --dry-run + --output
CLEAR_JSON="$TMP_DIR/clear.json"
python3 "$CLI" clear --dry-run --output "$CLEAR_JSON" >/dev/null
python3 - "$CLEAR_JSON" <<'PY'
import json, sys
data = json.load(open(sys.argv[1], encoding="utf-8"))
assert data == {"schemaVersion": 1, "announcement": None}
PY
echo "PASS: clear dry-run produces null announcement envelope"

# 3. Reject non-HTTPS or credentialed URLs
if python3 "$CLI" publish --title "T" --body "B" --action-url "http://example.com" --dry-run >/dev/null 2>&1; then
  echo "FAIL: expected http:// action-url to be rejected" >&2
  exit 1
fi
if python3 "$CLI" publish --title "T" --body "B" --action-url "https://user:pass@example.com" --dry-run >/dev/null 2>&1; then
  echo "FAIL: expected credentialed action-url to be rejected" >&2
  exit 1
fi
echo "PASS: invalid action URLs rejected"

# 4. Reject startsAt > expiresAt
if python3 "$CLI" publish --title "T" --body "B" --starts-at "2026-12-02T00:00:00Z" --expires-at "2026-12-01T00:00:00Z" --dry-run >/dev/null 2>&1; then
  echo "FAIL: expected inverted time window to be rejected" >&2
  exit 1
fi
echo "PASS: inverted date range rejected"

# 5. Reject oversized (>64 KiB) payloads
BIG_FILE="$TMP_DIR/big.txt"
python3 - "$BIG_FILE" <<'PY'
import sys
with open(sys.argv[1], "w", encoding="utf-8") as f:
    f.write("A" * 70000)
PY
if python3 "$CLI" publish --title "Large" --body-file "$BIG_FILE" --dry-run >/dev/null 2>&1; then
  echo "FAIL: expected >64 KiB payload to be rejected" >&2
  exit 1
fi
echo "PASS: oversized payload rejected"

# 6. Reject empty title or body
if python3 "$CLI" publish --title "   " --body "Hello" --dry-run >/dev/null 2>&1; then
  echo "FAIL: expected blank title to be rejected" >&2
  exit 1
fi
if python3 "$CLI" publish --title "Hello" --body "   " --dry-run >/dev/null 2>&1; then
  echo "FAIL: expected blank body to be rejected" >&2
  exit 1
fi
echo "PASS: blank title/body rejected"
for operation in publish clear; do
  args=()
  if [[ "$operation" == publish ]]; then args+=(--title T --body B); fi
  if python3 "$CLI" "$operation" ${args[@]+"${args[@]}"} --branch main --dry-run >/dev/null 2>&1; then
    echo "FAIL: $operation accepted main as the destination" >&2
    exit 1
  fi
done
echo "PASS: writes are restricted to the announcements branch"
echo "Announcement CLI: all 7 offline regression cases passed."
