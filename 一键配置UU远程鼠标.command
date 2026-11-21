#!/bin/zsh
# 一键安装：Mos（缺失或过旧时）+ UUTrackpadFix + 设置应用，然后启用一个远程模式。
# 用法：./一键配置UU远程鼠标.command [windows|mac|off]
#       不带参数时沿用上次选择的模式；首次安装默认 windows。
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
BUILD_SCRIPT="$SCRIPT_DIR/build-app.command"
SETTINGS_APP="/Applications/UURemoteScrollSettings.app"
SETTINGS_BIN="$SETTINGS_APP/Contents/MacOS/UURemoteScrollSettings"
TRACKPAD_APP="/Applications/UUTrackpadFix.app"
MOS_APP="/Applications/Mos.app"
UU_APP="/Applications/UURemote.app"
# 需要的最低 Mos 版本；本机没有 Mos 或版本更旧时安装这一版。
MOS_VERSION="4.2.1"
MOS_ASSET="Mos.Versions.4.2.1-20260531.1.zip"
MOS_SIZE="12127893"
MOS_SHA256="2ea69e96f092e44dada93a55bda1cddab3329c527bbd5f06e00dfb78e953960a"
MOS_TEAM_ID="N7Z52F27XK"
TRACKPAD_LAUNCH_LABEL="com.user.uuremote.trackpadfix"
BACKUP_DIR="$HOME/Library/Application Support/UURemoteScrollSettings/旧版应用备份"
USER_ID="$(id -u)"
MODE="${1:-default}"
TASK_TEMP="$(/usr/bin/mktemp -d /tmp/uuremote-setup.XXXXXX)"

autoload -Uz is-at-least

cleanup() {
  if [[ "$TASK_TEMP" == /tmp/uuremote-setup.* && -d "$TASK_TEMP" ]]; then
    /bin/rm -rf "$TASK_TEMP"
  fi
}

pause_on_exit() {
  echo
  if [[ -t 0 ]]; then
    read -k 1 "?按任意键关闭窗口..." || true
  fi
}

finish() {
  exit_status=$?
  cleanup
  if (( exit_status != 0 )); then
    echo
    echo "脚本异常结束，错误码：$exit_status" >&2
  fi
  pause_on_exit
}
trap finish EXIT
# Ctrl-C 或被终止时直接退出，不再继续执行后面的步骤。
trap 'exit 130' INT
trap 'exit 143' TERM

log() {
  echo "[$(date '+%H:%M:%S')] $*"
}

fail() {
  echo
  echo "配置失败：$*" >&2
  exit 1
}

case "$MODE" in
  windows|mac|off|default) ;;
  *) fail "未知模式：$MODE（可选 windows / mac / off）" ;;
esac

[[ "$(uname -s)" == "Darwin" ]] || fail "此脚本只能在 macOS 上运行。"
[[ -d "$UU_APP" ]] || fail "未找到 $UU_APP，请先安装 UU 远程。"
[[ -x "$BUILD_SCRIPT" ]] || fail "缺少构建脚本：$BUILD_SCRIPT"
[[ -w /Applications ]] || fail "当前用户没有 /Applications 的写入权限，请使用管理员账户运行。"

if ! xcrun --find swiftc >/dev/null 2>&1; then
  xcode-select --install 2>/dev/null || true
  fail "此 Mac 尚未安装 Apple 命令行开发工具。系统已尝试打开安装窗口，安装完成后请再次运行脚本。"
fi

# ---------- Mos ----------
current_version=""
if [[ -d "$MOS_APP" ]]; then
  current_version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$MOS_APP/Contents/Info.plist" 2>/dev/null || true)"
fi

# 只在缺失或版本过旧时安装；已有更新的版本不会被降级。
if [[ -n "$current_version" ]] && is-at-least "$MOS_VERSION" "$current_version"; then
  log "已安装 Mos $current_version，跳过"
else
  log "准备安装 Mos $MOS_VERSION"
  official_url="https://github.com/Caldis/Mos/releases/download/$MOS_VERSION/$MOS_ASSET"
  # 镜像只用于加速；无论走哪条线路，文件都必须通过下面的大小、哈希和签名校验。
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

  # 旧版本曾用后台任务守护 Mos，不先卸载的话 Mos 退出后会被立刻拉起。
  launchctl bootout "gui/$USER_ID/com.user.uuremote.mos" 2>/dev/null || true
  /usr/bin/pkill -x Mos 2>/dev/null || true
  /bin/sleep 1
  if [[ -d "$MOS_APP" ]]; then
    /bin/mkdir -p "$BACKUP_DIR"
    backup_path="$BACKUP_DIR/Mos ${current_version:-unknown} $(date '+%Y%m%d-%H%M%S').app"
    /bin/mv "$MOS_APP" "$backup_path" || fail "无法备份旧版 Mos。"
    log "旧版 Mos 已移到 $backup_path"
  fi
  /bin/mv "$new_app" "$MOS_APP" || fail "无法把 Mos 安装到 /Applications。"
  log "Mos $MOS_VERSION 安装完成"
fi

# ---------- 构建 ----------
log "从源码构建设置应用和触控板调速器"
# 构建输出只在失败时显示，避免编译器的提示刷屏。
if ! "$BUILD_SCRIPT" "$TASK_TEMP/build" >"$TASK_TEMP/build.log" 2>&1; then
  /bin/cat "$TASK_TEMP/build.log" >&2
  fail "构建失败。"
fi
new_settings="$TASK_TEMP/build/UURemoteScrollSettings.app"
new_trackpad="$TASK_TEMP/build/UUTrackpadFix.app"

# ---------- 触控板调速器 ----------
# 临时签名的应用每次重新编译都会让辅助功能授权失效，所以源码没变就保留已安装的那份。
new_fingerprint="$(/bin/cat "$new_trackpad/Contents/Resources/source.sha256")"
installed_fingerprint="$(/bin/cat "$TRACKPAD_APP/Contents/Resources/source.sha256" 2>/dev/null || true)"
trackpad_replaced=0
if [[ -n "$installed_fingerprint" && "$installed_fingerprint" == "$new_fingerprint" ]] \
   && /usr/bin/codesign --verify --deep --strict "$TRACKPAD_APP" 2>/dev/null; then
  log "触控板调速器源码未变化，保留已安装的版本（辅助功能授权继续有效）"
else
  launchctl bootout "gui/$USER_ID/$TRACKPAD_LAUNCH_LABEL" 2>/dev/null || true
  /bin/rm -rf "$TRACKPAD_APP"
  /bin/mv "$new_trackpad" "$TRACKPAD_APP" || fail "无法安装触控板调速器。"
  trackpad_replaced=1
  log "触控板调速器安装完成：$TRACKPAD_APP"
fi

# ---------- 设置应用 ----------
/usr/bin/pkill -x UURemoteScrollSettings 2>/dev/null || true
/bin/rm -rf "$SETTINGS_APP"
/bin/mv "$new_settings" "$SETTINGS_APP" || fail "无法安装设置应用。"
log "设置应用安装完成：$SETTINGS_APP"

# ---------- 启用模式 ----------
# 规则写入、Mos 重启、后台任务都交给设置应用，和在界面里点模式卡片走的是同一套逻辑。
log "启用远程模式"
echo
"$SETTINGS_BIN" --apply "$MODE" || fail "启用模式失败，详见上方提示。"

echo
echo "安装完成。"
echo "  • 设置应用：$SETTINGS_APP（切换模式、调整触控板速度）"
echo "  • Mos 的开机自启：请在 Mos 偏好设置 → 通用 中开启“登录时启动”"
if (( trackpad_replaced )); then
  echo
  echo "触控板调速器是新安装或已更新的，需要重新授权辅助功能："
  echo "  系统设置 → 隐私与安全性 → 辅助功能 → 打开“UU远程触控板调速器”"
  echo "  如果列表里已有旧条目但不生效，请先用“−”删除它再重新添加。"
fi
