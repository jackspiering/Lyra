#!/usr/bin/env bash
# Structural smoke checks that run anywhere (Linux CI included).
# Full build/test requires macOS + Xcode (see Scripts/xcode-test.sh).
#
# Intentionally does NOT re-list every Swift source — the macOS build job is the
# real compiler. This script checks invariants the compiler cannot: docs, fonts,
# entitlements source, deployment target, bundle id, and (when present) that a
# built app is ad-hoc signed with the sandbox entitlement.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

check_exists() {
  if [[ -e "$1" ]]; then
    echo "  ok: $1"
  else
    echo "  FAIL: missing $1"
    fail=1
  fi
}

echo "== Lyra smoke =="

echo "-- required non-code paths"
for path in \
  README.md AGENTS.md CONTRIBUTING.md LICENSE \
  docs/architecture.md docs/ci.md \
  Lyra.xcodeproj/project.pbxproj \
  Lyra.xcodeproj/xcshareddata/xcschemes/Lyra.xcscheme \
  Lyra/Lyra.entitlements \
  Lyra/Info.plist \
  Lyra/Resources/Fonts/Inter-Regular.ttf \
  Lyra/Resources/Fonts/Inter-SemiBold.ttf \
  Lyra/Resources/Fonts/Inter-Bold.ttf \
  Lyra/Resources/Fonts/Inter-OFL.txt \
  Scripts/package-dmg.sh \
  Scripts/xcode-test.sh
do
  check_exists "$path"
done

echo "-- entitlements source"
if grep -q "com.apple.security.app-sandbox" Lyra/Lyra.entitlements \
  && grep -q "com.apple.security.files.user-selected.read-write" Lyra/Lyra.entitlements; then
  echo "  ok: sandbox + user-selected files in entitlements file"
else
  echo "  FAIL: entitlements incomplete"
  fail=1
fi

echo "-- deployment target"
if grep -q "MACOSX_DEPLOYMENT_TARGET = 15.0" Lyra.xcodeproj/project.pbxproj; then
  echo "  ok: macOS 15.0 deployment target"
else
  echo "  FAIL: expected MACOSX_DEPLOYMENT_TARGET = 15.0"
  fail=1
fi

echo "-- bundle id"
if grep -q "PRODUCT_BUNDLE_IDENTIFIER = app.lyra.Lyra" Lyra.xcodeproj/project.pbxproj; then
  echo "  ok: bundle id app.lyra.Lyra"
else
  echo "  FAIL: bundle id"
  fail=1
fi

echo "-- marketing version consistency"
versions="$(grep -o 'MARKETING_VERSION = [^;]*' Lyra.xcodeproj/project.pbxproj | awk '{print $3}' | sort -u)"
count="$(printf '%s\n' "$versions" | grep -c . || true)"
if [[ "$count" -eq 1 ]]; then
  echo "  ok: single MARKETING_VERSION ($versions)"
else
  echo "  FAIL: MARKETING_VERSION diverges across configs:"
  printf '%s\n' "$versions"
  fail=1
fi

# Optional: if a built app is sitting in the usual place, assert real sandbox entitlements.
APP_CANDIDATES=(
  "build/DerivedData/Build/Products/Release/Lyra.app"
  "build/DerivedData/Build/Products/Debug/Lyra.app"
)
if command -v codesign >/dev/null 2>&1; then
  for app in "${APP_CANDIDATES[@]}"; do
    if [[ -d "$app" ]]; then
      echo "-- built app entitlements ($app)"
      if codesign -d --entitlements - "$app" 2>/dev/null | grep -q "com.apple.security.app-sandbox"; then
        echo "  ok: sandbox present on signed app"
      else
        echo "  FAIL: built app missing sandbox entitlement (unsigned or wrong flags?)"
        fail=1
      fi
      break
    fi
  done
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== smoke FAILED =="
  exit 1
fi
echo "== smoke PASSED =="
