#!/usr/bin/env bash
# Build + unit tests. Requires macOS with Xcode.
#
# Optional environment:
#   RESULT_BUNDLE  write an .xcresult bundle to this path (replaced if present)
#   DESTINATION    xcodebuild destination (default platform=macOS)
#   SCHEME         scheme to test (default Lyra)
#   LYRA_RAW_LOG   set to print raw xcodebuild output instead of xcbeautify
#
# When xcbeautify is installed (it is on GitHub's macOS runners) the log is
# condensed; on GitHub Actions compiler errors and failing tests also become
# annotations on the pull request.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found (need macOS + Xcode). Run Scripts/smoke.sh for structure checks."
  exit 2
fi

DESTINATION="${DESTINATION:-platform=macOS}"
SCHEME="${SCHEME:-Lyra}"

args=(-scheme "$SCHEME" -destination "$DESTINATION" -configuration Debug)
if [[ -n "${RESULT_BUNDLE:-}" ]]; then
  if [[ "$RESULT_BUNDLE" != *.xcresult ]]; then
    echo "error: RESULT_BUNDLE must end in .xcresult: $RESULT_BUNDLE" >&2
    exit 1
  fi
  # xcodebuild refuses to overwrite an existing bundle.
  rm -rf "$RESULT_BUNDLE"
  args+=(-resultBundlePath "$RESULT_BUNDLE")
fi
# Ad-hoc sign so sandbox entitlements apply; do not inject get-task-allow into the app.
args+=(
  CODE_SIGN_IDENTITY="-"
  CODE_SIGNING_REQUIRED=NO
  CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
  build test
)

if [[ -z "${LYRA_RAW_LOG:-}" ]] && command -v xcbeautify >/dev/null 2>&1; then
  renderer=terminal
  if [[ "${GITHUB_ACTIONS:-}" == "true" ]]; then
    renderer=github-actions
  fi
  echo "+ xcodebuild ${args[*]} | xcbeautify --renderer $renderer"
  xcodebuild "${args[@]}" 2>&1 | xcbeautify --renderer "$renderer"
else
  set -x
  xcodebuild "${args[@]}"
fi
