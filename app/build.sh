#!/bin/bash
#
# Build LogiBattery.app: compile the Swift sources, render and package the app
# icon, assemble the bundle, and ad-hoc sign it for integrity checks.
#
# Needs only the Command Line Tools (plus iconutil, which ships with macOS) - no
# Xcode, no provisioning profile, no Apple Developer account. The signature is
# ad-hoc ("-"): this is NOT Developer ID signing or notarization. Downloaded
# builds may be blocked by Gatekeeper.
#
#   ./build.sh          build the app and the hidprobe diagnostic CLI
#   ./build.sh --icons  also keep the rendered .iconset and PNG previews
#   ARCHS="arm64 x86_64" ./build.sh  build a universal app and probe
#
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(dirname "$HERE")"
APP="$ROOT/LogiBattery.app"
BUILD="$HERE/build"
ARCHS="${ARCHS:-$(uname -m)}"
HOST_TARGET="$(uname -m)-apple-macos13.0"
KEEP_ICON_SOURCES="${1:-}"

echo "==> compiling ($ARCHS)"
rm -rf "$APP" "$BUILD"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$BUILD"

APP_SLICES=()
for ARCH in $ARCHS; do
    case "$ARCH" in
        arm64|x86_64) ;;
        *) echo "Unsupported architecture: $ARCH" >&2; exit 1 ;;
    esac
    swiftc -O -target "$ARCH-apple-macos13.0" \
    "$HERE/Sources/HIDPP.swift" \
    "$HERE/Sources/Model.swift" \
    "$HERE/Sources/App.swift" \
    "$HERE/Sources/main.swift" \
    -o "$BUILD/LogiBattery-$ARCH"
    APP_SLICES+=("$BUILD/LogiBattery-$ARCH")
done
lipo -create "${APP_SLICES[@]}" \
    -output "$APP/Contents/MacOS/LogiBattery"

echo "==> writing Info.plist"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleName</key>
	<string>LogiBattery</string>
	<key>CFBundleDisplayName</key>
	<string>LogiBattery</string>
	<key>CFBundleIdentifier</key>
	<string>local.logibattery</string>
	<key>CFBundleExecutable</key>
	<string>LogiBattery</string>
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>LSMinimumSystemVersion</key>
	<string>13.0</string>
	<!-- Menu bar only: no Dock icon, no window. -->
	<key>LSUIElement</key>
	<true/>
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST

echo "==> rendering app icon"
swiftc -O -target "$HOST_TARGET" "$HERE/icon/main.swift" -o "$BUILD/iconmaker"
ICONSET="$BUILD/AppIcon.iconset"
if [ "$KEEP_ICON_SOURCES" = "--icons" ]; then
    "$BUILD/iconmaker" "$ICONSET" --preview "$BUILD/icon-preview"
else
    "$BUILD/iconmaker" "$ICONSET"
fi
iconutil --convert icns --output "$APP/Contents/Resources/AppIcon.icns" "$ICONSET"
echo "    $APP/Contents/Resources/AppIcon.icns"

echo "==> building hidprobe diagnostic"
PROBE_SLICES=()
for ARCH in $ARCHS; do
    swiftc -O -target "$ARCH-apple-macos13.0" \
    "$HERE/Sources/HIDPP.swift" \
    "$HERE/Sources/Model.swift" \
    "$HERE/probe/main.swift" \
    -o "$BUILD/hidprobe-$ARCH"
    PROBE_SLICES+=("$BUILD/hidprobe-$ARCH")
done
lipo -create "${PROBE_SLICES[@]}" \
    -output "$BUILD/hidprobe"
echo "    $BUILD/hidprobe"

# Signing must come last: the signature seals Resources, so the icon has to be
# in place before it is computed.
echo "==> signing (ad-hoc)"
codesign --force --sign - --timestamp=none "$APP"
codesign --verify --strict --verbose=2 "$APP" 2>&1 | sed 's/^/    /'

echo "==> built $APP"
