#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/.build"
SCRATCH_DIR="$(mktemp -d /tmp/naga-build-XXXXXX)"
PRODUCT_NAME="V-Mouse鼠标映射"
BUNDLE_ID="${VMOUSE_BUNDLE_ID:-com.vmouse.mousemapper}"
EXECUTABLE_NAME="NagaController"
EXECUTABLE_PATH="$SCRATCH_DIR/release/$EXECUTABLE_NAME"
MODULE_CACHE="$SCRATCH_DIR/module-cache"
if [[ -x "/Library/Developer/CommandLineTools/usr/bin/swift" ]]; then
  SWIFT_BIN="/Library/Developer/CommandLineTools/usr/bin/swift"
else
  SWIFT_BIN="swift"
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PROJECT_ROOT/Resources/Info.plist")"
APP_BUNDLE_NAME="${PRODUCT_NAME}-v${VERSION}.app"
APP_BUNDLE="$PROJECT_ROOT/$APP_BUNDLE_NAME"
DMG_PATH="$PROJECT_ROOT/${PRODUCT_NAME}-v${VERSION}.dmg"

# The current Command Line Tools can temporarily expose a newest SDK whose
# Swift interface was produced by a different patch release. Prefer the locally
# installed, proven-compatible 15.4 SDK when present; callers can still provide
# NAGA_SDKROOT explicitly after a future toolchain update.
if [[ -n "${NAGA_SDKROOT:-}" ]]; then
  export SDKROOT="$NAGA_SDKROOT"
elif [[ -d "/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk" ]]; then
  export SDKROOT="/Library/Developer/CommandLineTools/SDKs/MacOSX15.4.sdk"
else
  export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)"
fi

export CLANG_MODULE_CACHE_PATH="$MODULE_CACHE"
export SWIFTPM_MODULECACHE_OVERRIDE="$MODULE_CACHE"
mkdir -p "$MODULE_CACHE"

cleanup() {
  rm -rf "$SCRATCH_DIR"
}
trap cleanup EXIT

echo "Cleaning previous build artifacts..."
rm -rf "$BUILD_DIR" || true
"$SWIFT_BIN" package --disable-sandbox --package-path "$PROJECT_ROOT" clean >/dev/null 2>&1 || true

echo "Building for production..."
# Build release executable
"$SWIFT_BIN" build --disable-sandbox -c release --package-path "$PROJECT_ROOT" --scratch-path "$SCRATCH_DIR" \
  --jobs "${NAGA_BUILD_JOBS:-1}" \
  -Xswiftc -module-cache-path -Xswiftc "$MODULE_CACHE" \
  -Xswiftc -no-whole-module-optimization

# Verify the executable was actually built
if [[ ! -f "$EXECUTABLE_PATH" ]]; then
  echo "❌ Error: Build failed - executable not found at $EXECUTABLE_PATH"
  exit 1
fi

echo "Running HID report self-test..."
"$EXECUTABLE_PATH" --self-test-hid-codec

echo "Creating app bundle..."
# Create app bundle structure
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/Icons"

# Copy executable and resources
cp "$EXECUTABLE_PATH" "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
chmod +x "$APP_BUNDLE/Contents/MacOS/$EXECUTABLE_NAME"
cp -R "$PROJECT_ROOT/Resources/"* "$APP_BUNDLE/Contents/Resources/" 2>/dev/null || true

# Create/merge Info.plist
if [[ -f "$PROJECT_ROOT/Resources/Info.plist" ]]; then
  cp "$PROJECT_ROOT/Resources/Info.plist" "$APP_BUNDLE/Contents/Info.plist"
else
  cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key>
  <string>com.vmouse.mousemapper</string>
  <key>CFBundleName</key>
  <string>V-Mouse鼠标映射</string>
  <key>CFBundleDisplayName</key>
  <string>V-Mouse鼠标映射</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundleExecutable</key>
  <string>NagaController</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>0.7.4</string>
  <key>CFBundleVersion</key>
  <string>72</string>
  <key>LSMinimumSystemVersion</key>
  <string>13.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSAppleEventsUsageDescription</key>
  <string>V-Mouse鼠标映射需要处理并发送输入事件，以执行您设置的鼠标按键二次映射。</string>
</dict>
</plist>
PLIST
fi

# Keep the user-facing product name stable. The output filename carries only
# the semantic version, while bundle ID and executable remain compatible.
/usr/libexec/PlistBuddy -c "Set :CFBundleName ${PRODUCT_NAME}" "$APP_BUNDLE/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier ${BUNDLE_ID}" "$APP_BUNDLE/Contents/Info.plist"
if /usr/libexec/PlistBuddy -c 'Print :CFBundleDisplayName' "$APP_BUNDLE/Contents/Info.plist" >/dev/null 2>&1; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName ${PRODUCT_NAME}" "$APP_BUNDLE/Contents/Info.plist"
else
  /usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string ${PRODUCT_NAME}" "$APP_BUNDLE/Contents/Info.plist"
fi
echo "Code signing..."
# Test builds remain ad-hoc by default. VMOUSE_RELEASE=1 is fail-closed: it
# requires a Developer ID identity plus an existing notarytool keychain profile.
SIGNING_IDENTITY="${VMOUSE_SIGNING_IDENTITY:-${NAGA_SIGNING_IDENTITY:--}}"
RELEASE_BUILD="${VMOUSE_RELEASE:-0}"
NOTARY_PROFILE="${VMOUSE_NOTARY_PROFILE:-}"
if [[ "$RELEASE_BUILD" == "1" ]]; then
  if [[ "$SIGNING_IDENTITY" == "-" || -z "$SIGNING_IDENTITY" || -z "$NOTARY_PROFILE" ]]; then
    echo "❌ Release build requires VMOUSE_SIGNING_IDENTITY and VMOUSE_NOTARY_PROFILE." >&2
    exit 4
  fi
  codesign --force --deep --options runtime --timestamp --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
  codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
else
  codesign --force --deep --sign "$SIGNING_IDENTITY" "$APP_BUNDLE"
fi

# Remove quarantine attributes if present
xattr -dr com.apple.quarantine "$APP_BUNDLE" 2>/dev/null || true

DMG_STAGING="$SCRATCH_DIR/dmg-root"

echo "Creating versioned DMG..."
mkdir -p "$DMG_STAGING"
cp -R "$APP_BUNDLE" "$DMG_STAGING/"
ln -s /Applications "$DMG_STAGING/Applications"
hdiutil create \
  -volname "${PRODUCT_NAME} ${VERSION}" \
  -srcfolder "$DMG_STAGING" \
  -format UDZO \
  -ov \
  "$DMG_PATH" >/dev/null
hdiutil verify "$DMG_PATH" >/dev/null

if [[ "$RELEASE_BUILD" == "1" ]]; then
  echo "Signing and notarizing DMG..."
  codesign --force --timestamp --sign "$SIGNING_IDENTITY" "$DMG_PATH"
  xcrun notarytool submit "$DMG_PATH" --keychain-profile "$NOTARY_PROFILE" --wait
  xcrun stapler staple "$DMG_PATH"
  xcrun stapler validate "$DMG_PATH"
  spctl --assess --type open --context context:primary-signature --verbose=2 "$DMG_PATH"
fi

echo "✅ Build successful!"
echo "📦 App bundle: $APP_BUNDLE"
echo "💿 DMG installer: $DMG_PATH"
echo ""
echo "To run: open $APP_BUNDLE"
