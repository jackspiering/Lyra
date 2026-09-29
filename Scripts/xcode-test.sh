#!/usr/bin/env bash
# Build and run the unit tests. Requires macOS + Xcode.
#   RESULT_BUNDLE               also write an .xcresult bundle here
#   TEST_RUNNER_LYRA_SNAPSHOTS  set to 1 to render window PNGs (WindowSnapshotTests)
#   LYRA_RAW_LOG                set to print raw xcodebuild output instead of xcbeautify
set -euo pipefail
cd "$(dirname "$0")/.."

if ! command -v xcodebuild >/dev/null 2>&1; then
  echo "xcodebuild not found (need macOS + Xcode). Scripts/smoke.sh runs anywhere." >&2
  exit 2
fi

args=(-scheme Lyra -destination platform=macOS -configuration Debug)
if [[ -n "${RESULT_BUNDLE:-}" ]]; then
  rm -rf "$RESULT_BUNDLE" # xcodebuild refuses to overwrite a bundle
  args+=(-resultBundlePath "$RESULT_BUNDLE")
fi
# Ad-hoc sign so the sandbox entitlements apply; no get-task-allow.
args+=(CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO build test)

if [[ -z "${LYRA_RAW_LOG:-}" ]] && command -v xcbeautify >/dev/null 2>&1; then
  # On GitHub Actions, compiler errors and failing tests become PR annotations.
  renderer=terminal
  [[ "${GITHUB_ACTIONS:-}" == true ]] && renderer=github-actions
  xcodebuild "${args[@]}" 2>&1 | xcbeautify --renderer "$renderer"
else
  xcodebuild "${args[@]}"
fi
