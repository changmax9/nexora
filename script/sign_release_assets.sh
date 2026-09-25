#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! "$1" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "usage: $0 <version, for example 1.2.0>" >&2
  exit 2
fi
if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY is required" >&2
  exit 1
fi

VERSION="$1"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
DMG_PATH="$DIST_DIR/Nexora-$VERSION.dmg"
APPCAST_PATH="$DIST_DIR/appcast.xml"
SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "$VERSION"
if (( 10#$VERSION_MINOR > 99 || 10#$VERSION_PATCH > 9999 )); then
  echo "error: version exceeds the supported build-number range" >&2
  exit 2
fi
BUILD_NUMBER="${APP_BUILD:-$((10#$VERSION_MAJOR * 1000000 + 10#$VERSION_MINOR * 10000 + 10#$VERSION_PATCH))}"

test -f "$DMG_PATH"
test -x "$SIGN_UPDATE"
/usr/bin/hdiutil verify "$DMG_PATH" >/dev/null
MOUNT_DIR="$(mktemp -d "$DIST_DIR/release-check.XXXXXX")"
trap '/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true; rmdir "$MOUNT_DIR" 2>/dev/null || true' EXIT
/usr/bin/hdiutil attach -readonly -nobrowse -mountpoint "$MOUNT_DIR" "$DMG_PATH" >/dev/null
APP_BUNDLE="$MOUNT_DIR/Nexora.app"
test -d "$APP_BUNDLE"
test -L "$MOUNT_DIR/Applications"
test -x "$APP_BUNDLE/Contents/MacOS/NexoraTUNHelper"
test -x "$APP_BUNDLE/Contents/Resources/mihomo"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_BUNDLE/Contents/Info.plist")" == "$VERSION"
test "$(/usr/libexec/PlistBuddy -c 'Print CFBundleVersion' "$APP_BUNDLE/Contents/Info.plist")" == "$BUILD_NUMBER"
test "$(/usr/libexec/PlistBuddy -c 'Print SUEnableAutomaticChecks' "$APP_BUNDLE/Contents/Info.plist")" == true
/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
APP_TEAM="$(/usr/bin/codesign -dv --verbose=2 "$APP_BUNDLE" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
HELPER_TEAM="$(/usr/bin/codesign -dv --verbose=2 "$APP_BUNDLE/Contents/MacOS/NexoraTUNHelper" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
CORE_TEAM="$(/usr/bin/codesign -dv --verbose=2 "$APP_BUNDLE/Contents/Resources/mihomo" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
if [[ -z "$APP_TEAM" || "$APP_TEAM" == 'not set' || "$APP_TEAM" != "$HELPER_TEAM" || "$APP_TEAM" != "$CORE_TEAM" ]]; then
  echo "error: the app, TUN helper, and Mihomo must share an Apple signing team" >&2
  exit 1
fi
/usr/bin/hdiutil detach "$MOUNT_DIR" >/dev/null
rmdir "$MOUNT_DIR"
trap - EXIT

SIGNATURE_OUTPUT="$(
  printf '%s' "$SPARKLE_PRIVATE_KEY" \
    | "$SIGN_UPDATE" --ed-key-file - "$DMG_PATH"
)"
ED_SIGNATURE="$(printf '%s' "$SIGNATURE_OUTPUT" | sed -n 's/.*sparkle:edSignature="\([^"]*\)".*/\1/p')"
FILE_LENGTH="$(printf '%s' "$SIGNATURE_OUTPUT" | sed -n 's/.*length="\([^"]*\)".*/\1/p')"
if [[ -z "$ED_SIGNATURE" || -z "$FILE_LENGTH" ]]; then
  echo "error: Sparkle did not return a valid signature" >&2
  exit 1
fi

cat >"$APPCAST_PATH" <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0"
    xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>Nexora Updates</title>
    <item>
      <title>Nexora $VERSION</title>
      <pubDate>$(LC_ALL=C date -R)</pubDate>
      <description><![CDATA[
        <p>See the Nexora $VERSION GitHub release for changes and installation instructions.</p>
      ]]></description>
      <enclosure
        url="https://github.com/changmax9/nexora/releases/download/v$VERSION/Nexora-$VERSION.dmg"
        sparkle:version="$BUILD_NUMBER"
        sparkle:shortVersionString="$VERSION"
        length="$FILE_LENGTH"
        type="application/octet-stream"
        sparkle:edSignature="$ED_SIGNATURE" />
    </item>
  </channel>
</rss>
XML

printf '%s' "$SPARKLE_PRIVATE_KEY" \
  | "$SIGN_UPDATE" --ed-key-file - "$APPCAST_PATH"
printf '%s' "$SPARKLE_PRIVATE_KEY" \
  | "$SIGN_UPDATE" --verify --ed-key-file - "$DMG_PATH" "$ED_SIGNATURE"
printf '%s' "$SPARKLE_PRIVATE_KEY" \
  | "$SIGN_UPDATE" --verify --ed-key-file - "$APPCAST_PATH"

echo "$APPCAST_PATH"
