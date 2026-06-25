#!/bin/bash
# test.sh — Run package tests with a full Xcode toolchain.
# Usage: ./scripts/test.sh [swift test args...]

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
XCODE_DEV_DIR="/Applications/Xcode.app/Contents/Developer"

if [ ! -d "$XCODE_DEV_DIR" ]; then
  echo "error: Xcode not found at $XCODE_DEV_DIR" >&2
  echo "Install Xcode or update scripts/test.sh to point at your Xcode.app." >&2
  exit 1
fi

cd "$PROJECT_DIR"
export DEVELOPER_DIR="$XCODE_DEV_DIR"

exec swift test "$@"
