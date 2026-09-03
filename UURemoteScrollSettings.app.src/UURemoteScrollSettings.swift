import SwiftUI
import AppKit

enum RemoteMode: String, CaseIterable, Identifiable {
    case windows = "windows"
    case mac = "mac"
    case off = "off"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .windows: return "Mac 控制 Windows"
        case .mac: return "Mac 控制 Mac"
        case .off: return "关闭远程修正"
        }
    }

    var subtitle: String {
        switch self {
        case .windows:
            return "本机保持自然滚动；Windows 远程桌面使用 Windows 习惯的反向滚动。"
        case .mac:
            return "本机保持自然滚动；Mac 远程桌面与本地保持同向自然滚动。"
        case .off:
            return "保留本机自然滚动；停止 UU 远程专用方向修正和触控板调速。"
        }
    }

    var systemImage: String {
        switch self {
        case .windows: return "desktopcomputer.and.arrow.down"
        case .mac: return "laptopcomputer.and.arrow.down"
        case .off: return "pause.circle"
        }
    }
}

struct StatusRow: View {
    let title: String
    let value: String
    let good: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(good ? Color.primary : Color.orange)
        }
        .padding(.vertical, 2)
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var currentMode: RemoteMode?
    @Published var naturalScrolling = false
    @Published var localReverse = false
    @Published var remoteReverse = false
    @Published var trackpadReverse = false
    @Published var trackpadRunning = false
    @Published var mosRunning = false
    @Published var busy = false
    @Published var message = "请选择要启用的远程模式。"
    @Published var errorMessage: String?

    private let mosDomain = "com.caldis.Mos"
    private let mosAgent = "com.user.uuremote.mos"
    private let trackpadAgent = "com.user.uuremote.trackpadfix"
    private nonisolated var uid: String { String(getuid()) }

    private nonisolated var home: String {
        NSHomeDirectory()
    }

    private nonisolated var trackpadPlist: String {
        "\(home)/Library/LaunchAgents/com.user.uuremote.trackpadfix.plist"
    }

    init() {
        refresh()
    }

    func refresh() {
        busy = true
        errorMessage = nil
        Task {
            let state = await readState()
            naturalScrolling = state.natural
            localReverse = state.localReverse
            remoteReverse = state.remoteReverse
            trackpadReverse = state.trackpadReverse
            trackpadRunning = state.trackpadRunning
            mosRunning = state.mosRunning
            currentMode = state.mode
            busy = false
        }
    }

    func apply(_ mode: RemoteMode) {
        busy = true
        errorMessage = nil
        message = "正在应用：\(mode.title)…"
        Task {
            do {
                try await applyMode(mode)
                message = "已启用：\(mode.title)"
                refresh()
            } catch {
                errorMessage = "应用失败：\(error.localizedDescription)"
                message = "应用失败，请检查下方状态。"
                busy = false
            }
        }
    }

    func openUU() {
        NSWorkspace.shared.openApplication(
            at: URL(fileURLWithPath: "/Applications/UURemote.app"),
            configuration: NSWorkspace.OpenConfiguration()
        )
    }

    private struct StateSnapshot {
        var natural: Bool
        var localReverse: Bool
        var remoteReverse: Bool
        var trackpadReverse: Bool
        var trackpadRunning: Bool
        var mosRunning: Bool
        var mode: RemoteMode?
    }

    private nonisolated func readState() async -> StateSnapshot {
        let natural = (try? readDefaultsBool(domain: "NSGlobalDomain", key: "com.apple.swipescrolldirection")) ?? false
        let localReverse = (try? readDefaultsBool(domain: mosDomain, key: "reverse")) ?? false
        let remoteReverse = (try? readRemoteReverse()) ?? false
        let trackpadReverse = (try? readTrackpadReverse()) ?? false
        let trackpadRunning = (try? readAgentRunning(label: trackpadAgent)) ?? false
        let mosRunning = (try? readAgentRunning(label: mosAgent)) ?? false

        let mode: RemoteMode?
        if remoteReverse && trackpadReverse && trackpadRunning {
            mode = .windows
        } else if !remoteReverse && !trackpadReverse && trackpadRunning {
            mode = .mac
        } else if !trackpadRunning {
            mode = .off
        } else {
            mode = nil
        }

        return StateSnapshot(
            natural: natural,
            localReverse: localReverse,
            remoteReverse: remoteReverse,
            trackpadReverse: trackpadReverse,
            trackpadRunning: trackpadRunning,
            mosRunning: mosRunning,
            mode: mode
        )
    }

    private nonisolated func applyMode(_ mode: RemoteMode) async throws {
        guard FileManager.default.fileExists(atPath: "/Applications/Mos.app") else {
            throw AppError.mosMissing
        }
        guard FileManager.default.fileExists(atPath: "/Applications/UURemote.app") else {
            throw AppError.uuMissing
        }

        // 本机始终保留自然滚动，并通过 Mos 做本机方向补偿。
        try runDefaults(domain: "NSGlobalDomain", key: "com.apple.swipescrolldirection", value: "true")
        try runDefaults(domain: mosDomain, key: "reverse", value: "true")
        try runDefaults(domain: mosDomain, key: "reverseVertical", value: "true")
        try runDefaults(domain: mosDomain, key: "reverseHorizontal", value: "true")

        // 普通应用保持 Mos 丝滑滚动。
        try runDefaults(domain: mosDomain, key: "smooth", value: "true")
        try runDefaults(domain: mosDomain, key: "smoothVertical", value: "true")
        try runDefaults(domain: mosDomain, key: "smoothHorizontal", value: "true")

        let resourceName = mode == .windows ? "uuremote-mos-rules-windows" : "uuremote-mos-rules-mac"
        guard let resource = Bundle.main.url(forResource: resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: resource) else {
            throw AppError.rulesMissing
        }

        let hex = data.map { String(format: "%02x", $0) }.joined()
        _ = try runCommand("/usr/bin/defaults", ["write", mosDomain, "applications", "-data", hex])

        try restartAgent(label: mosAgent, plistPath: "\(home)/Library/LaunchAgents/\(mosAgent).plist")

        switch mode {
        case .windows, .mac:
            guard FileManager.default.fileExists(atPath: "/Applications/UUTrackpadFix.app") else {
                throw AppError.trackpadFixMissing
            }
            let reverse = mode == .windows ? "1" : "0"
            _ = try runCommand("/usr/libexec/PlistBuddy", ["-c", "Set :EnvironmentVariables:UU_TRACKPAD_REVERSE \(reverse)", trackpadPlist])
            try restartAgent(label: trackpadAgent, plistPath: trackpadPlist)
        case .off:
            stopAgent(label: trackpadAgent)
        }
    }

    private nonisolated func readDefaultsBool(domain: String, key: String) throws -> Bool {
        let output = try runCommand("/usr/bin/defaults", ["read", domain, key])
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return output == "1" || output == "true" || output == "yes"
    }

    private nonisolated func runDefaults(domain: String, key: String, value: String) throws {
        _ = try runCommand("/usr/bin/defaults", ["write", domain, key, "-bool", value])
    }

    private nonisolated func readRemoteReverse() throws -> Bool {
        let plist = "\(home)/Library/Preferences/com.caldis.Mos.plist"
        let base64 = try runCommand(
            "/usr/bin/plutil",
            ["-extract", "applications", "raw", "-o", "-", plist]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let encoded = Data(base64Encoded: base64),
              let json = try? JSONSerialization.jsonObject(with: encoded),
              let items = json as? [[String: Any]] else {
            return false
        }

        for item in items {
            guard let path = item["path"] as? String,
                  path.contains("/UURemote.app"),
                  let scroll = item["scroll"] as? [String: Any] else { continue }
            if let reverse = scroll["reverse"] as? Bool {
                return reverse
            }
        }
        return false
    }

    private nonisolated func readTrackpadReverse() throws -> Bool {
        guard FileManager.default.fileExists(atPath: trackpadPlist) else { return false }
        let output = try runCommand(
            "/usr/bin/plutil",
            ["-extract", "EnvironmentVariables.UU_TRACKPAD_REVERSE", "raw", "-o", "-", trackpadPlist]
        )
        .trimmingCharacters(in: .whitespacesAndNewlines)
        return output == "1" || output.lowercased() == "true"
    }

    private nonisolated func readAgentRunning(label: String) throws -> Bool {
        let output = try runCommand("/bin/launchctl", ["print", "gui/\(uid)/\(label)"])
        return output.contains("state = running")
    }

    private nonisolated func restartAgent(label: String, plistPath: String) throws {
        stopAgent(label: label)

        var bootstrapError: Error?
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 0.5)
            do {
                _ = try runCommand("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
                bootstrapError = nil
                break
            } catch {
                bootstrapError = error
            }
        }

        if let bootstrapError {
            throw bootstrapError
        }

        _ = try runCommand("/bin/launchctl", ["kickstart", "-k", "gui/\(uid)/\(label)"])
    }

    private nonisolated func stopAgent(label: String) {
        _ = try? runCommand("/bin/launchctl", ["bootout", "gui/\(uid)/\(label)"])
    }

    private nonisolated func runCommand(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()

        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw AppError.commandFailed(path)
        }

        return String(data: data, encoding: .utf8) ?? ""
    }
}

enum AppError: LocalizedError {
    case mosMissing
    case uuMissing
    case trackpadFixMissing
    case rulesMissing
    case commandFailed(String)

    var errorDescription: String? {
        switch self {
        case .mosMissing:
            return "未找到 /Applications/Mos.app。请先运行项目中的一键配置脚本。"
        case .uuMissing:
            return "未找到 /Applications/UURemote.app。请先安装 UU 远程。"
        case .trackpadFixMissing:
            return "未找到 /Applications/UUTrackpadFix.app。请先运行项目中的一键配置脚本。"
        case .rulesMissing:
            return "应用资源中缺少 UU 远程规则文件。"
        case .commandFailed(let command):
            return "命令执行失败：\(command)"
        }
    }
}

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack(spacing: 0) {
            header

            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    modeCards

                    GroupBox("当前状态") {
                        VStack(alignment: .leading, spacing: 8) {
                            StatusRow(title: "当前模式", value: model.currentMode?.title ?? "自定义 / 未识别", good: model.currentMode != nil)
                            StatusRow(title: "本机自然滚动", value: model.naturalScrolling ? "开启" : "关闭", good: model.naturalScrolling)
                            StatusRow(title: "本机方向补偿", value: model.localReverse ? "开启" : "关闭", good: model.localReverse)
                            StatusRow(title: "UU 鼠标远程反向", value: model.remoteReverse ? "开启" : "关闭", good: true)
                            StatusRow(title: "UU 触控板远程反向", value: model.trackpadReverse ? "开启" : "关闭", good: true)
                            StatusRow(title: "Mos 后台", value: model.mosRunning ? "运行中" : "未运行", good: model.mosRunning)
                            StatusRow(title: "触控板调速器", value: model.trackpadRunning ? "运行中" : "已停止", good: true)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(12)
                            .background(.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    HStack {
                        Button {
                            model.refresh()
                        } label: {
                            Label("刷新状态", systemImage: "arrow.clockwise")
                        }
                        .disabled(model.busy)

                        Button {
                            model.openUU()
                        } label: {
                            Label("打开 UU 远程", systemImage: "arrow.up.forward.app")
                        }
                        .disabled(model.busy)

                        Spacer()
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 720, height: 680)
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "magic.mouse")
                .font(.system(size: 34, weight: .semibold))
                .foregroundStyle(.blue.gradient)
                .frame(width: 56, height: 56)
                .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 3) {
                Text("UU 远程鼠标滚动设置")
                    .font(.system(size: 21, weight: .bold))
                Text(model.message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            ProgressView()
                .opacity(model.busy ? 1 : 0)
        }
        .padding(20)
        .background(.bar)
    }

    private var modeCards: some View {
        VStack(spacing: 12) {
            ForEach(RemoteMode.allCases) { mode in
                Button {
                    model.apply(mode)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 24, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 42, height: 42)
                            .background(.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(mode.title)
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.primary)
                            Text(mode.subtitle)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()

                        if model.currentMode == mode {
                            Label("已启用", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        if model.currentMode == mode {
                            RoundedRectangle(cornerRadius: 14)
                                .strokeBorder(Color.green, lineWidth: 1.5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }
        }
    }
}

@main
struct UURemoteScrollSettingsApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.automatic)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
