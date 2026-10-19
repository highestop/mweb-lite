#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
configuration="${1:-release}"
export CLANG_MODULE_CACHE_PATH="${CLANG_MODULE_CACHE_PATH:-$PWD/.build/clang-cache}"
swift build -c "$configuration" --disable-sandbox
bin_dir="$(swift build -c "$configuration" --show-bin-path --disable-sandbox)"
app="$PWD/build/MWeb Lite.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp "$bin_dir/MWebLite" "$app/Contents/MacOS/MWebLite"
for bundle in "$bin_dir"/*.bundle; do
    [ -d "$bundle" ] && cp -R "$bundle" "$app/Contents/Resources/"
done
cp Support/Info.plist "$app/Contents/Info.plist"
codesign --force --deep --sign - "$app"
echo "$app"
