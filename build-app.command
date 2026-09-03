#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/UURemoteScrollSettings.app.src"
APP="$SCRIPT_DIR/build/UURemoteScrollSettings.app"

/bin/rm -rf "$SCRIPT_DIR/build"
/bin/mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
/bin/cp "$SRC/Info.plist" "$APP/Contents/Info.plist"
/bin/cp "$SRC/uuremote-mos-rules-windows.json" "$APP/Contents/Resources/"
/bin/cp "$SRC/uuremote-mos-rules-mac.json" "$APP/Contents/Resources/"
/bin/chmod 644 "$APP/Contents/Resources/"*.json

xcrun swiftc -parse-as-library -O -framework SwiftUI -framework AppKit \
  "$SRC/UURemoteScrollSettings.swift" \
  -o "$APP/Contents/MacOS/UURemoteScrollSettings"

/usr/bin/xattr -cr "$APP"
/usr/bin/codesign --force --deep --sign - "$APP"
/usr/bin/codesign --verify --deep --strict "$APP"
/usr/bin/plutil -lint "$APP/Contents/Info.plist" >/dev/null

echo "构建完成：$APP"
