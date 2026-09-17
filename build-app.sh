#!/bin/zsh
# ai coding: 构建包含隐藏数量、尺寸复制和批量新建的 SideDrawer 2026/09/17: 11:14
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
APP_PATH="$SCRIPT_DIR/outputs/SideDrawer.app"
CONTENTS_PATH="$APP_PATH/Contents"
MODULE_CACHE="$SCRIPT_DIR/work/ModuleCache"

cd "$SCRIPT_DIR"
rm -rf "$APP_PATH"
mkdir -p "$CONTENTS_PATH/MacOS" "$CONTENTS_PATH/Resources"
mkdir -p "$MODULE_CACHE"
clang -fobjc-arc -fblocks -fmodules \
    -fmodules-cache-path="$MODULE_CACHE" \
    -mmacosx-version-min=14.0 \
    -framework Cocoa \
    -framework ApplicationServices \
    -framework Carbon \
    -framework QuartzCore \
    "Sources/SideDrawer/main.m" \
    -o "$CONTENTS_PATH/MacOS/SideDrawer"
cp "Resources/Info.plist" "$CONTENTS_PATH/Info.plist"
cp "Resources/SideDrawer.icns" "$CONTENTS_PATH/Resources/SideDrawer.icns"
chmod +x "$CONTENTS_PATH/MacOS/SideDrawer"
codesign --force --deep --sign - "$APP_PATH"

echo "$APP_PATH"
