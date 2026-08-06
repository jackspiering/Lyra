#!/usr/bin/env bash
# Lightweight whitespace checks that run anywhere (Linux CI included).
# The macOS compile job catches type errors; this catches drift it cannot:
# trailing whitespace and missing final newlines in tracked source files.
#
# No formatter dependency — deliberately objective so it never bikesheds style.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

FILES="$(git ls-files \
  '*.swift' '*.sh' '*.yml' '*.yaml' '*.md' \
  'Lyra.xcodeproj/project.pbxproj')"

echo "== Lyra lint =="

while IFS= read -r file; do
  if [[ -z "$file" ]]; then
    continue
  fi

  if grep -nE ' +$' "$file" >/tmp/lyra-lint-trailing.txt; then
    echo "  FAIL: trailing whitespace in $file:"
    sed 's/^/      /' /tmp/lyra-lint-trailing.txt | head -5
    fail=1
  fi

  if [[ -s "$file" ]] && [[ -z "$(tail -c 1 "$file" | tr -d '\n')" ]]; then
    :
  elif [[ -s "$file" ]]; then
    echo "  FAIL: $file does not end with a newline"
    fail=1
  fi
done <<< "$FILES"

if [[ "$fail" -ne 0 ]]; then
  echo "== lint FAILED =="
  exit 1
fi
echo "== lint PASSED =="
