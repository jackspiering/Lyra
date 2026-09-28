#!/usr/bin/env bash
# Lightweight whitespace checks that run anywhere (Linux CI included).
# The macOS compile job catches type errors; this catches drift it cannot:
# trailing whitespace, missing final newlines, and shell syntax in tracked files.
# ShellCheck also runs when it is installed (it is on GitHub's Ubuntu runners).
#
# No formatter dependency — deliberately objective so it never bikesheds style.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

FILES="$(git ls-files \
  '*.swift' '*.sh' '*.yml' '*.yaml' '*.md' \
  '*.plist' '*.entitlements' '*.xcscheme' '*.txt' \
  'Lyra.xcodeproj/project.pbxproj')"

echo "== Lyra lint =="

while IFS= read -r file; do
  if [[ -z "$file" ]]; then
    continue
  fi

  trailing="$(grep -nE '[[:blank:]]+$' "$file" || true)"
  if [[ -n "$trailing" ]]; then
    echo "  FAIL: trailing whitespace in $file:"
    printf '%s\n' "$trailing" | sed -n '1,5{s/^/      /;p;}'
    fail=1
  fi

  if [[ -s "$file" ]] && [[ -z "$(tail -c 1 "$file" | tr -d '\n')" ]]; then
    :
  elif [[ -s "$file" ]]; then
    echo "  FAIL: $file does not end with a newline"
    fail=1
  fi

  if [[ "$file" == *.sh ]] && ! bash -n "$file"; then
    echo "  FAIL: shell syntax in $file"
    fail=1
  fi
done <<< "$FILES"

if command -v shellcheck >/dev/null 2>&1; then
  if ! git ls-files -z '*.sh' | xargs -0 shellcheck; then
    echo "  FAIL: shellcheck"
    fail=1
  fi
else
  echo "  skip: shellcheck not installed"
fi

if [[ "$fail" -ne 0 ]]; then
  echo "== lint FAILED =="
  exit 1
fi
echo "== lint PASSED =="
