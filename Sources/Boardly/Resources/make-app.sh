#!/bin/bash
# 将 SwiftPM 构建产物打包为带自定义图标的 Boardly.app。
# 用法：bash Sources/Boardly/Resources/make-app.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
ICONSET="$ROOT/Sources/Boardly/Resources/AppIcon.iconset"
APP="$ROOT/build/Boardly.app"

cd "$ROOT"
swift build -c release

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Boardly" "$APP/Contents/MacOS/Boardly"

# iconutil（macOS 自带）把 iconset 编译为 icns。
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>Boardly</string>
    <key>CFBundleDisplayName</key>
    <string>Boardly</string>
    <key>CFBundleIdentifier</key>
    <string>dev.boardly.app</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleExecutable</key>
    <string>Boardly</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <false/>
    <key>NSSupportsSuddenTermination</key>
    <false/>
</dict>
</plist>
PLIST

# 临时签名让 Finder/Dock 正确加载图标。
codesign --force --sign - "$APP" >/dev/null 2>&1 || true

echo "已生成 ${APP}（Finder 中应显示自定义看板图标）"
