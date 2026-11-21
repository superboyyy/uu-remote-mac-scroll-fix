import SwiftUI
import AppKit

// MARK: - 模式

enum RemoteMode: String, CaseIterable, Identifiable, Sendable {
    case windows
    case mac
    case off

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
            return "预设：UU 窗口内鼠标滚轮反向（Windows 习惯），触控板不反向并降速。"
        case .mac:
            return "预设：UU 窗口内鼠标滚轮和触控板都不反向，触控板降速。"
        case .off:
            return "停止触控板调速，UU 窗口内鼠标滚轮不反向；重新登录后仍保持关闭。"
        }
    }

    var systemImage: String {
        switch self {
        case .windows: return "desktopcomputer"
        case .mac: return "laptopcomputer"
        case .off: return "pause.circle"
        }
    }

    var usesTrackpadFix: Bool { self != .off }

    /// 该模式预设的鼠标滚轮方向：UU 窗口内是否由 Mos 反向。
    /// 只有系统开着自然滚动时，发往 Windows 的滚轮才需要翻转。
    /// 用户可以在界面上用“鼠标滚轮反向”开关覆盖这个预设。
    func wantsMouseReverse(naturalScrolling: Bool) -> Bool {
        self == .windows && naturalScrolling
    }
}

// MARK: - 状态与错误

struct StateSnapshot: Sendable {
    var naturalScrolling = true
    var mosInstalled = false
    var mosRunning = false
    var mosGlobalReverse = true
    /// nil 表示 Mos 里还没有 UU 规则。
    var uuMouseReverse: Bool?
    var trackpadInstalled = false
    var trackpadRunning = false
    var trackpadWaitingForPermission = false
    var trackpadScale = ModeEngine.defaultScale
    var trackpadReverse = false
    var launchAtLogin = true
    /// Mos 是否在系统的登录项里；nil 表示读不到。
    var mosLaunchesAtLogin: Bool?
    /// 开机自启关闭、重新登录后，上次选的模式还没启用时不为 nil。
    var pendingMode: RemoteMode?
    var mode: RemoteMode?
}

struct ApplyResult: Sendable {
    var notes: [String] = []
}

enum AppError: LocalizedError {
    case mosMissing
    case uuMissing
    case trackpadFixMissing
    case mosRulesUnreadable
    case mosDidNotQuit
    case mosDidNotInitialize
    case trackpadDidNotStart(String)
    case noActiveMode
    case commandFailed(String, String)

    var errorDescription: String? {
        switch self {
        case .mosMissing:
            return "未找到 /Applications/Mos.app。请先安装 Mos，或运行项目中的 setup.command。"
        case .uuMissing:
            return "未找到 /Applications/UURemote.app。请先安装 UU 远程。"
        case .trackpadFixMissing:
            return "未找到 /Applications/UUTrackpadFix.app。请运行项目中的 setup.command，或把它放进“应用程序”文件夹。"
        case .mosRulesUnreadable:
            return "无法解析 Mos 现有的分应用规则。为避免覆盖，本次没有做任何修改。"
        case .mosDidNotQuit:
            return "Mos 没有正常退出，本次没有修改它的配置。请手动退出 Mos 后重试。"
        case .mosDidNotInitialize:
            return "Mos 首次启动后没有生成配置。请先手动打开一次 Mos，再重试。"
        case .trackpadDidNotStart(let detail):
            return "触控板调速器没有启动成功。\(detail)"
        case .noActiveMode:
            return "请先启用“Mac 控制 Windows”或“Mac 控制 Mac”模式，再调整滚动方向。"
        case .commandFailed(let command, let detail):
            let suffix = detail.isEmpty ? "" : "：\(detail)"
            return "命令执行失败（\(command)）\(suffix)"
        }
    }
}

// MARK: - 核心逻辑（界面和命令行共用，不依赖界面）

enum ModeEngine {
    static let defaultScale = 0.18
    static let scaleRange = 0.05...1.0

    private static let mosDomain = "com.caldis.Mos" as CFString
    private static let mosBundleID = "com.caldis.Mos"
    private static let mosAppPath = "/Applications/Mos.app"
    private static let uuAppPath = "/Applications/UURemote.app"
    private static let trackpadAppPath = "/Applications/UUTrackpadFix.app"
    private static let trackpadExecutable = "/Applications/UUTrackpadFix.app/Contents/MacOS/UUTrackpadFix"
    private static let trackpadLabel = "com.user.uuremote.trackpadfix"
    private static let legacyMosLabel = "com.user.uuremote.mos"
    private static let settingsDomain = "com.user.uuremote.scrollsettings" as CFString
    private static let waitingMarker = "等待辅助功能权限"

    private static var home: String { NSHomeDirectory() }
    private static var uid: String { String(getuid()) }
    private static var launchAgentsDirectory: String { "\(home)/Library/LaunchAgents" }
    /// 开机自启开启时，LaunchAgent 放在 ~/Library/LaunchAgents，登录时由系统自动加载。
    private static var loginPlistPath: String { "\(launchAgentsDirectory)/\(trackpadLabel).plist" }
    /// 开机自启关闭时，放在应用自己的目录里，只在本次登录期间手动加载。
    private static var sessionPlistPath: String { "\(supportDirectory)/\(trackpadLabel).plist" }
    /// 当前存在的那一份（两份不会同时存在）；调速器没有配置时为 nil。
    private static var trackpadPlistPath: String? {
        [loginPlistPath, sessionPlistPath].first { FileManager.default.fileExists(atPath: $0) }
    }
    private static var supportDirectory: String {
        "\(home)/Library/Application Support/UURemoteScrollSettings"
    }
    private static var legacyMosPlistPath: String { "\(launchAgentsDirectory)/\(legacyMosLabel).plist" }
    private static var trackpadLogPath: String { "\(home)/Library/Logs/UUTrackpadFix.log" }
    private static var mosPreferencesPath: String { "\(home)/Library/Preferences/com.caldis.Mos.plist" }
    private static var backupDirectory: String { "\(supportDirectory)/Mos 配置备份" }

    // MARK: 读取状态

    static func readState() -> StateSnapshot {
        var state = StateSnapshot()
        state.naturalScrolling = naturalScrolling()
        state.mosInstalled = FileManager.default.fileExists(atPath: mosAppPath)
        state.mosRunning = !mosProcessIDs().isEmpty
        state.mosGlobalReverse = mosGlobalReverseEnabled()
        state.uuMouseReverse = (try? readMosRules()).flatMap(uuReverse(in:))
        state.trackpadInstalled = FileManager.default.isExecutableFile(atPath: trackpadExecutable)
        state.trackpadRunning = isAgentRunning(trackpadLabel)
        state.trackpadWaitingForPermission = state.trackpadRunning && trackpadIsWaitingForPermission()
        state.trackpadScale = currentScale()
        state.trackpadReverse = state.trackpadRunning && activeTrackpadReverse()
        state.launchAtLogin = launchAtLogin()
        state.mosLaunchesAtLogin = mosLaunchesAtLogin()
        if !state.launchAtLogin, !state.trackpadRunning, state.trackpadInstalled,
           state.uuMouseReverse != nil, let saved = savedMode(), saved.usesTrackpadFix {
            state.pendingMode = saved
        }
        state.mode = detectMode(state)
        return state
    }

    /// 判断当前模式。方向可以被开关覆盖，所以以用户上次选择的模式为准，
    /// 只要它和调速器的实际运行状态对得上；对不上或没有记录时按实际状态推断。
    private static func detectMode(_ state: StateSnapshot) -> RemoteMode? {
        guard let reverse = state.uuMouseReverse else { return nil }
        if let saved = savedMode(), saved.usesTrackpadFix == state.trackpadRunning { return saved }
        if state.pendingMode != nil { return nil }
        if !state.trackpadRunning { return reverse ? nil : .off }
        return reverse ? .windows : .mac
    }

    // MARK: 应用模式

    /// 点模式卡片：启用该模式，并把两个方向开关恢复为该模式的预设。
    static func apply(_ mode: RemoteMode) throws -> ApplyResult {
        try applyConfiguration(
            mode: mode,
            mouseReverse: mode.wantsMouseReverse(naturalScrolling: naturalScrolling()),
            trackpadReverse: false
        )
    }

    /// 安装脚本使用：按上次保存的模式和方向开关重新应用，不重置用户的选择。
    static func applySaved() throws -> (mode: RemoteMode, result: ApplyResult) {
        let mode = defaultMode()
        let mouseReverse = savedFlag(mouseReverseKey)
            ?? mode.wantsMouseReverse(naturalScrolling: naturalScrolling())
        let trackpadReverse = savedFlag(trackpadReverseKey) ?? false
        let result = try applyConfiguration(mode: mode, mouseReverse: mouseReverse, trackpadReverse: trackpadReverse)
        return (mode, result)
    }

    /// “鼠标滚轮反向”开关：只改 Mos 里的 UU 规则，不动调速器。
    static func setMouseReverse(_ reverse: Bool) throws -> ApplyResult {
        guard let mode = readState().mode, mode.usesTrackpadFix else { throw AppError.noActiveMode }
        try checkPrerequisites(needsTrackpadFix: false)
        var result = ApplyResult()
        try applyMouseRules(reverse: reverse, result: &result)
        saveFlag(mouseReverseKey, reverse)
        return result
    }

    /// “触控板反向”开关：只重启调速器，不动 Mos。
    static func setTrackpadReverse(_ reverse: Bool) throws {
        guard let mode = readState().mode, mode.usesTrackpadFix else { throw AppError.noActiveMode }
        try checkPrerequisites(needsTrackpadFix: true)
        try startTrackpadAgent(scale: currentScale(), reverse: reverse)
        saveFlag(trackpadReverseKey, reverse)
    }

    /// “开机自启”开关。只决定触控板调速器登录后是否自动启动；
    /// Mos 是独立的应用，它的登录启动由 Mos 自己的设置控制，这里不改。
    static func setLaunchAtLogin(_ enabled: Bool) throws {
        saveFlag(launchAtLoginKey, enabled)
        // 调速器正在用（或上次登录用过）时，按新设置把 LaunchAgent 挪到对应位置并重启。
        if isAgentLoaded(trackpadLabel) || trackpadPlistPath != nil {
            try checkPrerequisites(needsTrackpadFix: true)
            try startTrackpadAgent(scale: currentScale(), reverse: activeTrackpadReverse())
        }
    }

    /// 开机自启关闭时，重新登录后调速器不会自己启动；这里按上次的设置把它启动起来。
    /// Mos 里的鼠标规则是持久的，不需要重写。
    static func resume() throws {
        try checkPrerequisites(needsTrackpadFix: true)
        try startTrackpadAgent(scale: currentScale(), reverse: savedFlag(trackpadReverseKey) ?? false)
    }

    private static func applyConfiguration(
        mode: RemoteMode,
        mouseReverse: Bool,
        trackpadReverse: Bool
    ) throws -> ApplyResult {
        try checkPrerequisites(needsTrackpadFix: mode.usesTrackpadFix)

        // “关闭远程修正”下两个方向都不反向。
        let mouseReverse = mode.usesTrackpadFix && mouseReverse
        let trackpadReverse = mode.usesTrackpadFix && trackpadReverse

        var result = ApplyResult()
        try applyMouseRules(reverse: mouseReverse, result: &result)

        if mode.usesTrackpadFix {
            try startTrackpadAgent(scale: currentScale(), reverse: trackpadReverse)
            if trackpadIsWaitingForPermission() {
                result.notes.append("触控板调速器正在等待辅助功能授权。")
            }
        } else {
            stopTrackpadAgent()
        }

        saveMode(mode)
        saveFlag(mouseReverseKey, mouseReverse)
        saveFlag(trackpadReverseKey, trackpadReverse)
        return result
    }

    /// 先检查全部前提，任何一项不满足都不动配置。
    private static func checkPrerequisites(needsTrackpadFix: Bool) throws {
        guard FileManager.default.fileExists(atPath: mosAppPath) else { throw AppError.mosMissing }
        guard FileManager.default.fileExists(atPath: uuAppPath) else { throw AppError.uuMissing }
        if needsTrackpadFix {
            guard FileManager.default.isExecutableFile(atPath: trackpadExecutable) else {
                throw AppError.trackpadFixMissing
            }
        }
    }

    /// 把 UU 的鼠标滚轮规则写进 Mos 并重启 Mos。
    private static func applyMouseRules(reverse: Bool, result: inout ApplyResult) throws {
        // 1. 旧版本用 LaunchAgent 守护 Mos，会导致 Mos 无法退出；这里迁移掉。
        if removeLegacyMosAgent() {
            result.notes.append("已移除旧版的 Mos 守护任务；Mos 的开机自启请在 Mos 偏好设置里开启。")
        }

        // 2. Mos 从未运行过时没有配置，先让它生成默认配置，否则首次启动会把规则清空。
        try ensureMosInitialized()

        // 3. 计算要写入的内容。只替换 UU 相关规则，保留用户给其他应用配的规则。
        let existingRules = try readMosRules()
        let mergedRules = existingRules.filter { !isUURule($0) } + uuRules(reverse: reverse)
        let rulesChanged = !(existingRules as NSArray).isEqual(to: mergedRules)
        // Mos 的分应用反向只有在全局“反向”开启时才生效。
        let mustEnableGlobalReverse = reverse && !mosGlobalReverseEnabled()

        // 4. Mos 只在启动时读配置，并且改任何设置都会把内存里的旧配置写回，
        //    所以必须先退出、再写入、再启动。
        try quitMos()
        do {
            if rulesChanged || mustEnableGlobalReverse {
                backupMosPreferences()
                let data = try JSONSerialization.data(withJSONObject: mergedRules)
                setMosValue("applications", data as CFData)
                if mustEnableGlobalReverse {
                    for key in ["reverse", "reverseVertical", "reverseHorizontal"] {
                        setMosValue(key, kCFBooleanTrue)
                    }
                    result.notes.append("已开启 Mos 的全局“反向滚动”，UU 的独立反向规则依赖它。")
                }
                CFPreferencesAppSynchronize(mosDomain)
            }
        } catch {
            try? launchMos()
            throw error
        }
        try launchMos()
    }

    /// 修改触控板倍率；调速器在运行时立即重启生效。
    static func setScale(_ value: Double) throws {
        let scale = clampScale(value)
        CFPreferencesSetAppValue("trackpadScale" as CFString, scale as CFNumber, settingsDomain)
        CFPreferencesAppSynchronize(settingsDomain)
        if isAgentLoaded(trackpadLabel) {
            try startTrackpadAgent(scale: scale, reverse: activeTrackpadReverse())
        }
    }

    // MARK: 系统与 Mos 偏好设置

    private static func naturalScrolling() -> Bool {
        CFPreferencesSynchronize(kCFPreferencesAnyApplication, kCFPreferencesCurrentUser, kCFPreferencesAnyHost)
        let value = CFPreferencesCopyValue(
            "com.apple.swipescrolldirection" as CFString,
            kCFPreferencesAnyApplication,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )
        // macOS 默认开启自然滚动，键不存在时按开启处理。
        return (value as? Bool) ?? true
    }

    private static func mosValue(_ key: String) -> Any? {
        CFPreferencesAppSynchronize(mosDomain)
        return CFPreferencesCopyAppValue(key as CFString, mosDomain)
    }

    private static func setMosValue(_ key: String, _ value: CFPropertyList) {
        CFPreferencesSetAppValue(key as CFString, value, mosDomain)
    }

    private static func mosGlobalReverseEnabled() -> Bool {
        // 这三个键在 Mos 里默认都是开启。
        ["reverse", "reverseVertical", "reverseHorizontal"].allSatisfy { key in
            (mosValue(key) as? Bool) ?? true
        }
    }

    private static func readMosRules() throws -> [[String: Any]] {
        guard let raw = mosValue("applications") else { return [] }
        guard let data = raw as? Data,
              let json = try? JSONSerialization.jsonObject(with: data),
              let rules = json as? [[String: Any]] else {
            throw AppError.mosRulesUnreadable
        }
        return rules
    }

    private static func isUURule(_ rule: [String: Any]) -> Bool {
        guard let path = rule["path"] as? String else { return false }
        return path == uuAppPath || path.hasPrefix(uuAppPath + "/")
    }

    private static func uuReverse(in rules: [[String: Any]]) -> Bool? {
        for rule in rules where isUURule(rule) {
            if let scroll = rule["scroll"] as? [String: Any], let reverse = scroll["reverse"] as? Bool {
                return reverse
            }
        }
        return nil
    }

    /// UU 远程的 Mos 规则：不继承全局设置、关闭平滑（UU 会忽略 Mos 合成的平滑事件）。
    /// Mos 按应用包路径或可执行文件路径匹配，所以主进程和服务进程各写一条。
    private static func uuRules(reverse: Bool) -> [[String: Any]] {
        let targets = [
            (uuAppPath, "UU远程"),
            ("\(uuAppPath)/Contents/MacOS/UURemote", "UU远程主进程"),
            ("\(uuAppPath)/Contents/Helpers/UURemoteServer", "UU远程服务进程"),
        ]
        return targets.map { path, name in
            [
                "path": path,
                "displayName": name,
                "inherit": false,
                "scroll": [
                    "smooth": false,
                    "reverse": reverse,
                    "reverseVertical": reverse,
                    "reverseHorizontal": reverse,
                    "dash": NSNull(),
                    "toggle": NSNull(),
                    "block": NSNull(),
                    "step": 8.0,
                    "speed": 1.0,
                    "duration": 4.2,
                    "deadZone": 1.0,
                    "smoothSimTrackpad": false,
                    "smoothVertical": false,
                    "smoothHorizontal": false,
                    "durationBeforeSimTrackpadLock": NSNull(),
                ] as [String: Any],
            ]
        }
    }

    private static func backupMosPreferences() {
        let manager = FileManager.default
        guard manager.fileExists(atPath: mosPreferencesPath) else { return }
        try? manager.createDirectory(atPath: backupDirectory, withIntermediateDirectories: true)

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let target = "\(backupDirectory)/com.caldis.Mos-\(formatter.string(from: Date())).plist"
        try? manager.copyItem(atPath: mosPreferencesPath, toPath: target)

        // 只保留最近 10 份。文件名里的时间戳可以直接按字典序排序。
        let backups = ((try? manager.contentsOfDirectory(atPath: backupDirectory)) ?? [])
            .filter { $0.hasPrefix("com.caldis.Mos-") }
            .sorted()
        for name in backups.dropLast(10) {
            try? manager.removeItem(atPath: "\(backupDirectory)/\(name)")
        }
    }

    // MARK: Mos 进程

    private static func mosProcessIDs() -> [pid_t] {
        NSRunningApplication.runningApplications(withBundleIdentifier: mosBundleID)
            .map(\.processIdentifier)
            .filter { $0 > 0 && kill($0, 0) == 0 }
    }

    private static func ensureMosInitialized() throws {
        guard mosValue("optionsExist") == nil else { return }
        try launchMos()
        guard waitUntil(timeout: 15, { mosValue("optionsExist") != nil }) else {
            throw AppError.mosDidNotInitialize
        }
    }

    private static func quitMos() throws {
        let applications = NSRunningApplication.runningApplications(withBundleIdentifier: mosBundleID)
        guard !applications.isEmpty else { return }
        let pids = applications.map(\.processIdentifier)

        applications.forEach { $0.terminate() }
        if waitUntil(timeout: 5, { pids.allSatisfy { kill($0, 0) != 0 } }) { return }

        // 正常退出没反应时再强制结束。Mos 退出时不写配置，强制结束不会丢数据。
        applications.forEach { $0.forceTerminate() }
        guard waitUntil(timeout: 3, { pids.allSatisfy { kill($0, 0) != 0 } }) else {
            throw AppError.mosDidNotQuit
        }
    }

    private static func launchMos() throws {
        // -g：不把 Mos 带到前台。
        _ = try run("/usr/bin/open", ["-g", mosAppPath])
        _ = waitUntil(timeout: 5) { !mosProcessIDs().isEmpty }
    }

    /// 旧版本安装的 com.user.uuremote.mos 守护任务。存在则卸载并删除，返回是否做了清理。
    private static func removeLegacyMosAgent() -> Bool {
        let loaded = isAgentLoaded(legacyMosLabel)
        let exists = FileManager.default.fileExists(atPath: legacyMosPlistPath)
        guard loaded || exists else { return false }
        if loaded {
            _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)/\(legacyMosLabel)"])
            _ = waitUntil(timeout: 3) { !isAgentLoaded(legacyMosLabel) }
        }
        try? FileManager.default.removeItem(atPath: legacyMosPlistPath)
        return true
    }

    // MARK: 触控板调速器

    private static func clampScale(_ value: Double) -> Double {
        let clamped = min(max(value, scaleRange.lowerBound), scaleRange.upperBound)
        return (clamped * 100).rounded() / 100
    }

    private static func currentScale() -> Double {
        CFPreferencesAppSynchronize(settingsDomain)
        if let saved = CFPreferencesCopyAppValue("trackpadScale" as CFString, settingsDomain) as? Double {
            return clampScale(saved)
        }
        // 兼容旧版：倍率只写在 LaunchAgent 里。
        if let plist = trackpadPlistPath.flatMap({ NSDictionary(contentsOfFile: $0) }),
           let environment = plist["EnvironmentVariables"] as? [String: Any],
           let text = environment["UU_TRACKPAD_SCALE"] as? String,
           let value = Double(text) {
            return clampScale(value)
        }
        return defaultScale
    }

    /// 调速器当前实际使用的方向：以 LaunchAgent 里的环境变量为准。
    private static func activeTrackpadReverse() -> Bool {
        guard let plist = trackpadPlistPath.flatMap({ NSDictionary(contentsOfFile: $0) }),
              let environment = plist["EnvironmentVariables"] as? [String: Any] else {
            return false
        }
        return environment["UU_TRACKPAD_REVERSE"] as? String == "1"
    }

    private static func startTrackpadAgent(scale: Double, reverse: Bool) throws {
        let manager = FileManager.default
        try manager.createDirectory(atPath: launchAgentsDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(atPath: supportDirectory, withIntermediateDirectories: true)
        try manager.createDirectory(atPath: "\(home)/Library/Logs", withIntermediateDirectories: true)

        unloadTrackpadAgent()

        // 开机自启决定 LaunchAgent 放在哪里；另一个位置的旧文件要删掉，否则设置不生效。
        let plistPath = launchAtLogin() ? loginPlistPath : sessionPlistPath
        for stale in [loginPlistPath, sessionPlistPath] where stale != plistPath {
            try? manager.removeItem(atPath: stale)
        }

        // 由应用自己生成 LaunchAgent，不再依赖安装脚本拷贝模板。
        let plist: [String: Any] = [
            "Label": trackpadLabel,
            "ProgramArguments": [trackpadExecutable],
            "EnvironmentVariables": [
                "UU_TRACKPAD_SCALE": String(format: "%.2f", clampScale(scale)),
                // 默认方向与本机一致；打开“触控板反向”开关后在 UU 窗口内翻转。
                "UU_TRACKPAD_REVERSE": reverse ? "1" : "0",
            ],
            "RunAtLoad": true,
            "KeepAlive": true,
            "ProcessType": "Interactive",
            "StandardOutPath": trackpadLogPath,
            "StandardErrorPath": trackpadLogPath,
        ]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: URL(fileURLWithPath: plistPath), options: .atomic)

        // 清空旧日志，后面靠最新一行判断是否在等待授权。
        manager.createFile(atPath: trackpadLogPath, contents: Data())

        // 之前若被 launchctl disable 过，bootstrap 会失败。
        _ = try? run("/bin/launchctl", ["enable", "gui/\(uid)/\(trackpadLabel)"])

        var lastError: Error?
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 0.5) }
            do {
                _ = try run("/bin/launchctl", ["bootstrap", "gui/\(uid)", plistPath])
                lastError = nil
                break
            } catch {
                lastError = error
            }
        }
        if let lastError {
            throw AppError.trackpadDidNotStart(lastError.localizedDescription)
        }
        guard waitUntil(timeout: 5, { isAgentRunning(trackpadLabel) }) else {
            throw AppError.trackpadDidNotStart("后台任务已加载但进程没有运行，可查看 ~/Library/Logs/UUTrackpadFix.log。")
        }
        // 给进程一点时间写出第一行日志（已启动 / 等待授权）。
        _ = waitUntil(timeout: 2) { !trackpadLogTail().isEmpty }
    }

    private static func unloadTrackpadAgent() {
        guard isAgentLoaded(trackpadLabel) else { return }
        _ = try? run("/bin/launchctl", ["bootout", "gui/\(uid)/\(trackpadLabel)"])
        _ = waitUntil(timeout: 3) { !isAgentLoaded(trackpadLabel) }
    }

    /// 停止调速器并删除 LaunchAgent。只 bootout 不删文件的话，下次登录又会自动启动。
    private static func stopTrackpadAgent() {
        unloadTrackpadAgent()
        for path in [loginPlistPath, sessionPlistPath] {
            try? FileManager.default.removeItem(atPath: path)
        }
    }

    private static func trackpadLogTail() -> String {
        guard let handle = FileHandle(forReadingAtPath: trackpadLogPath) else { return "" }
        defer { try? handle.close() }
        let size = (try? handle.seekToEnd()) ?? 0
        try? handle.seek(toOffset: size > 2048 ? size - 2048 : 0)
        let data = (try? handle.readToEnd()) ?? Data()
        return String(decoding: data, as: UTF8.self)
    }

    private static func trackpadIsWaitingForPermission() -> Bool {
        let lastLine = trackpadLogTail()
            .split(separator: "\n")
            .last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        return lastLine?.contains(waitingMarker) ?? false
    }

    // MARK: 用户选择的模式和方向开关

    private static let mouseReverseKey = "mouseReverse"
    private static let trackpadReverseKey = "trackpadReverse"
    private static let launchAtLoginKey = "launchAtLogin"

    /// 默认开启：启用模式后，重新登录也自动生效。
    private static func launchAtLogin() -> Bool {
        savedFlag(launchAtLoginKey) ?? true
    }

    /// Mos 是否在系统“登录时打开”列表里。Mos 自己的“登录时启动”选项用的也是这份列表。
    /// 这里只读不写。
    private static func mosLaunchesAtLogin() -> Bool? {
        guard let list = LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?
                .takeRetainedValue(),
              let items = LSSharedFileListCopySnapshot(list, nil)?.takeRetainedValue() as? [LSSharedFileListItem] else {
            return nil
        }
        return items.contains { item in
            let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?
            return url?.standardizedFileURL.path == mosAppPath
        }
    }

    private static func savedFlag(_ key: String) -> Bool? {
        CFPreferencesAppSynchronize(settingsDomain)
        return CFPreferencesCopyAppValue(key as CFString, settingsDomain) as? Bool
    }

    private static func saveFlag(_ key: String, _ value: Bool) {
        CFPreferencesSetAppValue(key as CFString, value ? kCFBooleanTrue : kCFBooleanFalse, settingsDomain)
        CFPreferencesAppSynchronize(settingsDomain)
    }

    private static func savedMode() -> RemoteMode? {
        CFPreferencesAppSynchronize(settingsDomain)
        guard let raw = CFPreferencesCopyAppValue("selectedMode" as CFString, settingsDomain) as? String else {
            return nil
        }
        return RemoteMode(rawValue: raw)
    }

    private static func saveMode(_ mode: RemoteMode) {
        CFPreferencesSetAppValue("selectedMode" as CFString, mode.rawValue as CFString, settingsDomain)
        CFPreferencesAppSynchronize(settingsDomain)
    }

    /// 沿用上次选择的模式；没有记录时按现有 UU 规则推断，都没有则用 Windows 模式。
    private static func defaultMode() -> RemoteMode {
        if let saved = savedMode() { return saved }
        if let reverse = (try? readMosRules()).flatMap(uuReverse(in:)) {
            return reverse ? .windows : .mac
        }
        return .windows
    }

    // MARK: launchctl 与子进程

    private static func isAgentLoaded(_ label: String) -> Bool {
        (try? run("/bin/launchctl", ["print", "gui/\(uid)/\(label)"])) != nil
    }

    private static func isAgentRunning(_ label: String) -> Bool {
        guard let output = try? run("/bin/launchctl", ["print", "gui/\(uid)/\(label)"]) else { return false }
        return output.contains("state = running")
    }

    private static func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if condition() { return true }
            if Date() >= deadline { return false }
            Thread.sleep(forTimeInterval: 0.1)
        }
    }

    @discardableResult
    private static func run(_ path: String, _ arguments: [String]) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments

        let output = Pipe()
        let errors = Pipe()
        process.standardOutput = output
        process.standardError = errors

        try process.run()
        // 这里调用的命令输出都很短，按顺序读完两个管道即可。
        let outputData = output.fileHandleForReading.readDataToEndOfFile()
        let errorData = errors.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let detail = String(decoding: errorData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let command = ([URL(fileURLWithPath: path).lastPathComponent] + arguments.prefix(1)).joined(separator: " ")
            throw AppError.commandFailed(command, detail)
        }
        return String(decoding: outputData, as: UTF8.self)
    }
}

// MARK: - 命令行入口（安装脚本和排查问题时使用）

enum CommandLineInterface {
    static let usage = """
    用法：
      UURemoteScrollSettings --status
      UURemoteScrollSettings --apply <windows|mac|off|default>
      UURemoteScrollSettings --scale <0.05–1.0>
      UURemoteScrollSettings --mouse-reverse <on|off>
      UURemoteScrollSettings --trackpad-reverse <on|off>
      UURemoteScrollSettings --launch-at-login <on|off>
      UURemoteScrollSettings --resume
    """

    /// 返回 nil 表示没有命令行参数，应启动图形界面。
    static func run(_ arguments: [String]) -> Int32? {
        guard let command = arguments.first else { return nil }
        switch command {
        case "--status":
            printState(ModeEngine.readState())
            return 0
        case "--apply":
            guard arguments.count == 2 else { return fail(usage) }
            do {
                let mode: RemoteMode
                let result: ApplyResult
                if arguments[1] == "default" {
                    (mode, result) = try ModeEngine.applySaved()
                } else if let parsed = RemoteMode(rawValue: arguments[1]) {
                    mode = parsed
                    result = try ModeEngine.apply(parsed)
                } else {
                    return fail(usage)
                }
                print("已启用：\(mode.title)")
                result.notes.forEach { print("提示：\($0)") }
                printState(ModeEngine.readState())
                return 0
            } catch {
                return fail("应用失败：\(error.localizedDescription)")
            }
        case "--scale":
            guard arguments.count == 2, let value = Double(arguments[1]) else { return fail(usage) }
            do {
                try ModeEngine.setScale(value)
                printState(ModeEngine.readState())
                return 0
            } catch {
                return fail("设置失败：\(error.localizedDescription)")
            }
        case "--resume":
            do {
                try ModeEngine.resume()
                printState(ModeEngine.readState())
                return 0
            } catch {
                return fail("启用失败：\(error.localizedDescription)")
            }
        case "--mouse-reverse", "--trackpad-reverse", "--launch-at-login":
            guard arguments.count == 2, ["on", "off"].contains(arguments[1]) else { return fail(usage) }
            let reverse = arguments[1] == "on"
            do {
                if command == "--mouse-reverse" {
                    try ModeEngine.setMouseReverse(reverse).notes.forEach { print("提示：\($0)") }
                } else if command == "--launch-at-login" {
                    try ModeEngine.setLaunchAtLogin(reverse)
                } else {
                    try ModeEngine.setTrackpadReverse(reverse)
                }
                printState(ModeEngine.readState())
                return 0
            } catch {
                return fail("设置失败：\(error.localizedDescription)")
            }
        case "--help", "-h":
            print(usage)
            return 0
        default:
            // 系统启动应用时可能附带自己的参数，一律交给图形界面。
            return nil
        }
    }

    private static func fail(_ message: String) -> Int32 {
        FileHandle.standardError.write(Data((message + "\n").utf8))
        return 1
    }

    private static func printState(_ state: StateSnapshot) {
        func text(_ value: Bool) -> String { value ? "yes" : "no" }
        print("mode=\(state.mode?.rawValue ?? "unknown")")
        print("natural_scrolling=\(text(state.naturalScrolling))")
        print("mos_installed=\(text(state.mosInstalled))")
        print("mos_running=\(text(state.mosRunning))")
        print("mos_global_reverse=\(text(state.mosGlobalReverse))")
        print("uu_mouse_reverse=\(state.uuMouseReverse.map(text) ?? "unset")")
        print("trackpad_installed=\(text(state.trackpadInstalled))")
        print("trackpad_running=\(text(state.trackpadRunning))")
        print("trackpad_waiting_for_permission=\(text(state.trackpadWaitingForPermission))")
        print("trackpad_scale=\(String(format: "%.2f", state.trackpadScale))")
        print("trackpad_reverse=\(text(state.trackpadReverse))")
        print("launch_at_login=\(text(state.launchAtLogin))")
        print("mos_launches_at_login=\(state.mosLaunchesAtLogin.map(text) ?? "unknown")")
        print("pending_mode=\(state.pendingMode?.rawValue ?? "none")")
    }
}

// MARK: - 界面

private func runInBackground<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        DispatchQueue.global(qos: .userInitiated).async {
            continuation.resume(with: Result { try work() })
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    @Published var state = StateSnapshot()
    @Published var scale = ModeEngine.defaultScale
    @Published var busy = false
    @Published var message = "请选择要启用的远程模式。"
    @Published var errorMessage: String?
    @Published var notes: [String] = []

    init() {
        refresh()
    }

    func refresh() {
        guard !busy else { return }
        busy = true
        Task {
            await reloadState()
            busy = false
        }
    }

    func apply(_ mode: RemoteMode) {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        notes = []
        message = "正在应用：\(mode.title)…"
        Task {
            do {
                let result = try await runInBackground { try ModeEngine.apply(mode) }
                notes = result.notes
                message = "已启用：\(mode.title)"
            } catch {
                errorMessage = "应用失败：\(error.localizedDescription)"
                message = "应用失败，请查看下方提示。"
            }
            await reloadState()
            busy = false
        }
    }

    func commitScale() {
        guard !busy, abs(scale - state.trackpadScale) > 0.001 else { return }
        busy = true
        errorMessage = nil
        let value = scale
        Task {
            do {
                try await runInBackground { try ModeEngine.setScale(value) }
                message = "触控板倍率已设为 \(String(format: "%.2f", value))"
            } catch {
                errorMessage = "设置失败：\(error.localizedDescription)"
            }
            await reloadState()
            busy = false
        }
    }

    func setMouseReverse(_ reverse: Bool) {
        guard !busy, reverse != (state.uuMouseReverse ?? false) else { return }
        busy = true
        errorMessage = nil
        notes = []
        message = "正在切换鼠标滚轮方向…"
        Task {
            do {
                let result = try await runInBackground { try ModeEngine.setMouseReverse(reverse) }
                notes = result.notes
                message = reverse ? "UU 窗口内鼠标滚轮已反向" : "UU 窗口内鼠标滚轮已恢复不反向"
            } catch {
                errorMessage = "设置失败：\(error.localizedDescription)"
                message = "设置失败，请查看下方提示。"
            }
            await reloadState()
            busy = false
        }
    }

    func setTrackpadReverse(_ reverse: Bool) {
        guard !busy, reverse != state.trackpadReverse else { return }
        busy = true
        errorMessage = nil
        notes = []
        Task {
            do {
                try await runInBackground { try ModeEngine.setTrackpadReverse(reverse) }
                message = reverse ? "UU 窗口内触控板已反向" : "UU 窗口内触控板已恢复不反向"
            } catch {
                errorMessage = "设置失败：\(error.localizedDescription)"
                message = "设置失败，请查看下方提示。"
            }
            await reloadState()
            busy = false
        }
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        guard !busy, enabled != state.launchAtLogin else { return }
        busy = true
        errorMessage = nil
        notes = []
        Task {
            do {
                try await runInBackground { try ModeEngine.setLaunchAtLogin(enabled) }
                message = enabled ? "已开启开机自启" : "已关闭开机自启"
            } catch {
                errorMessage = "设置失败：\(error.localizedDescription)"
                message = "设置失败，请查看下方提示。"
            }
            await reloadState()
            busy = false
        }
    }

    func resume() {
        guard !busy else { return }
        busy = true
        errorMessage = nil
        notes = []
        message = "正在启用…"
        Task {
            do {
                try await runInBackground { try ModeEngine.resume() }
                message = "已启用"
            } catch {
                errorMessage = "启用失败：\(error.localizedDescription)"
                message = "启用失败，请查看下方提示。"
            }
            await reloadState()
            busy = false
        }
    }

    func openMos() {
        // Mos 已在运行时再次打开，它会显示自己的偏好设置窗口。
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Mos.app"))
    }

    func openUU() {
        NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/UURemote.app"))
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func reloadState() async {
        if let latest = try? await runInBackground({ ModeEngine.readState() }) {
            state = latest
            scale = latest.trackpadScale
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
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(good ? Color.primary : Color.orange)
        }
        .padding(.vertical, 2)
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

                    if let pending = model.state.pendingMode {
                        resumeNotice(pending)
                    }

                    if model.state.trackpadWaitingForPermission {
                        permissionNotice
                    }

                    if let error = model.errorMessage {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                            .padding(12)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                    }

                    ForEach(model.notes, id: \.self) { note in
                        Label(note, systemImage: "info.circle")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }

                    directionBox
                    scaleBox
                    launchBox
                    statusBox

                    HStack {
                        Button {
                            model.refresh()
                        } label: {
                            Label("刷新状态", systemImage: "arrow.clockwise")
                        }

                        Button {
                            model.openUU()
                        } label: {
                            Label("打开 UU 远程", systemImage: "arrow.up.forward.app")
                        }

                        Spacer()
                    }
                    .disabled(model.busy)
                }
                .padding(20)
            }
        }
        .frame(minWidth: 640, idealWidth: 720, minHeight: 560, idealHeight: 800)
        // 用户去系统设置授权后切回来，自动刷新状态。
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refresh()
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            Image(systemName: "computermouse")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(.blue)
                .frame(width: 56, height: 56)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))

            VStack(alignment: .leading, spacing: 3) {
                Text("UU远程滚动助手")
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
                let active = model.state.mode == mode
                Button {
                    model.apply(mode)
                } label: {
                    HStack(spacing: 14) {
                        Image(systemName: mode.systemImage)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.blue)
                            .frame(width: 42, height: 42)
                            .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

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

                        if active {
                            Label("已启用", systemImage: "checkmark.circle.fill")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.green)
                        }
                    }
                    .padding(15)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14)
                            .strokeBorder(active ? Color.green : Color.primary.opacity(0.08), lineWidth: active ? 1.5 : 1)
                    }
                    .contentShape(RoundedRectangle(cornerRadius: 14))
                }
                .buttonStyle(.plain)
                .disabled(model.busy)
            }
        }
    }

    private var permissionNotice: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text("触控板调速器还没有辅助功能权限")
                    .font(.system(size: 13, weight: .semibold))
                Text("请在“系统设置 → 隐私与安全性 → 辅助功能”里打开“UU远程触控板调速器”。授权前触控板速度不会被调整。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("打开辅助功能设置") {
                    model.openAccessibilitySettings()
                }
            }
            Spacer()
        }
        .padding(12)
        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func resumeNotice(_ mode: RemoteMode) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "power")
                .foregroundStyle(.blue)
            VStack(alignment: .leading, spacing: 6) {
                Text("本次登录还没有启用远程修正")
                    .font(.system(size: 13, weight: .semibold))
                Text("开机自启已关闭，所以触控板调速器没有自动启动。上次使用的是“\(mode.title)”。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Button("立即启用") {
                    model.resume()
                }
                .disabled(model.busy)
            }
            Spacer()
        }
        .padding(12)
        .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }

    private var launchBox: some View {
        let state = model.state
        return GroupBox("开机自启") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { model.state.launchAtLogin },
                    set: { model.setLaunchAtLogin($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("登录后自动启用远程修正")
                            .font(.system(size: 13, weight: .medium))
                        Text("开启：登录后触控板调速器自动启动。关闭：每次登录后需要打开本应用点“立即启用”。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .toggleStyle(.switch)

                if state.launchAtLogin && state.mosLaunchesAtLogin == false {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Mos 没有设置登录时启动，登录后鼠标滚轮规则不会生效。请在 Mos 偏好设置 → 通用 中勾选“登录时启动”。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("打开 Mos 设置") {
                            model.openMos()
                        }
                    }
                }
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.busy)
    }

    private var directionBox: some View {
        let active = model.state.mode?.usesTrackpadFix == true
        return GroupBox("UU 窗口内滚动方向") {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { model.state.uuMouseReverse ?? false },
                    set: { model.setMouseReverse($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("鼠标滚轮反向")
                            .font(.system(size: 13, weight: .medium))
                        Text("由 Mos 处理，切换时会重启 Mos。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Divider()

                Toggle(isOn: Binding(
                    get: { model.state.trackpadReverse },
                    set: { model.setTrackpadReverse($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("触控板反向")
                            .font(.system(size: 13, weight: .medium))
                        Text("由触控板调速器处理。Magic Mouse 的滚动也按触控板处理。")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                Text(active
                     ? "只影响 UU 窗口，本机其他应用不变。点模式卡片会把这两个开关恢复为该模式的预设。"
                     : "启用“Mac 控制 Windows”或“Mac 控制 Mac”后才能调整方向。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.busy || !active)
    }

    private var scaleBox: some View {
        GroupBox("UU 触控板速度") {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 12) {
                    Text("慢")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Slider(value: $model.scale, in: ModeEngine.scaleRange) { editing in
                        if !editing { model.commitScale() }
                    }
                    Text("快")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Text(String(format: "×%.2f", model.scale))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .frame(width: 52, alignment: .trailing)
                }
                Text("只影响 UU 窗口内的触控板滚动。默认 ×0.18，松开滑块后立即生效。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .disabled(model.busy)
    }

    private var statusBox: some View {
        let state = model.state
        return GroupBox("当前状态") {
            VStack(alignment: .leading, spacing: 8) {
                StatusRow(
                    title: "当前模式",
                    value: state.mode?.title
                        ?? (state.pendingMode != nil ? "本次登录未启用"
                            : (state.uuMouseReverse == nil ? "尚未配置" : "自定义 / 未识别")),
                    good: state.mode != nil
                )
                StatusRow(
                    title: "系统自然滚动",
                    value: state.naturalScrolling ? "开启" : "关闭",
                    good: true
                )
                StatusRow(
                    title: "Mos",
                    value: !state.mosInstalled ? "未安装" : (state.mosRunning ? "运行中" : "未运行"),
                    good: state.mosRunning
                )
                StatusRow(
                    title: "Mos 全局反向",
                    value: state.mosGlobalReverse ? "开启" : "关闭",
                    good: state.mosGlobalReverse || state.uuMouseReverse != true
                )
                StatusRow(
                    title: "UU 窗口内鼠标滚轮",
                    value: state.uuMouseReverse.map { $0 ? "反向" : "不反向" } ?? "未配置",
                    good: state.uuMouseReverse != nil
                )
                StatusRow(
                    title: "UU 窗口内触控板",
                    value: state.trackpadRunning ? (state.trackpadReverse ? "反向" : "不反向") : "未处理",
                    good: true
                )
                StatusRow(
                    title: "开机自启",
                    value: state.launchAtLogin ? "开启" : "关闭",
                    good: !state.launchAtLogin || state.mosLaunchesAtLogin != false
                )
                StatusRow(
                    title: "触控板调速器",
                    value: trackpadStatus(state),
                    good: state.trackpadInstalled && !state.trackpadWaitingForPermission
                )
            }
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func trackpadStatus(_ state: StateSnapshot) -> String {
        if !state.trackpadInstalled { return "未安装" }
        if state.trackpadWaitingForPermission { return "等待辅助功能授权" }
        if state.trackpadRunning { return String(format: "运行中（×%.2f）", state.trackpadScale) }
        return "已停止"
    }
}

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

@main
enum Main {
    static func main() {
        if let status = CommandLineInterface.run(Array(CommandLine.arguments.dropFirst())) {
            exit(status)
        }
        UURemoteScrollSettingsApp.main()
    }
}
