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
ICON_SOURCE="$ROOT_DIR/Assets/AppIcon.png"

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

if [[ ! -f "$ICON_SOURCE" ]]; then
    echo "Missing app icon source: $ICON_SOURCE" >&2
    exit 1
fi

ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"

create_icon_size() {
    local size="$1"
    local output="$2"
    sips -z "$size" "$size" "$ICON_SOURCE" --out "$ICONSET_DIR/$output" >/dev/null
}

create_icon_size 16 icon_16x16.png
create_icon_size 32 icon_16x16@2x.png
create_icon_size 32 icon_32x32.png
create_icon_size 64 icon_32x32@2x.png
create_icon_size 128 icon_128x128.png
create_icon_size 256 icon_128x128@2x.png
create_icon_size 256 icon_256x256.png
create_icon_size 512 icon_256x256@2x.png
create_icon_size 512 icon_512x512.png
create_icon_size 1024 icon_512x512@2x.png

iconutil -c icns "$ICONSET_DIR" -o "$RESOURCES_DIR/AppIcon.icns"
rm -rf "$ICONSET_DIR"

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
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
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
