#!/bin/zsh
set -euo pipefail
APP="/Applications/UURemoteScrollSettings.app"
if [[ ! -d "$APP" ]]; then
  echo "未找到 $APP，请先运行“一键配置UU远程鼠标.command”。" >&2
  exit 1
fi
open "$APP"
