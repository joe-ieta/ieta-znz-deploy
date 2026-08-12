#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
echo "Remote image pull is disabled. Loading local offline archives instead."
exec bash "$SCRIPT_DIR/load-images.sh"
