#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOL="$(basename "$HERE")"
exec "$HERE/../scripts/install-tool.sh" "$TOOL" "$@"
