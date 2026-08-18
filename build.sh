#!/usr/bin/env bash
# Convenience wrapper for scripts/build-container.sh.
# Usage: ./build.sh pi|dsh|webui
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scripts/build-container.sh" "$@"
