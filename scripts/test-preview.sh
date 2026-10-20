#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixtures_dir="$project_dir/Tests/Fixtures/Preview"
runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/mweb-lite-preview.XXXXXX")"
trap 'rm -rf "$runtime_dir"' EXIT
results_dir="$project_dir/build/test-results"
mkdir -p "$results_dir"
log_file="$results_dir/preview-$(date -u '+%Y%m%dT%H%M%SZ').log"
exec > >(tee "$log_file") 2>&1
printf 'Preview integration run: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
printf 'Fixtures: Tests/Fixtures/Preview (copied into a temporary directory)\n'
printf 'Log: %s\n' "$log_file"
test_app="$runtime_dir/PreviewTests.app"
resource_bundle="$test_app/Contents/Resources/MWebLite_MWebLite.bundle"
mkdir -p "$resource_bundle/Contents/Resources" "$test_app/Contents/MacOS"
cat > "$test_app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.mweblite.preview-tests</string>
<key>CFBundleExecutable</key><string>PreviewTests</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST
cp "$project_dir"/Sources/MWebLite/Resources/* "$resource_bundle/Contents/Resources/"
swiftc -module-cache-path "$runtime_dir/ModuleCache" \
  "$project_dir/Sources/MWebLite/Preview/MarkdownPreview.swift" \
  "$project_dir/Tests/PreviewIntegration/main.swift" \
  -o "$test_app/Contents/MacOS/PreviewTests"
# There is deliberately no SwiftPM fallback bundle: the installed-app lookup must work.
MWEB_PREVIEW_FIXTURES="$fixtures_dir" MWEB_PREVIEW_RUNTIME_ROOT="$runtime_dir" \
  "$test_app/Contents/MacOS/PreviewTests"
