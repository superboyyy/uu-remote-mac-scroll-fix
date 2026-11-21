# UU Remote Mac Scroll Fix

[![macOS](https://img.shields.io/badge/macOS-12%2B-black?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/FlynnAIwang/uu-remote-mac-scroll-fix)](https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix/releases)

为 UU 远程提供 Mac 主控端鼠标滚轮 / 触控板方向修复，并附带一个可一键切换远程模式的 macOS 设置应用。

> Unofficial community project. This repository is not affiliated with NetEase, UU Remote, or Mos.

## 支持的远程模式

| 模式 | UU 窗口内鼠标滚轮 | UU 窗口内触控板 | 适用场景 |
|---|---|---|---|
| **Mac 控制 Windows** | 预设反向，符合 Windows 滚轮习惯 | 预设不反向，降速 | Mac 作为主控端连接 Windows |
| **Mac 控制 Mac** | 预设不反向 | 预设不反向，降速 | Mac 作为主控端连接另一台 Mac |
| **总开关关闭** | 不反向 | 不处理 | 临时排查或恢复 UU 原生行为 |

无论哪种状态都**不会**修改系统的“自然滚动”设置，也不会改动 Mos 的平滑、速度等全局参数。本机其他应用的滚动手感保持不变。

如果系统关闭了自然滚动，鼠标滚轮本来就是 Windows 方向，“Mac 控制 Windows”模式不会再反向。

## 快速安装

### 方法一：克隆仓库并一键安装（推荐）

```bash
git clone https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix.git
cd uu-remote-mac-scroll-fix
./setup.command
```

脚本会：

1. 本机没有 Mos 或版本低于 4.2.1 时，下载并校验 Mos 4.2.1；已有更新的版本不会被降级。
2. 从源码编译 `UUTrackpadFix.app` 和 `UURemoteScrollSettings.app` 并安装到 `/Applications`。
3. 启用一个远程模式（首次安装默认“Mac 控制 Windows”，之后沿用上次的选择）。

也可以直接指定模式：`./setup.command mac`。

### 方法二：下载 Release

1. 自行安装 [Mos](https://github.com/Caldis/Mos/releases) 并打开一次。
2. 打开 [Releases](https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix/releases)，下载 `UURemoteScrollSettings-macOS.zip`。
3. 解压后把 `UURemoteScrollSettings.app` 和 `UUTrackpadFix.app` 都放入 `/Applications`。
4. 打开 `UURemoteScrollSettings.app`，点击要用的模式。

Release 里的应用使用临时签名，会被 Gatekeeper 拦截。首次打开后到 **系统设置 → 隐私与安全性** 页面底部点击 **仍要打开**（macOS 15 起，右键“打开”已不能绕过拦截）。介意的话请用方法一从源码编译。

### 授权辅助功能

`Mos` 和 `UU远程触控板调速器` 首次运行都需要在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权。设置应用本身不需要这个权限；调速器未授权时，设置应用会显示提示和跳转按钮。

## 使用设置应用

1. 打开 `/Applications/UURemoteScrollSettings.app`（在访达和程序坞里显示为“UU远程滚动助手”）。
2. 点击模式卡片即可启用，应用会重启 Mos 并启动或停止触控板调速器。
3. 用“UU 触控板速度”滑块调整倍率（默认 ×0.18），松开后立即生效。
4. 切换到 UU 远程窗口测试滚动方向。方向不对时，用“鼠标滚轮反向”“触控板反向”两个开关单独调整；它们只作用于 UU 窗口。

模式卡片是预设：点卡片会把两个方向开关恢复为该模式的默认值。

标题栏右侧的**总开关**用来整体启用或关闭远程修正。关闭后停止触控板调速、UU 窗口内鼠标滚轮不再反向；重新打开时恢复关闭前的模式和两个方向开关。

**开机自启**开关（默认开启）决定登录后触控板调速器是否自动启动。关闭后，每次登录需要打开应用点一下“立即启用”。这个开关不会改动 Mos 的登录启动设置；如果 Mos 没有设置登录时启动，应用会给出提示。

点击模式卡片时应用做的事：

- 先检查 Mos、UU 远程、调速器是否都已安装，缺任何一项都不会改动配置。
- 备份 Mos 配置到 `~/Library/Application Support/UURemoteScrollSettings/Mos 配置备份/`（保留最近 10 份）。
- 退出 Mos → 只替换 Mos 分应用规则中 UU 远程的 3 条，其余应用的规则原样保留 → 重新启动 Mos。
- “Mac 控制 Windows”需要 Mos 的全局“反向滚动”处于开启状态（Mos 默认开启）；如果你关掉了它，应用会重新打开并给出提示。
- 生成或删除调速器的 LaunchAgent。关闭总开关会删除它，重新登录后也不会再启动。

## 命令行

设置应用的可执行文件同时是命令行工具，安装脚本用的就是它：

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --status
```

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --enabled off
```

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --apply windows
```

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --scale 0.25
```

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --mouse-reverse on
```

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --trackpad-reverse on
```

```bash
/Applications/UURemoteScrollSettings.app/Contents/MacOS/UURemoteScrollSettings --launch-at-login off
```

## 工作原理

1. Mos 负责鼠标滚轮：UU 远程有独立的分应用规则，关闭平滑（UU 会忽略 Mos 合成的平滑事件）并按模式决定是否反向。
2. Mos 不处理触控板事件，所以由本地编译的 `UUTrackpadFix` 监听发往 UU 窗口的连续滚动事件并缩放。
3. `UUTrackpadFix` 由用户级 LaunchAgent 保持运行，日志在 `~/Library/Logs/UUTrackpadFix.log`。开机自启开启时，LaunchAgent 放在 `~/Library/LaunchAgents`；关闭时放在应用自己的目录里，只在本次登录期间加载。
4. Mos 自身不由本项目守护；开机自启请在 Mos 偏好设置里开启“登录时启动”。
5. 所有改动都在用户级偏好设置和 LaunchAgent 内，不安装系统扩展。

## 安全措施

- 固定 Mos 版本，校验 Release 文件大小、SHA-256、Apple Gatekeeper 和开发者 Team ID；镜像线路同样必须通过这些校验。
- 替换旧版 Mos 前把旧版移到 `~/Library/Application Support/UURemoteScrollSettings/旧版应用备份/`。
- 修改 Mos 偏好设置前自动备份。
- 方法一中，`UUTrackpadFix` 和设置应用均从仓库源码在本机编译。
- 两个应用都不联网；`UUTrackpadFix` 只监听滚轮事件，不读取键盘内容、不记录鼠标位置。

## 本地构建

```bash
./build-app.command
```

构建结果（arm64 + x86_64 通用二进制，最低 macOS 12）：

```text
build/UURemoteScrollSettings.app
build/UUTrackpadFix.app
```

应用图标由 `tools/make-icon.swift` 用代码绘制。修改后运行 `xcrun swift tools/make-icon.swift UURemoteScrollSettings.app.src/AppIcon.icns` 重新生成。

仓库在 `docs/release-workflow.yml` 中提供可选的 GitHub Actions 工作流。如需启用自动构建，将该文件复制到 `.github/workflows/release.yml` 后提交。

## 卸载与恢复

1. 在设置应用中关闭**总开关**（停止调速器并删除它的 LaunchAgent）。
2. 打开 Mos 偏好设置 → 应用，删除 3 条 UU 远程规则；或从 `Mos 配置备份` 里恢复之前的配置。
3. 删除：

```text
/Applications/UUTrackpadFix.app
/Applications/UURemoteScrollSettings.app
~/Library/Application Support/UURemoteScrollSettings
~/Library/Logs/UUTrackpadFix.log
```

Mos 是独立的应用，是否保留由你决定。

## 已知限制

- UU 远程对 Mos 合成的平滑滚轮事件兼容性不稳定，因此 UU 窗口内鼠标使用原始滚轮事件。
- Magic Mouse 的滚动特征与触控板一致，会被当作触控板处理（降速、不反向）。
- `UUTrackpadFix` 使用临时签名：源码变化并重新安装后，需要重新授权辅助功能。安装脚本在源码未变化时会保留已安装的版本，避免无谓的重新授权。
- UU 或 Mos 更新后若修改进程结构，可能需要更新匹配路径。

## 贡献与反馈

欢迎提交 Issue 和 Pull Request。反馈问题时请提供：

- macOS 版本与芯片类型
- UU 远程版本
- 鼠标或触控板型号
- 当前使用的模式，以及 `--status` 的输出
- 具体表现：方向错误、速度异常或无响应

## License

本项目代码使用 [MIT License](LICENSE)。Mos 和 UU 远程分别受其自身许可证与服务条款约束；本项目不分发它们的二进制文件。
