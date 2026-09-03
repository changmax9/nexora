#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <version, for example 1.2.0>" >&2
  exit 2
fi

VERSION="${1#v}"
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Nexora.app"
DMG_NAME="Nexora-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APPCAST_PATH="$DIST_DIR/appcast.xml"
SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
BUILD_NUMBER="${APP_BUILD:-${GITHUB_RUN_NUMBER:-1}}"

if [[ -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY is required" >&2
  exit 1
fi

APP_VERSION="$VERSION" \
APP_BUILD="$BUILD_NUMBER" \
SPARKLE_ENABLE_AUTOMATIC_CHECKS=true \
BUILD_CONFIGURATION=release \
"$ROOT_DIR/script/build_and_run.sh" --stage

if [[ ! -x "$APP_BUNDLE/Contents/Resources/mihomo" ]]; then
  echo "error: packaged app is missing the Mihomo core" >&2
  exit 1
fi
for asset in geoip.dat geoip.metadb geosite.dat ASN.mmdb; do
  if [[ ! -f "$APP_BUNDLE/Contents/Resources/GeoData/$asset" ]]; then
    echo "error: packaged app is missing GeoData/$asset" >&2
    exit 1
  fi
done

rm -f "$DMG_PATH" "$APPCAST_PATH"
/usr/bin/hdiutil create \
  -volname "Nexora" \
  -srcfolder "$APP_BUNDLE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

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

PREVIOUS_TAG="$(git -C "$ROOT_DIR" describe --tags --abbrev=0 HEAD^ 2>/dev/null || true)"
if [[ -n "$PREVIOUS_TAG" ]]; then
  RELEASE_COMMITS="$(git -C "$ROOT_DIR" log "$PREVIOUS_TAG"..HEAD --pretty='%s')"
else
  RELEASE_COMMITS="$(git -C "$ROOT_DIR" log -20 --pretty='%s')"
fi
RELEASE_ITEMS="$(
  printf '%s\n' "$RELEASE_COMMITS" \
    | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g' \
    | sed -e 's/^/<li>/' -e 's/$/<\/li>/'
)"

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
        <h2>Nexora $VERSION</h2>
        <ul>$RELEASE_ITEMS</ul>
      ]]></description>
      <enclosure
        url="https://github.com/changmax9/nexora/releases/download/$TAG/$DMG_NAME"
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

echo "$DMG_PATH"
echo "$APPCAST_PATH"
