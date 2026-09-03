# UU Remote Mac Scroll Fix

[![macOS](https://img.shields.io/badge/macOS-12%2B-black?logo=apple)](https://www.apple.com/macos/)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/FlynnAIwang/uu-remote-mac-scroll-fix)](https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix/releases)

为 UU 远程提供 Mac 主控端鼠标滚轮 / 触控板方向修复，并附带一个可一键切换远程模式的 macOS 设置应用。

> Unofficial community project. This repository is not affiliated with NetEase, UU Remote, or Mos.

## 支持的远程模式

| 模式 | Mac 本机 | UU 远程端 | 适用场景 |
|---|---|---|---|
| **Mac 控制 Windows** | 保持自然滚动手感 | 单独反向，符合 Windows 滚轮习惯 | Mac 作为主控端连接 Windows |
| **Mac 控制 Mac** | 保持自然滚动手感 | 与本机同向，保持远程 Mac 自然滚动 | Mac 作为主控端连接另一台 Mac |
| **关闭远程修正** | 保持自然滚动手感 | 停止 UU 专用方向修正和触控板调速 | 临时排查或恢复 UU 原生行为 |

设置应用会同时处理：

- macOS 系统自然滚动设置
- Mos 本机方向补偿
- UU 鼠标独立规则
- UU 触控板方向与速度
- Mos / UUTrackpadFix 后台任务状态

## 快速安装

### 方法一：下载 Release

1. 打开 [Releases](https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix/releases)。
2. 下载 `UURemoteScrollSettings-macOS.zip`。
3. 解压后将 `UURemoteScrollSettings.app` 放入 `/Applications`。
4. 首次使用前，先运行仓库中的 `setup.command` 安装基础组件。
5. 如果 macOS 阻止运行：右键应用 → **打开** → 再次点击 **打开**。

### 方法二：克隆仓库并一键安装

```bash
git clone https://github.com/FlynnAIwang/uu-remote-mac-scroll-fix.git
cd uu-remote-mac-scroll-fix
./setup.command
```

安装完成后会生成：

```text
/Applications/Mos.app
/Applications/UUTrackpadFix.app
/Applications/UURemoteScrollSettings.app
```

## 使用设置应用

1. 打开 `/Applications/UURemoteScrollSettings.app`。
2. 选择模式：
   - **Mac 控制 Windows**
   - **Mac 控制 Mac**
   - **关闭远程修正**
3. 点击对应模式卡片即可一键启用。
4. 应用会自动重启 Mos 和 UUTrackpadFix。
5. 切换到 UU 远程窗口测试滚动方向。

设置应用本身不需要辅助功能权限；`Mos` 和 `UUTrackpadFix` 首次运行时需要用户在 **系统设置 → 隐私与安全性 → 辅助功能** 中授权。

## 工作原理

1. 安装并校验 Mos 4.2.1。
2. 本机普通应用使用 Mos 丝滑滚动，并通过方向补偿保持自然滚动手感。
3. 精确匹配 UU 远程应用包、主进程和服务进程。
4. UU 鼠标使用原始滚轮事件，避免 UU 忽略 Mos 合成事件。
5. 根据当前模式切换 UU 鼠标独立反向规则。
6. 本地编译轻量辅助程序，只处理发往 UU 窗口的连续触控板事件。
7. 使用用户级 LaunchAgent 保持 Mos 和 UUTrackpadFix 登录后自动运行。
8. 设置应用只修改用户级偏好设置和 LaunchAgent，不安装系统扩展。

## 安全措施

- 固定 Mos 版本及 Release 文件大小。
- 校验 Mos Release 的 SHA-256。
- 校验 Apple Gatekeeper。
- 校验 Mos 开发者 Team ID。
- 替换旧版 Mos 前自动备份。
- 修改 Mos 偏好设置前自动备份。
- `UUTrackpadFix` 和设置应用均从仓库源码在本机编译。
- 设置应用不联网、不读取键盘内容、不记录鼠标位置。

## 自定义触控板速度

默认倍率为 `0.18`。编辑 `com.user.uuremote.trackpadfix.plist`：

```xml
<key>UU_TRACKPAD_SCALE</key>
<string>0.18</string>
```

数值越小，滚动越慢。建议范围：`0.10`–`0.35`。修改后重新运行 `setup.command`。

## 本地构建

```bash
./build-app.command
```

构建结果：

```text
build/UURemoteScrollSettings.app
```

仓库在 `docs/release-workflow.yml` 中提供可选的 GitHub Actions 工作流。由于当前推送凭证没有 `workflow` scope，如需启用自动构建，可将该文件复制到 `.github/workflows/release.yml` 后通过 GitHub 网页提交。

## 卸载与恢复

停止后台任务：

```bash
launchctl bootout "gui/$(id -u)/com.user.uuremote.mos"
launchctl bootout "gui/$(id -u)/com.user.uuremote.trackpadfix"
```

删除：

```text
~/Library/LaunchAgents/com.user.uuremote.mos.plist
~/Library/LaunchAgents/com.user.uuremote.trackpadfix.plist
/Applications/Mos.app
/Applications/UUTrackpadFix.app
/Applications/UURemoteScrollSettings.app
```

最后在 **系统设置 → 鼠标** 中恢复你原来的“自然滚动”选项。

## 已知限制

- UU 远程 4.35.0 对 Mos 合成平滑滚轮事件的兼容性不稳定，因此 UU 窗口内鼠标使用原始滚轮事件。
- `UUTrackpadFix` 首次运行需要辅助功能权限。
- UU 或 Mos 更新后若修改进程结构，可能需要更新匹配路径。
- 设置应用当前使用本机临时签名；从 GitHub 下载后如被 Gatekeeper 拦截，请右键打开。

## 贡献与反馈

欢迎提交 Issue 和 Pull Request。反馈问题时请提供：

- macOS 版本与芯片类型
- UU 远程版本
- 鼠标或触控板型号
- 当前使用的模式
- 具体表现：方向错误、速度异常或无响应

## License

本项目代码使用 [MIT License](LICENSE)。Mos 和 UU 远程分别受其自身许可证与服务条款约束；本项目不分发它们的二进制文件。
