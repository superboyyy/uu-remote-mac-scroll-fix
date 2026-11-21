#!/bin/zsh
# 构建 UURemoteScrollSettings.app 和 UUTrackpadFix.app。
# 用法：./build-app.command [输出目录]   （默认输出到 ./build）
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SRC="$SCRIPT_DIR/UURemoteScrollSettings.app.src"
OUT="${1:-$SCRIPT_DIR/build}"
MIN_MACOS="12.0"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  echo "未找到 swiftc，请先安装 Apple 命令行开发工具：xcode-select --install" >&2
  exit 1
fi

# 分别编译 arm64 和 x86_64 再合并，产物在 Apple 芯片和 Intel 的 Mac 上都能运行。
# 显式指定最低系统版本；不指定时 swiftc 会以构建机的系统版本为准。
build_universal() {
  local output="$1"
  shift
  local arch
  local -a slices
  for arch in arm64 x86_64; do
    xcrun swiftc -O -target "$arch-apple-macos$MIN_MACOS" "$@" -o "$output.$arch"
    slices+=("$output.$arch")
  done
  /usr/bin/lipo -create "${slices[@]}" -output "$output"
  /bin/rm -f "${slices[@]}"
}

sign_app() {
  /usr/bin/xattr -cr "$1"
  /usr/bin/codesign --force --deep --sign - "$1"
  /usr/bin/codesign --verify --deep --strict "$1"
  /usr/bin/plutil -lint "$1/Contents/Info.plist" >/dev/null
}

SETTINGS_APP="$OUT/UURemoteScrollSettings.app"
TRACKPAD_APP="$OUT/UUTrackpadFix.app"
/bin/rm -rf "$SETTINGS_APP" "$TRACKPAD_APP"

echo "构建 UURemoteScrollSettings.app"
/bin/mkdir -p "$SETTINGS_APP/Contents/MacOS" "$SETTINGS_APP/Contents/Resources"
/bin/cp "$SRC/Info.plist" "$SETTINGS_APP/Contents/Info.plist"
# 图标由 tools/make-icon.swift 生成；zh-Hans.lproj 里是应用的中文显示名称。
/bin/cp "$SRC/AppIcon.icns" "$SETTINGS_APP/Contents/Resources/AppIcon.icns"
/bin/cp -R "$SRC/zh-Hans.lproj" "$SETTINGS_APP/Contents/Resources/"
build_universal "$SETTINGS_APP/Contents/MacOS/UURemoteScrollSettings" \
  -parse-as-library -framework SwiftUI -framework AppKit \
  "$SRC/UURemoteScrollSettings.swift"
sign_app "$SETTINGS_APP"

echo "构建 UUTrackpadFix.app"
/bin/mkdir -p "$TRACKPAD_APP/Contents/MacOS" "$TRACKPAD_APP/Contents/Resources"
/bin/cp "$SCRIPT_DIR/UUTrackpadFix-Info.plist" "$TRACKPAD_APP/Contents/Info.plist"
build_universal "$TRACKPAD_APP/Contents/MacOS/UUTrackpadFix" \
  -framework Cocoa -framework ApplicationServices \
  "$SCRIPT_DIR/UUTrackpadFix.swift"
# 记录源码指纹。安装脚本据此判断已安装的调速器是否需要替换：
# 临时签名的应用每次重新编译都会让之前的辅助功能授权失效，源码没变就不该替换。
/bin/cat "$SCRIPT_DIR/UUTrackpadFix.swift" "$SCRIPT_DIR/UUTrackpadFix-Info.plist" \
  | /usr/bin/shasum -a 256 | /usr/bin/awk '{print $1}' \
  > "$TRACKPAD_APP/Contents/Resources/source.sha256"
sign_app "$TRACKPAD_APP"

echo "构建完成："
echo "  $SETTINGS_APP"
echo "  $TRACKPAD_APP"
