#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
# Xcode 27's SwiftPM build backend currently records the deployment target as
# LC_BUILD_VERSION.sdk (15.0), which opts AppKit into legacy window controls.
# The native backend records the selected SDK correctly. Keep this overridable
# so we can return to the default backend when its SDK metadata is fixed.
SWIFT_BUILD_SYSTEM="${SWIFT_BUILD_SYSTEM:-native}"
MACOS_SDK_PATH="$(xcrun --sdk macosx --show-sdk-path)"
APP_NAME="Nexora"
BUNDLE_ID="com.maxchang.Nexora"
MIN_SYSTEM_VERSION="15.0"
APP_VERSION="${APP_VERSION:-0.2.0}"
if [[ ! "$APP_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  echo "error: APP_VERSION must have the form 1.2.3" >&2
  exit 2
fi
VERSION_MAJOR="${BASH_REMATCH[1]}"
VERSION_MINOR="${BASH_REMATCH[2]}"
VERSION_PATCH="${BASH_REMATCH[3]}"
if (( 10#$VERSION_MINOR > 99 || 10#$VERSION_PATCH > 9999 )); then
  echo "error: APP_VERSION exceeds the supported build-number range" >&2
  exit 2
fi
APP_BUILD="${APP_BUILD:-$((10#$VERSION_MAJOR * 1000000 + 10#$VERSION_MINOR * 10000 + 10#$VERSION_PATCH))}"
SPARKLE_ENABLE_AUTOMATIC_CHECKS="${SPARKLE_ENABLE_AUTOMATIC_CHECKS:-false}"
CODE_SIGN_IDENTITY="${CODE_SIGN_IDENTITY:--}"

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
APP_ICON_SOURCE="$ROOT_DIR/Assets/NexoraIcon.icon"
SPARKLE_FRAMEWORK="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
SPARKLE_FEED_URL="https://github.com/changmax9/nexora/releases/latest/download/appcast.xml"
SPARKLE_PUBLIC_KEY="nNIrqbotaDGgjLrL4Rhx42PoCFiqj04ktB+FidHXvF8="

if [[ "$MODE" != "--stage" && "$MODE" != "stage" ]] && pgrep -x "$APP_NAME" >/dev/null 2>&1; then
  /usr/bin/osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
  for _ in {1..20}; do
    pgrep -x "$APP_NAME" >/dev/null 2>&1 || break
    sleep 0.1
  done
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
fi

SWIFT_BUILD_ARGS=(--build-system "$SWIFT_BUILD_SYSTEM" --sdk "$MACOS_SDK_PATH" -c "$BUILD_CONFIGURATION")
swift build "${SWIFT_BUILD_ARGS[@]}"
BUILD_BINARY="$(swift build "${SWIFT_BUILD_ARGS[@]}" --show-bin-path)/$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS"
mkdir -p "$APP_RESOURCES"
mkdir -p "$APP_FRAMEWORKS"
mkdir -p "$APP_CONTENTS/Library/LaunchDaemons"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$(dirname "$BUILD_BINARY")/NexoraTUNHelper" "$APP_MACOS/NexoraTUNHelper"
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
ICON_BUILD_DIR="$(mktemp -d "$DIST_DIR/icon-build.XXXXXX")"
xcrun actool \
  --compile "$ICON_BUILD_DIR" \
  --platform macosx \
  --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
  --app-icon NexoraIcon \
  --output-partial-info-plist "$ICON_BUILD_DIR/icon-info.plist" \
  "$APP_ICON_SOURCE" >/dev/null
cp "$ICON_BUILD_DIR/Assets.car" "$APP_RESOURCES/Assets.car"
cp "$ICON_BUILD_DIR/NexoraIcon.icns" "$APP_RESOURCES/NexoraIcon.icns"
rm -rf "$ICON_BUILD_DIR"

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
  <string>NexoraIcon</string>
  <key>CFBundleIconName</key>
  <string>NexoraIcon</string>
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

cat >"$APP_CONTENTS/Library/LaunchDaemons/com.maxchang.Nexora.TUNHelper.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>Label</key><string>com.maxchang.Nexora.TUNHelper</string>
  <key>BundleProgram</key><string>Contents/MacOS/NexoraTUNHelper</string>
  <key>MachServices</key><dict><key>com.maxchang.Nexora.TUNHelper</key><true/></dict>
  <key>AssociatedBundleIdentifiers</key><array><string>com.maxchang.Nexora</string></array>
  <key>ProcessType</key><string>Interactive</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" --identifier com.maxchang.Nexora.TUNHelper "$APP_MACOS/NexoraTUNHelper"
if [[ -x "$APP_RESOURCES/mihomo" ]]; then
  /usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" --identifier com.maxchang.Nexora.mihomo "$APP_RESOURCES/mihomo"
fi
# Sign the enclosing app last without rewriting the helper's pinned identifier.
/usr/bin/codesign --force --sign "$CODE_SIGN_IDENTITY" "$APP_BUNDLE"

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
