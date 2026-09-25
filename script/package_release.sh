#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 || $# -gt 2 ]]; then
  echo "usage: $0 <version, for example 1.2.0> [--local|--community]" >&2
  exit 2
fi

PACKAGE_MODE="${2:-release}"
case "$PACKAGE_MODE" in
  release|--local|--community) ;;
  *) echo "error: unknown packaging option: $PACKAGE_MODE" >&2; exit 2 ;;
esac
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
IFS=. read -r VERSION_MAJOR VERSION_MINOR VERSION_PATCH <<< "$VERSION"
if (( 10#$VERSION_MINOR > 99 || 10#$VERSION_PATCH > 9999 )); then
  echo "error: version exceeds the supported build-number range" >&2
  exit 2
fi
BUILD_NUMBER="${APP_BUILD:-$((10#$VERSION_MAJOR * 1000000 + 10#$VERSION_MINOR * 10000 + 10#$VERSION_PATCH))}"

if [[ "$PACKAGE_MODE" == release && -z "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  echo "error: SPARKLE_PRIVATE_KEY is required" >&2
  exit 1
fi

APP_VERSION="$VERSION" \
APP_BUILD="$BUILD_NUMBER" \
SPARKLE_ENABLE_AUTOMATIC_CHECKS="$([[ "$PACKAGE_MODE" == --local ]] && echo false || echo true)" \
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
if [[ "$PACKAGE_MODE" != release ]]; then
  echo "Prebuilt DMG (Sparkle appcast signed separately): $DMG_PATH"
  exit 0
fi

APP_BUILD="$BUILD_NUMBER" "$ROOT_DIR/script/sign_release_assets.sh" "$VERSION"

echo "$DMG_PATH"
echo "$APPCAST_PATH"
