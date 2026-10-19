#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/mweb-lite-preview.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
test_app="$fixture_dir/PreviewTests.app"
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
swiftc -module-cache-path "$fixture_dir/ModuleCache" \
  "$project_dir/Sources/MWebLite/Preview/MarkdownPreview.swift" \
  "$project_dir/Tests/PreviewIntegration/main.swift" \
  -o "$test_app/Contents/MacOS/PreviewTests"
# There is deliberately no SwiftPM fallback bundle: the installed-app lookup must work.
MWEB_PREVIEW_FIXTURE="$fixture_dir" "$test_app/Contents/MacOS/PreviewTests"
