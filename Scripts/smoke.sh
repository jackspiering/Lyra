#!/usr/bin/env bash
# Structural smoke checks that run anywhere (Linux CI included).
# Full build/test requires macOS + Xcode (see Scripts/xcode-test.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
fail=0

check() {
  if "$@"; then
    echo "  ok: $*"
  else
    echo "  FAIL: $*"
    fail=1
  fi
}

echo "== Lyra smoke =="

echo "-- required paths"
for path in \
  README.md AGENTS.md CONTRIBUTING.md LICENSE \
  docs/architecture.md \
  Lyra.xcodeproj/project.pbxproj \
  Lyra.xcodeproj/xcshareddata/xcschemes/Lyra.xcscheme \
  Lyra/LyraApp.swift \
  Lyra/App/ContentView.swift \
  Lyra/App/VaultFolderPicker.swift \
  Lyra/Vault/FileSystemVault.swift \
  Lyra/Vault/VaultStore.swift \
  Lyra/Vault/WikiLinkResolver.swift \
  Lyra/Vault/UntitledName.swift \
  Lyra/Vault/AttachmentStore.swift \
  Lyra/Editor/EditorViewModel.swift \
  Lyra/Editor/MarkdownTextView.swift \
  Lyra/Editor/MarkdownHighlighter.swift \
  Lyra/Preview/MarkdownPreviewView.swift \
  Lyra/Preview/MarkdownPreviewBlocks.swift \
  Lyra/Preview/MarkdownImagePath.swift \
  Lyra/Preview/NotePDFExporter.swift \
  Lyra/Preview/MarkdownBlockRow.swift \
  Lyra/App/LyraTheme.swift \
  Lyra/App/NoteViewMode.swift \
  Lyra/App/UserFacingError.swift \
  Lyra/App/LyraFonts.swift \
  Lyra/Resources/Fonts/Inter-Regular.ttf \
  Lyra/Resources/Fonts/Inter-SemiBold.ttf \
  Lyra/Resources/Fonts/Inter-Bold.ttf \
  Lyra/Resources/Fonts/Inter-OFL.txt \
  LyraTests/UserFacingErrorTests.swift \
  Lyra/Models/VaultNode.swift \
  LyraTests/MarkdownPreviewBlocksTests.swift \
  Lyra/Lyra.entitlements \
  Lyra/Info.plist \
  LyraTests/WikiLinkResolverTests.swift \
  LyraTests/UntitledNameTests.swift \
  LyraTests/FileSystemVaultTests.swift \
  LyraTests/AttachmentStoreTests.swift \
  LyraTests/MarkdownImagePathTests.swift \
  LyraTests/NotePDFExporterTests.swift \
  LyraTests/EditorViewModelTests.swift \
  LyraTests/MarkdownHighlighterTests.swift \
  LyraTests/VaultStoreRenameTests.swift
do
  if [[ -e "$path" ]]; then
    echo "  ok: $path"
  else
    echo "  FAIL: missing $path"
    fail=1
  fi
done

echo "-- removed / unwanted paths"
for path in Lyra/App/OpenVaultView.swift Lyra/Models/NoteDocument.swift Lyra/Editor/EditorView.swift Lyra/Preview/LivePreviewView.swift; do
  if [[ -e "$path" ]]; then
    echo "  FAIL: should not exist: $path"
    fail=1
  else
    echo "  ok: absent $path"
  fi
done

echo "-- pbxproj references"
for name in LyraApp ContentView VaultStore WikiLinkResolver MarkdownTextView VaultFolderPicker LyraTheme MarkdownPreviewBlocks MarkdownImagePath AttachmentStore AttachmentStoreTests MarkdownImagePathTests NotePDFExporter NotePDFExporterTests NoteViewMode MarkdownBlockRow UserFacingError LyraFonts UserFacingErrorTests EditorViewModelTests MarkdownHighlighterTests VaultStoreRenameTests; do
  if grep -q "$name.swift" Lyra.xcodeproj/project.pbxproj; then
    echo "  ok: pbxproj lists $name.swift"
  else
    echo "  FAIL: pbxproj missing $name.swift"
    fail=1
  fi
done
for name in OpenVaultView NoteDocument EditorView LivePreviewView; do
  if grep -q "$name.swift" Lyra.xcodeproj/project.pbxproj; then
    echo "  FAIL: pbxproj still lists $name.swift"
    fail=1
  else
    echo "  ok: pbxproj omits $name.swift"
  fi
done

echo "-- entitlements"
if grep -q "com.apple.security.app-sandbox" Lyra/Lyra.entitlements \
  && grep -q "com.apple.security.files.user-selected.read-write" Lyra/Lyra.entitlements; then
  echo "  ok: sandbox + user-selected files"
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

if [[ "$fail" -ne 0 ]]; then
  echo "== smoke FAILED =="
  exit 1
fi
echo "== smoke PASSED =="
