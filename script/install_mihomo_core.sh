#!/usr/bin/env bash
set -euo pipefail

VERSION="${MIHOMO_VERSION:-v1.19.33}"
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
    DEFAULT_SHA256="060b64b0f2c9a310831db0fe4adb2878de67bfa606c311813c1f13966aa504b6"
    ;;
  x86_64)
    ASSET="mihomo-darwin-amd64-compatible-${VERSION}.gz"
    DEFAULT_SHA256="eefe967b74312f70b64efa0dfa54929d00c7af8e94416e1b12df09863a40f35b"
    ;;
  *)
    echo "Unsupported macOS architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

# Digests are from the official v1.19.33 GitHub Release assets. Custom
# versions must supply their own digest rather than bypass verification.
if [[ "$VERSION" == "v1.19.33" ]]; then
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
