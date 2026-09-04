#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
RULE_FILE="$SCRIPT_DIR/uuremote-mos-rules.json"
AGENT_TEMPLATE="$SCRIPT_DIR/com.user.uuremote.mos.plist"
TRACKPAD_SOURCE="$SCRIPT_DIR/UUTrackpadFix.swift"
TRACKPAD_INFO="$SCRIPT_DIR/UUTrackpadFix-Info.plist"
TRACKPAD_AGENT_TEMPLATE="$SCRIPT_DIR/com.user.uuremote.trackpadfix.plist"
SETTINGS_SOURCE="$SCRIPT_DIR/UURemoteScrollSettings.app.src/UURemoteScrollSettings.swift"
SETTINGS_INFO="$SCRIPT_DIR/UURemoteScrollSettings.app.src/Info.plist"
SETTINGS_RULE_WINDOWS="$SCRIPT_DIR/UURemoteScrollSettings.app.src/uuremote-mos-rules-windows.json"
SETTINGS_RULE_MAC="$SCRIPT_DIR/UURemoteScrollSettings.app.src/uuremote-mos-rules-mac.json"
SETTINGS_APP="/Applications/UURemoteScrollSettings.app"
MOS_APP="/Applications/Mos.app"
UU_APP="/Applications/UURemote.app"
TRACKPAD_APP="/Applications/UUTrackpadFix.app"
MOS_VERSION="4.2.1"
MOS_ASSET="Mos.Versions.4.2.1-20260531.1.zip"
MOS_SIZE="12127893"
MOS_SHA256="2ea69e96f092e44dada93a55bda1cddab3329c527bbd5f06e00dfb78e953960a"
MOS_TEAM_ID="N7Z52F27XK"
LAUNCH_LABEL="com.user.uuremote.mos"
LAUNCH_AGENT="$HOME/Library/LaunchAgents/$LAUNCH_LABEL.plist"
TRACKPAD_LAUNCH_LABEL="com.user.uuremote.trackpadfix"
TRACKPAD_LAUNCH_AGENT="$HOME/Library/LaunchAgents/$TRACKPAD_LAUNCH_LABEL.plist"
USER_ID="$(id -u)"
TASK_TEMP="$(/usr/bin/mktemp -d /tmp/uuremote-mos-setup.XXXXXX)"

cleanup() {
  if [[ "$TASK_TEMP" == /tmp/uuremote-mos-setup.* && -d "$TASK_TEMP" ]]; then
    /usr/bin/find "$TASK_TEMP" -depth -delete 2>/dev/null || true
  fi
}

pause_on_exit() {
  echo
  if [[ -t 0 ]]; then
    read -k 1 "?按任意键关闭窗口..."
  fi
}
trap pause_on_exit INT TERM

finish() {
  exit_status=$?
  cleanup
  if (( exit_status != 0 )); then
    echo
    echo "脚本异常结束，错误码：$exit_status" >&2
    pause_on_exit
  fi
}
trap finish EXIT

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
  echo
  echo "配置失败：$*" >&2
  exit 1
}

[[ "$(uname -s)" == "Darwin" ]] || fail "此脚本只能在 macOS 上运行。"
[[ -d "$UU_APP" ]] || fail "未找到 $UU_APP，请先安装 UU 远程。"
[[ -f "$RULE_FILE" ]] || fail "缺少配置文件：$RULE_FILE"
[[ -f "$AGENT_TEMPLATE" ]] || fail "缺少后台启动文件：$AGENT_TEMPLATE"
[[ -f "$TRACKPAD_SOURCE" ]] || fail "缺少触控板调速器源码：$TRACKPAD_SOURCE"
[[ -f "$TRACKPAD_INFO" ]] || fail "缺少触控板调速器信息文件：$TRACKPAD_INFO"
[[ -f "$TRACKPAD_AGENT_TEMPLATE" ]] || fail "缺少触控板后台启动文件：$TRACKPAD_AGENT_TEMPLATE"
[[ -f "$SETTINGS_SOURCE" ]] || fail "缺少设置应用源码：$SETTINGS_SOURCE"
[[ -f "$SETTINGS_INFO" ]] || fail "缺少设置应用信息文件：$SETTINGS_INFO"
[[ -f "$SETTINGS_RULE_WINDOWS" ]] || fail "缺少 Windows 模式规则：$SETTINGS_RULE_WINDOWS"
[[ -f "$SETTINGS_RULE_MAC" ]] || fail "缺少 Mac 模式规则：$SETTINGS_RULE_MAC"

current_version=""
if [[ -d "$MOS_APP" ]]; then
  current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOS_APP/Contents/Info.plist" 2>/dev/null || true)"
fi

if [[ "$current_version" != "$MOS_VERSION" ]]; then
  log "准备安装 Mos $MOS_VERSION"
  official_url="https://github.com/Caldis/Mos/releases/download/$MOS_VERSION/$MOS_ASSET"
  download_urls=(
    "$official_url"
    "https://ghfast.top/$official_url"
    "https://gh-proxy.com/$official_url"
  )

  archive_path=""
  attempt=0
  for download_url in "${download_urls[@]}"; do
    attempt=$((attempt + 1))
    candidate="$TASK_TEMP/Mos-$attempt.zip"
    log "下载 Mos（线路 $attempt）"
    if /usr/bin/curl -fL --connect-timeout 10 --max-time 180 --speed-limit 1024 --speed-time 15 "$download_url" -o "$candidate"; then
      actual_size="$(/usr/bin/stat -f '%z' "$candidate")"
      actual_sha="$(/usr/bin/shasum -a 256 "$candidate" | /usr/bin/awk '{print $1}')"
      if [[ "$actual_size" == "$MOS_SIZE" && "$actual_sha" == "$MOS_SHA256" ]]; then
        archive_path="$candidate"
        break
      fi
      log "线路 $attempt 的文件校验不符，切换线路"
    fi
  done
  [[ -n "$archive_path" ]] || fail "Mos 下载失败，请检查网络后重试。"

  /usr/bin/ditto -x -k "$archive_path" "$TASK_TEMP/extracted"
  new_app="$TASK_TEMP/extracted/Mos.app"
  [[ -d "$new_app" ]] || fail "安装包中没有找到 Mos.app。"

  /usr/bin/codesign --verify --deep --strict "$new_app" || fail "Mos 代码签名验证失败。"
  /usr/sbin/spctl --assess --type execute "$new_app" || fail "Mos 未通过 Apple Gatekeeper 验证。"
  team_id="$(/usr/bin/codesign -dv --verbose=2 "$new_app" 2>&1 | /usr/bin/awk -F= '/TeamIdentifier=/{print $2}')"
  [[ "$team_id" == "$MOS_TEAM_ID" ]] || fail "Mos 开发者签名不匹配。"

  /usr/bin/osascript -e 'tell application "Mos" to quit' 2>/dev/null || true
  /bin/sleep 1
  if [[ -d "$MOS_APP" ]]; then
    backup_version="${current_version:-unknown}"
    backup_path="/Applications/Mos ${backup_version} Backup $(date '+%Y%m%d-%H%M%S').app"
    /bin/mv "$MOS_APP" "$backup_path" || fail "无法备份旧版 Mos。"
    log "旧版已备份到 $backup_path"
  fi
  /bin/mv "$new_app" "$MOS_APP" || fail "无法把 Mos 安装到 /Applications。"
  log "Mos $MOS_VERSION 安装完成"
else
  log "Mos 已是指定版本 $MOS_VERSION"
fi

log "构建 UU 触控板专用调速器"
swift_compiler="$(xcrun --find swiftc 2>/dev/null || true)"
if [[ -z "$swift_compiler" ]]; then
  xcode-select --install 2>/dev/null || true
  fail "此 Mac 尚未安装 Apple 命令行开发工具。系统已尝试打开安装窗口，安装完成后请再次运行脚本。"
fi

trackpad_build="$TASK_TEMP/UUTrackpadFix.app"
/bin/mkdir -p "$trackpad_build/Contents/MacOS"
/bin/cp "$TRACKPAD_INFO" "$trackpad_build/Contents/Info.plist"
xcrun swiftc -O -framework Cocoa -framework ApplicationServices "$TRACKPAD_SOURCE" -o "$trackpad_build/Contents/MacOS/UUTrackpadFix"
/usr/bin/codesign --force --deep --sign - "$trackpad_build"
/usr/bin/codesign --verify --deep --strict "$trackpad_build" || fail "触控板调速器签名失败。"

launchctl bootout "gui/$USER_ID/$TRACKPAD_LAUNCH_LABEL" 2>/dev/null || true
if [[ -d "$TRACKPAD_APP" ]]; then
  trackpad_backup="/Applications/UUTrackpadFix Backup $(date '+%Y%m%d-%H%M%S').app"
  /bin/mv "$TRACKPAD_APP" "$trackpad_backup" || fail "无法备份旧版触控板调速器。"
fi
/bin/mv "$trackpad_build" "$TRACKPAD_APP" || fail "无法安装触控板调速器。"
log "UU 触控板调速器安装完成（倍率 0.18，方向与本机一致）"

log "构建 UU 远程鼠标设置应用"
settings_build="$TASK_TEMP/UURemoteScrollSettings.app"
/bin/mkdir -p "$settings_build/Contents/MacOS" "$settings_build/Contents/Resources"
/bin/cp "$SETTINGS_INFO" "$settings_build/Contents/Info.plist"
/bin/cp "$SETTINGS_RULE_WINDOWS" "$settings_build/Contents/Resources/uuremote-mos-rules-windows.json"
/bin/cp "$SETTINGS_RULE_MAC" "$settings_build/Contents/Resources/uuremote-mos-rules-mac.json"
/bin/chmod 644 "$settings_build/Contents/Resources/"*.json
xcrun swiftc -parse-as-library -O -framework SwiftUI -framework AppKit "$SETTINGS_SOURCE" -o "$settings_build/Contents/MacOS/UURemoteScrollSettings"
/usr/bin/xattr -cr "$settings_build"
/usr/bin/codesign --force --deep --sign - "$settings_build"
/usr/bin/codesign --verify --deep --strict "$settings_build" || fail "设置应用签名失败。"
if [[ -d "$SETTINGS_APP" ]]; then
  settings_backup="/Applications/UURemoteScrollSettings Backup $(date '+%Y%m%d-%H%M%S').app"
  /bin/mv "$SETTINGS_APP" "$settings_backup" || fail "无法备份旧版设置应用。"
fi
/bin/mv "$settings_build" "$SETTINGS_APP" || fail "无法安装设置应用。"
log "UU 远程鼠标设置应用安装完成：$SETTINGS_APP"

log "备份并写入滚动配置"
preferences_file="$HOME/Library/Preferences/com.caldis.Mos.plist"
if [[ -f "$preferences_file" ]]; then
  /bin/cp -p "$preferences_file" "$preferences_file.backup-$(date '+%Y%m%d-%H%M%S')"
fi

launchctl bootout "gui/$USER_ID/com.codex.mos.runtime" 2>/dev/null || true
launchctl bootout "gui/$USER_ID/$LAUNCH_LABEL" 2>/dev/null || true
/usr/bin/osascript -e 'tell application "Mos" to quit' 2>/dev/null || true
/bin/sleep 1

rule_hex="$(/usr/bin/xxd -p -c 1000000 "$RULE_FILE")"

# 保留 macOS“自然滚动”；本机普通应用由 Mos 做方向补偿，保持自然滚动手感。
defaults write NSGlobalDomain com.apple.swipescrolldirection -bool true

# Mos 全局配置：普通应用启用丝滑滚动，并通过方向补偿保持自然滚动手感。
defaults write com.caldis.Mos allowlist -bool false
defaults write com.caldis.Mos applications -data "$rule_hex"
defaults write com.caldis.Mos hideStatusItem -bool false
defaults write com.caldis.Mos smooth -bool true
defaults write com.caldis.Mos smoothVertical -bool true
defaults write com.caldis.Mos smoothHorizontal -bool true
defaults write com.caldis.Mos smoothSimTrackpad -bool false
defaults write com.caldis.Mos reverse -bool true
defaults write com.caldis.Mos reverseVertical -bool true
defaults write com.caldis.Mos reverseHorizontal -bool true
defaults write com.caldis.Mos step -float 36.00965073529412
defaults write com.caldis.Mos speed -float 4.874310661764706
defaults write com.caldis.Mos duration -float 3.9
defaults write com.caldis.Mos deadZone -float 1.0

/bin/mkdir -p "$HOME/Library/LaunchAgents"
/bin/cp "$AGENT_TEMPLATE" "$LAUNCH_AGENT"
/bin/cp "$TRACKPAD_AGENT_TEMPLATE" "$TRACKPAD_LAUNCH_AGENT"
/usr/bin/plutil -lint "$LAUNCH_AGENT" >/dev/null || fail "后台启动文件格式错误。"
/usr/bin/plutil -lint "$TRACKPAD_LAUNCH_AGENT" >/dev/null || fail "触控板后台启动文件格式错误。"
launchctl bootstrap "gui/$USER_ID" "$LAUNCH_AGENT" || fail "无法启动 Mos 后台任务。"
launchctl bootstrap "gui/$USER_ID" "$TRACKPAD_LAUNCH_AGENT" || fail "无法启动触控板后台任务。"
launchctl kickstart -k "gui/$USER_ID/$LAUNCH_LABEL"
launchctl kickstart -k "gui/$USER_ID/$TRACKPAD_LAUNCH_LABEL"
/bin/sleep 3

installed_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOS_APP/Contents/Info.plist")"
job_state="$(launchctl print "gui/$USER_ID/$LAUNCH_LABEL" 2>/dev/null | /usr/bin/awk -F'= ' '/^[[:space:]]*state =/{print $2; exit}')"
trackpad_job_state="$(launchctl print "gui/$USER_ID/$TRACKPAD_LAUNCH_LABEL" 2>/dev/null | /usr/bin/awk -F'= ' '/^[[:space:]]*state =/{print $2; exit}')"
[[ "$installed_version" == "$MOS_VERSION" ]] || fail "安装后的版本校验失败。"
[[ "$job_state" == "running" ]] || fail "Mos 后台进程未正常运行。"
[[ "$trackpad_job_state" == "running" ]] || fail "触控板调速进程未正常运行。"

echo
echo "配置完成："
echo "  • 本机普通应用：自然滚动手感 + Mos 丝滑滚动和方向补偿"
echo "  • UU 鼠标：仅发往 Windows 远程桌面时单独反转方向"
echo "  • UU 触控板：仅在 UU 窗口内缩放连续滚动，方向与本机自然滚动一致（不影响本机）"
echo "  • 设置应用：$SETTINGS_APP，可在 Mac 控制 Mac / Windows 之间一键切换"
echo "  • Mos：$installed_version，已设置登录后自动运行"
echo
echo "首次安装时，如果 macOS 弹出辅助功能权限，请允许以下两项："
echo "  1. Mos"
echo "  2. UU远程触控板调速器"
echo "路径：系统设置 → 隐私与安全性 → 辅助功能"
echo
if [[ -t 0 ]]; then
  read -k 1 "?按任意键关闭窗口..."
fi
