#!/usr/bin/env bash
# Convenience wrapper for scripts/start-container.sh.
# Usage: ./start.sh [pi|webui|dsh] [command arguments...]
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "$SCRIPT_DIR/scripts/start-container.sh" "$@"
