#!/usr/bin/env bash
# Build + unit tests. Requires macOS with Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found (need macOS + Xcode). Run Scripts/smoke.sh for structure checks."
  exit 2
fi

DESTINATION="${DESTINATION:-platform=macOS}"
SCHEME="${SCHEME:-Lyra}"

set -x
xcodebuild \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -configuration Debug \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build test
