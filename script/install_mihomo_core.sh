#!/usr/bin/env bash
set -euo pipefail

VERSION="${MIHOMO_VERSION:-v1.19.34}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CORE_DIR="$ROOT_DIR/core"
CORE_PATH="$CORE_DIR/mihomo"
mkdir -p "$CORE_DIR"
# Keep staging on the same volume so the final rename is atomic.
TMP_DIR="$(mktemp -d "$CORE_DIR/.mihomo-install.XXXXXX")"

cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

case "$(uname -m)" in
  arm64)
    ASSET="mihomo-darwin-arm64-${VERSION}.gz"
    DEFAULT_SHA256="1a7a20eca63fbbaec90137717465bfde488d0db2a3a79b8fadebf9b2545b6e4c"
    ;;
  x86_64)
    ASSET="mihomo-darwin-amd64-compatible-${VERSION}.gz"
    DEFAULT_SHA256="703bceaa494732fa456f47e6ac2f06bf0bc5593d4c927d5f61e10f1a31039c37"
    ;;
  *)
    echo "Unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

# Digests are from the official v1.19.34 GitHub Release assets. Custom
# versions must supply their own digest rather than bypass verification.
if [[ "$VERSION" == "v1.19.34" ]]; then
  EXPECTED_SHA256="${MIHOMO_SHA256:-$DEFAULT_SHA256}"
else
  EXPECTED_SHA256="${MIHOMO_SHA256:-}"
fi
if [[ ! "$EXPECTED_SHA256" =~ ^[[:xdigit:]]{64}$ ]]; then
  echo "error: MIHOMO_SHA256 must be the official asset's SHA-256 for $VERSION" >&2
  exit 1
fi

URL="https://github.com/MetaCubeX/mihomo/releases/download/${VERSION}/${ASSET}"

echo "Downloading Mihomo $VERSION"
curl --fail --location --retry 2 --connect-timeout 20 --max-time 300 \
  "$URL" -o "$TMP_DIR/mihomo.gz"
printf '%s  %s\n' "$EXPECTED_SHA256" "$TMP_DIR/mihomo.gz" | shasum -a 256 -c -
gzip -dc "$TMP_DIR/mihomo.gz" > "$TMP_DIR/mihomo"
chmod +x "$TMP_DIR/mihomo"
VERSION_OUTPUT="$("$TMP_DIR/mihomo" -v)"
if [[ "$VERSION_OUTPUT" != *"Mihomo Meta ${VERSION} "* ]]; then
  echo "error: downloaded core did not report the requested version $VERSION" >&2
  exit 1
fi
mv -f "$TMP_DIR/mihomo" "$CORE_PATH"
printf '%s\n' "$VERSION_OUTPUT"
