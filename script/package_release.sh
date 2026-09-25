#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <version, for example 1.2.0> [--local]" >&2
  exit 2
fi

LOCAL_PACKAGE=false
if [[ "${2:-}" == "--local" ]]; then
  LOCAL_PACKAGE=true
elif [[ $# -eq 2 ]]; then
  echo "error: unknown packaging option: $2" >&2
  exit 2
fi
if [[ -z "${CODE_SIGN_IDENTITY:-}" || "$CODE_SIGN_IDENTITY" == "-" ]]; then
  echo "error: an Apple signing identity is required for the TUN helper" >&2
  exit 1
fi
VERSION="${1#v}"
if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: version must have the form 1.2.3" >&2
  exit 2
fi
TAG="v$VERSION"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/Nexora.app"
DMG_NAME="Nexora-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
APPCAST_PATH="$DIST_DIR/appcast.xml"
SIGN_UPDATE="$ROOT_DIR/.build/artifacts/sparkle/Sparkle/bin/sign_update"
IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "$VERSION"
if (( 10#$VERSION_MINOR > 99 || 10#$VERSION_PATCH > 9999 )); then
  echo "error: version exceeds the supported build-number range" >&2
  exit 2
fi
BUILD_NUMBER="${APP_BUILD:-$((10#$VERSION_MAJOR * 1000000 + 10#$VERSION_MINOR * 10000 + 10#$VERSION_PATCH))}"

if [[ "$LOCAL_PACKAGE" == false && -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY is required" >&2
  exit 1
fi

APP_VERSION="$VERSION" \
APP_BUILD="$BUILD_NUMBER" \
SPARKLE_ENABLE_AUTOMATIC_CHECKS="$([[ "$LOCAL_PACKAGE" == true ]] && echo false || echo true)" \
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

/usr/bin/codesign --verify --deep --strict "$APP_BUNDLE"
STAGING_DIR="$(mktemp -d "$DIST_DIR/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT
/usr/bin/ditto "$APP_BUNDLE" "$STAGING_DIR/Nexora.app"
ln -s /Applications "$STAGING_DIR/Applications"
rm -f "$DMG_PATH" "$APPCAST_PATH"
/usr/bin/hdiutil create \
  -volname "Nexora" \
  -srcfolder "$STAGING_DIR" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

/usr/bin/hdiutil verify "$DMG_PATH"
if [[ "$LOCAL_PACKAGE" == true ]]; then
  echo "Local test DMG (no Sparkle appcast or notarization): $DMG_PATH"
  exit 0
fi

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
