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
swift -module-cache-path "$CLANG_MODULE_CACHE_PATH" scripts/build-icon.swift Support/AppIcon.svg "$PWD/build/AppIcon.iconset"
iconutil -c icns "$PWD/build/AppIcon.iconset" -o "$app/Contents/Resources/AppIcon.icns"
cp Support/AppIcon-LICENSE.txt "$app/Contents/Resources/AppIcon-LICENSE.txt"
# Keep Command Line Tools builds compatible; full Xcode 26+ adds the native layered icon.
rm -f "$app/Contents/Resources/Assets.car"
if xcode_version="$(xcodebuild -version 2>/dev/null)"; then
    xcode_major="$(printf '%s\n' "$xcode_version" | awk '/^Xcode / { split($2, parts, "."); print parts[1] }')"
    if [[ "$xcode_major" =~ ^[0-9]+$ ]] && (( xcode_major >= 26 )); then
        xcrun actool Support/AppIcon.icon --compile "$app/Contents/Resources" \
            --platform macosx --minimum-deployment-target 14.0 --app-icon AppIcon \
            --output-partial-info-plist "$PWD/build/AppIcon-Info.plist" \
            --output-format human-readable-text --notices --warnings
        /usr/libexec/PlistBuddy -c 'Add :CFBundleIconName string AppIcon' "$app/Contents/Info.plist"
    fi
fi
codesign --force --deep --sign - "$app"
echo "$app"
