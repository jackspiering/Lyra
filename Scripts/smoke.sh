#!/usr/bin/env bash
# Checks that run anywhere (Linux CI included). The macOS job is the compiler;
# this catches what it cannot: whitespace, shell errors, and project invariants.
set -euo pipefail
cd "$(dirname "$0")/.."
fail=0

pass() { echo "  ok: $1"; }
flunk() { echo "  FAIL: $1"; fail=1; }

echo "-- whitespace"
while IFS= read -r file; do
  if grep -qE '[[:blank:]]+$' "$file"; then
    flunk "trailing whitespace in $file"
  fi
  if [[ -s "$file" && -n "$(tail -c 1 "$file")" ]]; then
    flunk "$file does not end with a newline"
  fi
done < <(git ls-files '*.swift' '*.sh' '*.yml' '*.md' '*.plist' '*.entitlements' '*.svg' 'Lyra.xcodeproj/project.pbxproj')

echo "-- shell"
for script in Scripts/*.sh; do
  bash -n "$script" || flunk "shell syntax in $script"
done
if command -v shellcheck >/dev/null 2>&1; then
  if shellcheck Scripts/*.sh; then pass "shellcheck"; else flunk "shellcheck"; fi
else
  echo "  skip: shellcheck not installed"
fi

echo "-- project"
project=Lyra.xcodeproj/project.pbxproj
versions="$(grep -o 'MARKETING_VERSION = [^;]*' "$project" | awk '{print $3}' | sort -u)"
if [[ "$(grep -c . <<<"$versions")" -eq 1 ]]; then
  pass "MARKETING_VERSION $versions"
else
  flunk "MARKETING_VERSION differs across configurations: $(tr '\n' ' ' <<<"$versions")"
fi
if grep -q 'MACOSX_DEPLOYMENT_TARGET = 15.0' "$project" \
  && ! grep 'MACOSX_DEPLOYMENT_TARGET' "$project" | grep -vq '15.0'; then
  pass "deployment target macOS 15.0"
else
  flunk "deployment target must be macOS 15.0 in every configuration"
fi
for key in app-sandbox files.user-selected.read-write files.bookmarks.app-scope; do
  grep -q "com.apple.security.$key" Lyra/Lyra.entitlements || flunk "entitlement com.apple.security.$key missing"
done

if [[ "$fail" -ne 0 ]]; then
  echo "== smoke FAILED =="
  exit 1
fi
echo "== smoke PASSED =="
