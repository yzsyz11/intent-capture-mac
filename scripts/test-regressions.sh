#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

CAPTURE_SERVICE="$ROOT/Sources/CaptureService.swift"
REGION_WINDOW="$ROOT/Sources/RegionSelectionWindow.swift"

require_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"

  if ! grep -Eq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

reject_pattern() {
  local pattern="$1"
  local file="$2"
  local message="$3"

  if grep -Eq "$pattern" "$file"; then
    echo "FAIL: $message" >&2
    exit 1
  fi
}

require_pattern "guard activeSelectionWindow == nil else \\{ return \\}" "$CAPTURE_SERVICE" \
  "capture actions must ignore duplicate triggers while a selection window is active"

require_pattern "RegionSelectionWindow\\(screen:" "$CAPTURE_SERVICE" \
  "region selection must create screen-scoped overlay windows so fullscreen Spaces receive mouse events"

require_pattern "collectionBehavior = \\[[^]]*fullScreenAuxiliary" "$REGION_WINDOW" \
  "region selection windows must remain fullscreen auxiliary windows"

reject_pattern "NSScreen\\.screens\\.reduce\\(CGRect\\.null\\)" "$REGION_WINDOW" \
  "region selection window must not use one union-frame window across all screens"

echo "regression checks passed."
