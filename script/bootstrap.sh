#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

"$ROOT_DIR/script/install_mihomo_core.sh"
"$ROOT_DIR/script/install_runtime_assets.sh"

echo "Nexora runtime is ready."
