#!/usr/bin/env bash
# Build Lyra.app (Release) and wrap it in a DMG. Requires macOS + Xcode.
set -euo pipefail

ROOT="$(cd -P "$(dirname "$0")/.." && pwd -P)"
cd "$ROOT"

# Resolve a path lexically, reject traversal, and refuse existing symlink
# components. This keeps cleanup from reaching outside ROOT through a symlink.
safe_path() {
  local label="$1"
  local raw="$2"
  local abs="$raw"
  local rest segment normalized relative current

  if [[ -z "$raw" ]]; then
    echo "error: $label is empty" >&2
    return 1
  fi
  case "$raw" in
    *$'\n'*|*$'\r'*)
      echo "error: $label contains a newline" >&2
      return 1
      ;;
  esac

  if [[ "$abs" != /* ]]; then
    abs="$ROOT/$abs"
  fi

  normalized="/"
  rest="${abs#/}"
  while [[ -n "$rest" ]]; do
    if [[ "$rest" == */* ]]; then
      segment="${rest%%/*}"
      rest="${rest#*/}"
    else
      segment="$rest"
      rest=""
    fi

    case "$segment" in
      ""|.)
        ;;
      ..)
        echo "error: $label must not contain '..': $raw" >&2
        return 1
        ;;
      *)
        if [[ "$normalized" == "/" ]]; then
          normalized="/$segment"
        else
          normalized="$normalized/$segment"
        fi
        ;;
    esac
  done

  if [[ "$normalized" == "$ROOT" ]]; then
    echo "error: $label must not be ROOT: $raw" >&2
    return 1
  fi
  case "$normalized" in
    "$ROOT"/*)
      ;;
    *)
      echo "error: $label must be under $ROOT: $raw" >&2
      return 1
      ;;
  esac

  relative="${normalized#"$ROOT"/}"
  current="$ROOT"
  while [[ -n "$relative" ]]; do
    if [[ "$relative" == */* ]]; then
      segment="${relative%%/*}"
      relative="${relative#*/}"
    else
      segment="$relative"
      relative=""
    fi
    current="$current/$segment"
    if [[ -L "$current" ]]; then
      echo "error: $label has a symlinked ancestor: $current" >&2
      return 1
    fi
  done

  printf '%s\n' "$normalized"
}

validate_version() {
  local version="$1"
  if ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "error: VERSION must be three-part semver (e.g. 0.9.2), got '$version'" >&2
    return 1
  fi
}

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
validate_version "$VERSION"

SCHEME="${SCHEME:-Lyra}"
CONFIGURATION="${CONFIGURATION:-Release}"
if [[ -z "$SCHEME" || -z "$CONFIGURATION" ]]; then
  echo "error: SCHEME and CONFIGURATION must not be empty" >&2
  exit 1
fi
case "$CONFIGURATION" in
  */*|.|..|*$'\n'*|*$'\r'*)
    echo "error: CONFIGURATION must be a single path component: $CONFIGURATION" >&2
    exit 1
    ;;
esac
case "$SCHEME" in
  *$'\n'*|*$'\r'*)
    echo "error: SCHEME contains a newline" >&2
    exit 1
    ;;
esac

DERIVED_DATA="${DERIVED_DATA:-$ROOT/build/DerivedData}"
STAGE="${STAGE:-$ROOT/build/dmg-stage}"
OUT_DIR="${OUT_DIR:-$ROOT/build/dist}"
DMG_NAME="${DMG_NAME:-Lyra-${VERSION}.dmg}"

case "$DMG_NAME" in
  ""|.|..|*/*|*$'\n'*|*$'\r'*)
    echo "error: DMG_NAME must be a single filename: $DMG_NAME" >&2
    exit 1
    ;;
esac
if [[ "$DMG_NAME" != *.dmg ]]; then
  echo "error: DMG_NAME must end in .dmg: $DMG_NAME" >&2
  exit 1
fi

DERIVED_DATA="$(safe_path DERIVED_DATA "$DERIVED_DATA")"
STAGE="$(safe_path STAGE "$STAGE")"
OUT_DIR="$(safe_path OUT_DIR "$OUT_DIR")"
DMG_PATH="$(safe_path DMG_PATH "$OUT_DIR/$DMG_NAME")"

for required_command in xcodebuild codesign hdiutil; do
  if ! command -v "$required_command" >/dev/null 2>&1; then
    echo "$required_command not found (need macOS + Xcode)." >&2
    exit 2
  fi
done
if [[ ! -x /usr/libexec/PlistBuddy ]]; then
  echo "/usr/libexec/PlistBuddy not found (need macOS)." >&2
  exit 2
fi

echo "Packaging Lyra ${VERSION} → ${DMG_PATH}"

# Recheck immediately before destructive cleanup. Existing ancestors must still
# be real directories, not symlinks, and none of the targets may be ROOT.
DERIVED_DATA="$(safe_path DERIVED_DATA "$DERIVED_DATA")"
STAGE="$(safe_path STAGE "$STAGE")"
OUT_DIR="$(safe_path OUT_DIR "$OUT_DIR")"

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
  CODE_SIGNING_ALLOWED=YES \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

APP="${DERIVED_DATA}/Build/Products/${CONFIGURATION}/Lyra.app"
APP="$(safe_path APP "$APP")"
if [[ ! -d "$APP" ]]; then
  echo "Built app not found at $APP"
  find "$DERIVED_DATA/Build/Products" -name 'Lyra.app' -type d 2>/dev/null || true
  exit 1
fi
if [[ -L "$APP" || ! -f "$APP/Contents/Info.plist" ]]; then
  echo "error: built app bundle is invalid: $APP" >&2
  exit 1
fi

echo "Verifying code signature and sandbox entitlements"
if ! codesign --verify --deep --strict --verbose=2 "$APP"; then
  echo "error: built app is not validly signed: $APP" >&2
  exit 1
fi

ENTITLEMENTS_FILE="$(mktemp -t lyra-entitlements)"
remove_entitlements_file() {
  if [[ -n "${ENTITLEMENTS_FILE:-}" ]]; then
    rm -f "$ENTITLEMENTS_FILE"
  fi
}
trap remove_entitlements_file EXIT
if ! codesign -d --entitlements :- "$APP" >"$ENTITLEMENTS_FILE" 2>/dev/null; then
  echo "error: could not read embedded entitlements from $APP" >&2
  exit 1
fi

check_entitlement() {
  local key="$1"
  local value
  value="$(/usr/libexec/PlistBuddy -c "Print :$key" "$ENTITLEMENTS_FILE" 2>/dev/null || true)"
  if [[ "$value" != "true" ]]; then
    echo "error: expected embedded entitlement '$key = true'" >&2
    return 1
  fi
}

check_entitlement com.apple.security.app-sandbox
check_entitlement com.apple.security.files.user-selected.read-write
check_entitlement com.apple.security.files.bookmarks.app-scope

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

# Keep staging and the final output protected if a directory changed during the
# build. This also rejects a symlink at the final DMG path before hdiutil runs.
STAGE="$(safe_path STAGE "$STAGE")"
OUT_DIR="$(safe_path OUT_DIR "$OUT_DIR")"
DMG_PATH="$(safe_path DMG_PATH "$DMG_PATH")"

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
if [[ ! -s "$DMG_PATH" || -L "$DMG_PATH" ]]; then
  echo "error: hdiutil did not create a regular DMG at $DMG_PATH" >&2
  exit 1
fi
ls -lh "$DMG_PATH"
echo "DMG_PATH=$DMG_PATH"
echo "VERSION=$VERSION"
