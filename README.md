# UU Remote Mac Scroll Fix

[![macOS](https://img.shields.io/badge/macOS-12%2B-black?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/FlynnAIwang/uu-remote-mac-scroll-fix)](https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix/releases)

一键修复 UU 远程在 Mac 主控端常见的鼠标滚轮、触控板方向和速度问题，同时保留本机其他应用的 Mos 丝滑滚动体验。

> Unofficial community project. This repository is not affiliated with NetEase, UU Remote, or Mos.

## 解决什么问题

在 Mac 上使用 UU 远程控制另一台电脑时，可能遇到：

- 鼠标滚轮方向与本机相反。
- 鼠标滚轮经过平滑工具后，在远程桌面中无响应。
- 触控板滚动方向与本机相反。
- 触控板在远程桌面中滚动过快、过于灵敏。
- Mos 退出或升级后不再自动运行。
- 只修改 macOS“自然滚动”会同时破坏本机其他应用的操作习惯。

本项目把鼠标和触控板分开处理，避免它们互相干扰：

| 输入设备 | UU 远程窗口 | 本机其他应用 |
|---|---|---|
| 鼠标滚轮 | 使用 UU 兼容的原始滚轮事件，并独立修正方向 | Mos 丝滑滚动和方向补偿 |
| 触控板 | 方向反转，滚动量缩放至 `0.18` | 完全保持系统原始体验 |

## 工作原理

1. 安装并校验 Mos 4.2.1。
2. 普通 Mac 应用继续使用 Mos 的丝滑滚动。
3. 精确匹配 UU 的应用包、主进程与服务进程。
4. UU 鼠标使用原始滚轮事件，避免 UU 忽略 Mos 合成事件。
5. 本地编译一个开源轻量辅助程序，只缩放发往 UU 窗口的触控板连续滚动事件。
6. 使用用户级 LaunchAgent 保证 Mos 和触控板调速器登录后启动、退出后恢复。

辅助程序不联网、不读取键盘内容、不记录鼠标位置，也不会处理 UU 以外应用的触控板滚动。

## 快速安装

### 方法一：下载 Release（推荐）

1. 从 [Releases](https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix/releases) 下载最新 ZIP。
2. 解压整个文件夹。
3. 确保 UU 远程安装在 `/Applications/UURemote.app`。
4. 双击 `setup.command`，或双击 `一键配置UU远程鼠标.command`。
5. 如果 macOS 阻止运行：右键脚本 → **打开** → 再次点击 **打开**。
6. 在 **系统设置 → 隐私与安全性 → 辅助功能** 中允许：
   - `Mos`
   - `UU远程触控板调速器`

### 方法二：克隆仓库

```bash
git clone https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix.git
cd uu-remote-mac-scroll-fix
./setup.command
```

## 环境要求

- macOS 12 或更高版本。
- UU 远程位于 `/Applications/UURemote.app`。
- Apple Command Line Tools。未安装时，脚本会尝试打开系统安装提示。
- 首次安装需要联网下载 Mos。

## 安全措施

安装器会执行以下校验：

- 固定 Mos 版本及 Release 文件大小。
- 校验 Mos Release 的 SHA-256。
- 校验 Apple Gatekeeper 公证。
- 校验 Mos 开发者 Team ID。
- 替换旧版 Mos 前自动备份。
- 修改 Mos 偏好设置前自动备份。
- 触控板辅助程序直接从仓库内可审计的 Swift 源码在本机编译。

## 自定义触控板速度

默认倍率为 `0.18`。编辑 `com.user.uuremote.trackpadfix.plist`：

```xml
<key>UU_TRACKPAD_SCALE</key>
<string>0.18</string>
```

数值越小，滚动越慢。建议范围为 `0.10`–`0.35`。修改后重新运行 `setup.command`。

## 卸载与恢复

停止后台任务：

```bash
launchctl bootout "gui/$(id -u)/com.user.uuremote.mos"
launchctl bootout "gui/$(id -u)/com.user.uuremote.trackpadfix"
```

然后删除：

```text
~/Library/LaunchAgents/com.user.uuremote.mos.plist
~/Library/LaunchAgents/com.user.uuremote.trackpadfix.plist
/Applications/UUTrackpadFix.app
```

最后在 **系统设置 → 鼠标** 中恢复你原来的“自然滚动”选项。旧版 Mos 和偏好设置备份不会被自动删除。

## 已知限制

- UU 远程 4.35.0 对 Mos 合成平滑滚轮事件的兼容性不稳定，因此 UU 窗口内的鼠标使用原始滚轮事件。
- 触控板辅助程序首次运行必须由用户手动授予辅助功能权限，这是 macOS 的安全限制。
- UU 或 Mos 更新后若修改进程结构，可能需要更新匹配路径。

## 贡献与反馈

欢迎提交 Issue 和 Pull Request。反馈问题时请提供：

- macOS 版本与芯片类型。
- UU 远程版本。
- 鼠标或触控板型号。
- 具体表现：方向错误、速度异常或无响应。
- `/tmp/com.user.uuremote.trackpadfix.stderr.log` 中与问题相关的日志。

## License

本项目代码使用 [MIT License](LICENSE)。Mos 和 UU 远程分别受其自身许可证与服务条款约束；本项目不分发它们的二进制文件。

