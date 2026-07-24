#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Discord App Builder"
EXECUTABLE_NAME="DiscordAppBuilder"
BUILD_CONFIG="release"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

cd "$ROOT_DIR"

if [[ -z "${DEVELOPER_DIR:-}" ]]; then
    ACTIVE_DEVELOPER_DIR="$(xcode-select -p 2>/dev/null || true)"
    if [[ "$ACTIVE_DEVELOPER_DIR" == *".app/Contents/Developer" ]]; then
        export DEVELOPER_DIR="$ACTIVE_DEVELOPER_DIR"
    elif [[ -d "/Applications/Xcode.app/Contents/Developer" ]]; then
        export DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer"
    else
        for CANDIDATE in /Volumes/*/Applications/Xcode*.app/Contents/Developer; do
            if [[ -d "$CANDIDATE" ]]; then
                export DEVELOPER_DIR="$CANDIDATE"
                break
            fi
        done
        if [[ -z "${DEVELOPER_DIR:-}" ]]; then
            XCODE_APP="$(mdfind "kMDItemCFBundleIdentifier == 'com.apple.dt.Xcode'" 2>/dev/null | head -n 1)"
            if [[ -n "$XCODE_APP" && -d "$XCODE_APP/Contents/Developer" ]]; then
                export DEVELOPER_DIR="$XCODE_APP/Contents/Developer"
            fi
        fi
    fi
fi

if [[ "${DEVELOPER_DIR:-}" == *".app/Contents/Developer" ]]; then
    xcrun swift build -c "$BUILD_CONFIG"
else
    swift build -c "$BUILD_CONFIG"
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$ROOT_DIR/.build/$BUILD_CONFIG/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$CONTENTS_DIR/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>$APP_NAME</string>
    <key>CFBundleExecutable</key>
    <string>$EXECUTABLE_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>software.perfectlyplural.discord-app-builder</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticGraphicsSwitching</key>
    <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR"

echo "Created $APP_DIR"
