#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

usage() {
    echo 'Usage: scripts/run-preview-app.sh <run-name> [--prepare-only]'
    echo '       scripts/run-preview-app.sh --reopen <run-name>'
}
if [[ "${1:-}" == "--help" ]]; then usage; exit 0; fi
reopen=false
prepare_only=false
if [[ "${1:-}" == "--reopen" && $# == 2 ]]; then
    reopen=true
    run_name="$2"
elif [[ $# == 1 || ( $# == 2 && "${2:-}" == "--prepare-only" ) ]]; then
    run_name="$1"
    [[ $# == 1 ]] || prepare_only=true
else
    usage >&2; exit 1
fi
if [[ ! "$run_name" =~ ^[a-zA-Z0-9][a-zA-Z0-9_-]{0,63}$ ]]; then
    echo 'Use 1–64 letters, digits, hyphens, or underscores for the run name.' >&2; exit 1
fi
run="$PWD/build/Test Runs/$run_name"
app="$run/MWeb Lite Preview.app"
library="$run/Library"
if $reopen; then
    [[ -f "$run/run.json" && -f "$app/Contents/Info.plist" && -f "$library/mainlib.db" ]] || {
        echo 'This run is incomplete or does not exist; create a new run first.' >&2; exit 1;
    }
else
    [[ ! -e "$run" && ! -L "$run" ]] || { echo 'Run already exists. Choose a new name or use --reopen after quitting.' >&2; exit 1; }
    ./scripts/build-app.sh release
    python3 scripts/prepare-test-library.py "$library"
    ditto "$PWD/build/MWeb Lite.app" "$app"
    run_token="$(printf '%s' "$run_name" | shasum -a 256 | cut -c 1-12)"
    /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.highestop.mweb-lite.preview.$run_token" "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleName MWeb Lite Preview' "$app/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName MWeb Lite Preview' "$app/Contents/Info.plist"
    codesign --force --deep --sign - "$app"
    python3 - "$run" <<'PY'
import datetime, hashlib, json, pathlib, platform, subprocess, sys
root = pathlib.Path.cwd()
run = pathlib.Path(sys.argv[1])
files = sorted(p for folder in ("Sources", "Tests", "Support", "scripts")
               for p in (root / folder).rglob("*") if p.is_file() and "__pycache__" not in p.parts)
files.append(root / "Package.swift")
hashes = {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(files)}
tree_hash = hashlib.sha256(json.dumps(hashes, sort_keys=True).encode()).hexdigest()
baseline = json.loads((run / "Library/.fixture-baseline.json").read_text())
def tool_version(command):
    result = subprocess.run(command, capture_output=True, text=True)
    return (result.stdout or result.stderr).strip()
(run / "run.json").write_text(json.dumps({
    "createdAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "baseCommit": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "workingTreeDirty": bool(subprocess.check_output(["git", "status", "--porcelain"], text=True).strip()),
    "sourceFingerprint": tree_hash, "sourceFiles": hashes,
    "macOS": platform.mac_ver()[0], "swift": tool_version(["swift", "--version"]),
    "xcode": tool_version(["xcodebuild", "-version"]),
    "fixture": "Tests/Fixtures/Library", "fixtureVersion": baseline["fixtureVersion"],
    "note": "Preparation is not a test pass. Record executed GWT cases and observations separately."
}, indent=2) + "\n")
PY
fi
printf 'App: %s\nLibrary: %s\nRun record: %s\n' "$app" "$library" "$run/run.json"
if ! $prepare_only; then
    open "$app" --args --library "$library"
fi
