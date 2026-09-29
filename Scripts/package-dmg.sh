#!/usr/bin/env bash
# Build Lyra.app (Release), check its signature and sandbox, and wrap it in a DMG.
# Requires macOS + Xcode. Output: build/dist/Lyra-<version>.dmg and SHA256SUMS.txt.
#   VERSION  expected version (default: MARKETING_VERSION from the project)
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found (need macOS + Xcode)." >&2
  exit 2
fi

project_version="$(grep -o 'MARKETING_VERSION = [^;]*' Lyra.xcodeproj/project.pbxproj | awk '{print $3}' | sort -u)"
VERSION="${VERSION:-$project_version}"
VERSION="${VERSION#v}"
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "error: VERSION must be MAJOR.MINOR.PATCH, got '$VERSION'" >&2
  exit 1
fi

derived=build/DerivedData
stage=build/dmg-stage
dist=build/dist
dmg="$dist/Lyra-$VERSION.dmg"
rm -rf "$derived" "$stage" "$dist"
mkdir -p "$stage" "$dist"

# Ad-hoc sign so the App Sandbox entitlements are embedded; no get-task-allow.
xcodebuild -scheme Lyra -configuration Release -destination 'platform=macOS' \
  -derivedDataPath "$derived" \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO \
  build

app="$derived/Build/Products/Release/Lyra.app"
codesign --verify --deep --strict "$app"
entitlements="$(codesign -d --entitlements - --xml "$app" 2>/dev/null)"
for key in app-sandbox files.user-selected.read-write files.bookmarks.app-scope; do
  if ! grep -q "com.apple.security.$key" <<<"$entitlements"; then
    echo "error: built app lacks entitlement com.apple.security.$key" >&2
    exit 1
  fi
done
app_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")"
if [[ "$app_version" != "$VERSION" ]]; then
  echo "error: app version $app_version does not match $VERSION (bump MARKETING_VERSION)" >&2
  exit 1
fi

cp -R "$app" "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Lyra $VERSION" -srcfolder "$stage" -format UDZO -ov "$dmg"

(cd "$dist" && shasum -a 256 "Lyra-$VERSION.dmg" | tee SHA256SUMS.txt)
