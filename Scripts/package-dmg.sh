#!/usr/bin/env bash
# Build Lyra.app (Release) and wrap it in a DMG. Requires macOS + Xcode.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found (need macOS + Xcode)."
  exit 2
fi

VERSION="${VERSION:-}"
if [[ -z "$VERSION" ]]; then
  # Prefer MARKETING_VERSION from the Xcode project, fall back to git tag / 0.0.0
  VERSION="$(grep -m1 'MARKETING_VERSION' Lyra.xcodeproj/project.pbxproj | sed -E 's/.*MARKETING_VERSION = ([^;]+);/\1/' | tr -d '[:space:]')"
  VERSION="${VERSION:-0.0.0}"
fi
# Strip leading v from tags if present
VERSION="${VERSION#v}"

SCHEME="${SCHEME:-Lyra}"
CONFIGURATION="${CONFIGURATION:-Release}"
DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"
STAGE="${STAGE:-$ROOT/build/dmg-stage}"
OUT_DIR="${OUT_DIR:-$ROOT/build/dist}"
DMG_NAME="${DMG_NAME:-Lyra-${VERSION}.dmg}"
DMG_PATH="${OUT_DIR}/${DMG_NAME}"

echo "Packaging Lyra ${VERSION} → ${DMG_PATH}"

# Refuse to rm -rf paths that are empty or outside the repo (caller-overridable env vars).
assert_under_root() {
  local label="$1"
  local path="$2"
  if [[ -z "$path" ]]; then
    echo "error: $label is empty" >&2
    exit 1
  fi
  local resolved
  resolved="$(cd "$(dirname "$path")" 2>/dev/null && pwd)/$(basename "$path")" || resolved="$path"
  case "$resolved" in
    "$ROOT"|"$ROOT"/*) ;;
    *)
      echo "error: $label must be under $ROOT (got: $path)" >&2
      exit 1
      ;;
  esac
}

assert_under_root DERIVED_DATA "$DERIVED_DATA"
assert_under_root STAGE "$STAGE"
assert_under_root OUT_DIR "$OUT_DIR"

rm -rf "$DERIVED_DATA" "$STAGE" "$OUT_DIR"
mkdir -p "$STAGE" "$OUT_DIR"

set -x
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Lyra.app"
if [[ ! -d "$APP" ]]; then
  echo "Built app not found at $APP"
  find "$DERIVED_DATA/Build/Products" -name 'Lyra.app' -type d 2>/dev/null || true
  exit 1
fi

cp -R "$APP" "$STAGE/"
ln -sf /Applications "$STAGE/Applications"

# UDZO = compressed read-only image
hdiutil create \
  -volname "Lyra ${VERSION}" \
  -srcfolder "$STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

set +x
ls -lh "$DMG_PATH"
echo "DMG_PATH=$DMG_PATH"
echo "VERSION=$VERSION"
