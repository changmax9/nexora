#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
APP_NAME="Nexora"
BUNDLE_ID="com.maxchang.Nexora"
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="${APP_VERSION:-0.1.0}"
SPARKLE_ENABLE_AUTOMATIC_CHECKS="${SPARKLE_ENABLE_AUTOMATIC_CHECKS:-false}"

case "$SPARKLE_ENABLE_AUTOMATIC_CHECKS" in
  true|false)
    ;;
  *)
    echo "error: SPARKLE_ENABLE_AUTOMATIC_CHECKS must be true or false" >&2
    exit 2
    ;;
esac

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_FRAMEWORKS="$APP_CONTENTS/Frameworks"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
CORE_BINARY="$ROOT_DIR/core/mihomo"
GEO_DATA_SOURCE="$ROOT_DIR/runtime-assets"
GEO_DATA_DESTINATION="$APP_RESOURCES/GeoData"
APP_ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.icns"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FEED_URL="https://github.com/changmax9/nexora/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="nNIrqbotaDGgjLrL4Rhx42PoCFiqj04ktB+FidHXvF8="

if pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

swift build -c "$BUILD_CONFIGURATION"
BUILD_BINARY="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
mkdir -p "$APP_FRAMEWORKS"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -d "$SPARKLE_FRAMEWORK" ]]; then
  cp -R "$SPARKLE_FRAMEWORK" "$APP_FRAMEWORKS/"
  /usr/bin/install_name_tool \
    -add_rpath "@executable_path/../Frameworks" \
    "$APP_BINARY" 2>/dev/null || true
else
  echo "error: Sparkle.framework is missing; run swift package resolve" >&2
  exit 1
fi
if [[ -x "$CORE_BINARY" ]]; then
  cp "$CORE_BINARY" "$APP_RESOURCES/mihomo"
  chmod +x "$APP_RESOURCES/mihomo"
else
  echo "warning: Mihomo core is missing; run ./script/bootstrap.sh" >&2
fi
if [[ -d "$GEO_DATA_SOURCE" ]]; then
  mkdir -p "$GEO_DATA_DESTINATION"
  while IFS= read -r asset; do
    cp "$asset" "$GEO_DATA_DESTINATION/"
  done < <(find "$GEO_DATA_SOURCE" -maxdepth 1 -type f -print)
fi
if [[ -f "$APP_ICON_SOURCE" ]]; then
  cp "$APP_ICON_SOURCE" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Nexora</string>
  <key>CFBundleDisplayName</key>
  <string>Nexora</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>${APP_BUILD:-1}</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>SUFeedURL</key>
  <string>$SPARKLE_FEED_URL</string>
  <key>SUPublicEDKey</key>
  <string>$SPARKLE_PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key>
  <$SPARKLE_ENABLE_AUTOMATIC_CHECKS/>
  <key>SUAllowsAutomaticUpdates</key>
  <false/>
  <key>SUScheduledCheckInterval</key>
  <integer>86400</integer>
</dict>
</plist>
PLIST

/usr/bin/codesign --force --deep --sign - "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  --stage|stage)
    ;;
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  *)
    echo "usage: $0 [run|--stage|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
