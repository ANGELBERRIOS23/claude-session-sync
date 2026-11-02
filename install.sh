#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="Claude Session Sync"
VERSION="1.1.1"
# CI builds the bundle into its own folder instead of /Applications.
APP_DIR="${APP_DIR:-/Applications}"
APP_BUNDLE="${APP_DIR}/${APP_NAME}.app"

BUILD_FLAGS=(-c release -Xswiftc -swift-version -Xswiftc 5)
# UNIVERSAL=1 builds one binary for Apple Silicon and Intel (used for releases).
if [ "${UNIVERSAL:-0}" = 1 ]; then
    BUILD_FLAGS+=(--arch arm64 --arch x86_64)
fi

echo "Building release binary..."
cd "$SCRIPT_DIR"
swift build "${BUILD_FLAGS[@]}" 2>&1 | tail -3

BINARY="$(swift build "${BUILD_FLAGS[@]}" --show-bin-path)/ClaudeSessionSync"
if [ ! -f "$BINARY" ]; then
    echo "Build failed."
    exit 1
fi

echo "Creating app bundle at $APP_BUNDLE..."
rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$BINARY" "$APP_BUNDLE/Contents/MacOS/ClaudeSessionSync"

if [ -f "$SCRIPT_DIR/AppIcon.icns" ]; then
    cp "$SCRIPT_DIR/AppIcon.icns" "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
fi

cat > "$APP_BUNDLE/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ClaudeSessionSync</string>
    <key>CFBundleIdentifier</key>
    <string>com.angelberrios.claude-session-sync</string>
    <key>CFBundleName</key>
    <string>Claude Session Sync</string>
    <key>CFBundleDisplayName</key>
    <string>Claude Session Sync</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleVersion</key>
    <string>${VERSION}</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
</dict>
</plist>
PLIST

# Ad-hoc sign the whole bundle so macOS treats the binary, icon and Info.plist as one app.
codesign --force --deep --sign - "$APP_BUNDLE"

echo ""
echo "Done! Installed at: $APP_BUNDLE"
echo ""
echo "You can now:"
echo "  - Find it in Launchpad / Spotlight: search 'Claude Session Sync'"
echo "  - Open it: open '/Applications/Claude Session Sync.app'"
echo "  - Enable 'Launch at login' from the menubar toggle"
