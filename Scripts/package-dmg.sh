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
  # All MARKETING_VERSION values must agree; take the unique value.
  VERSION_LINES="$(grep -o 'MARKETING_VERSION = [^;]*' Lyra.xcodeproj/project.pbxproj | awk '{print $3}' | sort -u)"
  COUNT="$(printf '%s\n' "$VERSION_LINES" | grep -c . || true)"
  if [[ "$COUNT" -ne 1 ]]; then
    echo "error: MARKETING_VERSION must be unique across configs, got:" >&2
    printf '%s\n' "$VERSION_LINES" >&2
    exit 1
  fi
  VERSION="$VERSION_LINES"
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
# Do not require the path (or its parent) to exist yet — CI starts with no build/ tree.
# Collapse "." / ".." so a crafted DERIVED_DATA cannot escape ROOT before rm -rf.
assert_under_root() {
  local label="$1"
  local path="$2"
  if [[ -z "$path" ]]; then
    echo "error: $label is empty" >&2
    exit 1
  fi
  local abs="$path"
  if [[ "$abs" != /* ]]; then
    abs="$ROOT/$abs"
  fi
  local cleaned="" segment
  local rest="${abs#/}"
  while [[ -n "$rest" ]]; do
    segment="${rest%%/*}"
    if [[ "$segment" == "$rest" ]]; then
      rest=""
    else
      rest="${rest#*/}"
    fi
    case "$segment" in
      ""|".") ;;
      "..")
        cleaned="${cleaned%/*}"
        ;;
      *)
        cleaned="${cleaned}/${segment}"
        ;;
    esac
  done
  abs="$cleaned"
  [[ -n "$abs" ]] || abs="/"
  case "$abs" in
    "$ROOT"|"$ROOT"/*) ;;
    *)
      echo "error: $label must be under $ROOT (got: $path → $abs)" >&2
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
# Ad-hoc sign with entitlements so the App Sandbox is actually applied.
# CODE_SIGNING_ALLOWED must stay YES (default). Injected get-task-allow is disabled.
xcodebuild \
  -scheme "$SCHEME" \
  -configuration "$CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA" \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Lyra.app"
if [[ ! -d "$APP" ]]; then
  echo "Built app not found at $APP"
  find "$DERIVED_DATA/Build/Products" -name 'Lyra.app' -type d 2>/dev/null || true
  exit 1
fi

# Fail if the finished app's version does not match the requested VERSION.
APP_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || true)"
if [[ -z "$APP_VERSION" ]]; then
  echo "error: could not read CFBundleShortVersionString from $APP" >&2
  exit 1
fi
if [[ "$APP_VERSION" != "$VERSION" ]]; then
  echo "error: app version $APP_VERSION does not match package version $VERSION" >&2
  echo "       Bump MARKETING_VERSION in the Xcode project to match the tag." >&2
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
