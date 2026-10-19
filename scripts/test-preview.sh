#!/bin/bash
set -euo pipefail

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
fixture_dir="$(mktemp -d "${TMPDIR:-/tmp}/mweb-lite-preview.XXXXXX")"
trap 'rm -rf "$fixture_dir"' EXIT
resource_bundle="$fixture_dir/PreviewTests.bundle"
mkdir -p "$resource_bundle/Contents/Resources"
cp "$project_dir"/Sources/MWebLite/Resources/* "$resource_bundle/Contents/Resources/"
swiftc -module-cache-path "$fixture_dir/ModuleCache" \
  "$project_dir/Sources/MWebLite/Preview/MarkdownPreview.swift" \
  "$project_dir/Tests/PreviewIntegration/main.swift" \
  -o "$fixture_dir/preview-tests"
MWEB_PREVIEW_RESOURCE_BUNDLE="$resource_bundle" MWEB_PREVIEW_FIXTURE="$fixture_dir" \
  "$fixture_dir/preview-tests"
