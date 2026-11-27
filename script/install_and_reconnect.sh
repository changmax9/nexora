#!/usr/bin/env bash
set -euo pipefail

MODE="${1:---check}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
STAGED_APP="$ROOT_DIR/dist/Nexora.app"
INSTALLED_APP="/Applications/Nexora.app"

if [[ "$MODE" != "--check" && "$MODE" != "--apply" ]]; then
  echo "usage: $0 [--check|--apply]" >&2
  exit 2
fi
test -x "$STAGED_APP/Contents/MacOS/Nexora"
test -d "$INSTALLED_APP"
test -w /Applications
/usr/bin/codesign --verify --deep --strict "$STAGED_APP"

if [[ "$MODE" == "--check" ]]; then
  echo "Ready to install $STAGED_APP and reconnect locally. The running app was not changed."
  exit 0
fi

# Finish the copies before touching the active connection. All subsequent
# steps run locally, including the new app's --connect startup request.
BACKUP_DIR="$ROOT_DIR/dist/Backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"
/usr/bin/ditto "$INSTALLED_APP" "$BACKUP_DIR/Nexora.app"
INCOMING_DIR="$(mktemp -d /Applications/.Nexora-network-fix.XXXXXX)"
/usr/bin/ditto "$STAGED_APP" "$INCOMING_DIR/Nexora.app"
/usr/bin/codesign --verify --deep --strict "$INCOMING_DIR/Nexora.app"

if pgrep -x Nexora >/dev/null; then
  /usr/bin/osascript -e 'tell application id "com.maxchang.Nexora" to quit'
  for _ in {1..50}; do
    pgrep -x Nexora >/dev/null || break
    sleep 0.1
  done
  if pgrep -x Nexora >/dev/null; then
    /bin/rm -rf "$INCOMING_DIR"
    echo "Nexora did not quit. Installation stopped; the active app was preserved." >&2
    exit 1
  fi
fi

mv "$INSTALLED_APP" "$INCOMING_DIR/previous.app"
if ! mv "$INCOMING_DIR/Nexora.app" "$INSTALLED_APP"; then
  mv "$INCOMING_DIR/previous.app" "$INSTALLED_APP"
  /usr/bin/open -n "$INSTALLED_APP"
  exit 1
fi
/usr/bin/open -n "$INSTALLED_APP" --args --connect

for _ in {1..20}; do
  PROXY_STATE="$(/usr/sbin/scutil --proxy)"
  PROXY_ENABLED="$(awk '/HTTPEnable :/ { print $3; exit }' <<<"$PROXY_STATE")"
  PROXY_PORT="$(awk '/HTTPPort :/ { print $3; exit }' <<<"$PROXY_STATE")"
  PROXY_HOST="$(awk '/HTTPProxy :/ { print $3; exit }' <<<"$PROXY_STATE")"
  if [[ "$PROXY_ENABLED" == "1" && "$PROXY_HOST" == "127.0.0.1" && "$PROXY_PORT" =~ ^[0-9]+$ ]]; then
    if /usr/bin/curl --proxy "http://127.0.0.1:$PROXY_PORT" --noproxy '' \
      --connect-timeout 2 --max-time 4 --silent --output /dev/null https://chatgpt.com; then
      /bin/rm -rf "$INCOMING_DIR"
      echo "Installed and reconnected. Previous app: $BACKUP_DIR/Nexora.app"
      exit 0
    fi
  fi
  sleep 0.5
done

echo "Installed, but reconnection was not confirmed. Check Nexora's visible error. Backup: $BACKUP_DIR/Nexora.app" >&2
exit 1
