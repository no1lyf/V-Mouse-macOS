#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -d "$1" || "$1" != *.app ]]; then
  echo "Usage: $0 '/absolute/path/to/V-Mouse鼠标映射-vVERSION.app'" >&2
  exit 2
fi

SOURCE_APP="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
DESTINATION="/Applications/$(basename "$SOURCE_APP")"
BUNDLE_ID="${VMOUSE_BUNDLE_ID:-com.vmouse.mousemapper}"

if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$SOURCE_APP/Contents/Info.plist")" != "$BUNDLE_ID" ]]; then
  echo "Refusing to install a bundle with an unexpected identifier." >&2
  exit 3
fi
codesign --verify --deep --strict "$SOURCE_APP"

# A test generation must never run alongside an older generation: two Event
# Taps would make scroll direction and button interception results meaningless.
pkill -TERM -x NagaController 2>/dev/null || true
for _ in {1..10}; do
  pgrep -x NagaController >/dev/null 2>&1 || break
  sleep 0.2
done
if pgrep -x NagaController >/dev/null 2>&1; then
  pkill -KILL -x NagaController 2>/dev/null || true
fi

for applications_dir in /Applications "$HOME/Applications"; do
  [[ -d "$applications_dir" ]] || continue
  while IFS= read -r -d '' old_app; do
    old_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$old_app/Contents/Info.plist" 2>/dev/null || true)"
    if [[ "$old_id" == "$BUNDLE_ID" ]]; then
      rm -rf "$old_app"
    fi
  done < <(find "$applications_dir" -maxdepth 1 -type d -name '*.app' -print0)
done

ditto "$SOURCE_APP" "$DESTINATION"
xattr -dr com.apple.quarantine "$DESTINATION" 2>/dev/null || true
codesign --verify --deep --strict "$DESTINATION"
open "$DESTINATION"

echo "Installed test build: $DESTINATION"
