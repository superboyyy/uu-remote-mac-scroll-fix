import Cocoa
import ApplicationServices

private let targetBundleIdentifier = "com.netease.uuremote"
private let configuredScale: Double = {
    guard let value = ProcessInfo.processInfo.environment["UU_TRACKPAD_SCALE"],
          let number = Double(value) else { return 0.18 }
    return min(max(number, 0.05), 1.0)
}()
// 默认不反转方向；只有显式设置 UU_TRACKPAD_REVERSE=1 时才反转。
private let shouldReverse = ProcessInfo.processInfo.environment["UU_TRACKPAD_REVERSE"] == "1"
private var eventScale: Double { shouldReverse ? -configuredScale : configuredScale }

// 事件监听句柄。回调里需要用它在监听被系统停用后重新启用。
private var eventTap: CFMachPort?

// 进程是否属于 UU 远程的判断结果只缓存几秒，避免 PID 被其他进程复用后误判。
private struct TargetCacheEntry {
    let matched: Bool
    let checkedAt: CFAbsoluteTime
}
private let targetCacheLifetime: CFAbsoluteTime = 5
private let targetCacheLimit = 64
private var targetCache: [pid_t: TargetCacheEntry] = [:]

private var verticalResidual = 0.0
private var horizontalResidual = 0.0

private func log(_ message: String) {
    let output = "[UUTrackpadFix] \(message)\n"
    FileHandle.standardError.write(Data(output.utf8))
}

private func isUURemoteTarget(_ event: CGEvent) -> Bool {
    let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
    guard pid > 1 else { return false }

    let now = CFAbsoluteTimeGetCurrent()
    if let cached = targetCache[pid], now - cached.checkedAt < targetCacheLifetime {
        return cached.matched
    }

    var matched = false
    if let app = NSRunningApplication(processIdentifier: pid) {
        let bundleMatch = app.bundleIdentifier == targetBundleIdentifier
        let pathMatch = app.executableURL?.path.contains("/UURemote.app/") == true
        matched = bundleMatch || pathMatch
    }

    if targetCache.count >= targetCacheLimit {
        targetCache.removeAll(keepingCapacity: true)
    }
    targetCache[pid] = TargetCacheEntry(matched: matched, checkedAt: now)
    return matched
}

private func isTrackpadEvent(_ event: CGEvent) -> Bool {
    event.getDoubleValueField(.scrollWheelEventMomentumPhase) != 0 ||
    event.getDoubleValueField(.scrollWheelEventScrollPhase) != 0 ||
    event.getDoubleValueField(.scrollWheelEventIsContinuous) == 1
}

private func scaledInteger(_ value: Int64, residual: inout Double) -> Int64 {
    let accumulated = Double(value) * eventScale + residual
    let emitted = Int64(accumulated.rounded(.towardZero))
    residual = accumulated - Double(emitted)
    return emitted
}

private func scaleAxis(
    event: CGEvent,
    delta: CGEventField,
    point: CGEventField,
    fixed: CGEventField,
    residual: inout Double
) {
    // 先读出三个值再写回：写入整数行增量会让系统重算另外两个字段。
    let deltaValue = event.getIntegerValueField(delta)
    let pointValue = event.getDoubleValueField(point)
    let fixedValue = event.getDoubleValueField(fixed)

    event.setIntegerValueField(delta, value: scaledInteger(deltaValue, residual: &residual))
    event.setDoubleValueField(point, value: pointValue * eventScale)
    event.setDoubleValueField(fixed, value: fixedValue * eventScale)
}

private let eventCallback: CGEventTapCallBack = { _, type, event, _ in
    // 回调超时或用户输入保护会让系统停用监听；不重新启用的话调速会静默失效。
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: true)
            log("事件监听被系统停用，已重新启用")
        }
        return Unmanaged.passUnretained(event)
    }
    guard type == .scrollWheel,
          isTrackpadEvent(event),
          isUURemoteTarget(event) else {
        return Unmanaged.passUnretained(event)
    }

    scaleAxis(
        event: event,
        delta: .scrollWheelEventDeltaAxis1,
        point: .scrollWheelEventPointDeltaAxis1,
        fixed: .scrollWheelEventFixedPtDeltaAxis1,
        residual: &verticalResidual
    )
    scaleAxis(
        event: event,
        delta: .scrollWheelEventDeltaAxis2,
        point: .scrollWheelEventPointDeltaAxis2,
        fixed: .scrollWheelEventFixedPtDeltaAxis2,
        residual: &horizontalResidual
    )
    return Unmanaged.passUnretained(event)
}

let promptOptions = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
_ = AXIsProcessTrustedWithOptions(promptOptions)

var announcedWaiting = false
while eventTap == nil {
    eventTap = CGEvent.tapCreate(
        tap: .cgAnnotatedSessionEventTap,
        place: .headInsertEventTap,
        options: .defaultTap,
        eventsOfInterest: CGEventMask(1 << CGEventType.scrollWheel.rawValue),
        callback: eventCallback,
        userInfo: nil
    )
    if eventTap == nil {
        // 只提示一次，避免等待授权期间把日志写满。
        if !announcedWaiting {
            log("等待辅助功能权限；请在系统设置中允许 UU远程触控板调速器")
            announcedWaiting = true
        }
        Thread.sleep(forTimeInterval: 2.0)
    }
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap!, enable: true)
log("已启动；UU 触控板滚动倍率 = \(configuredScale)，反转方向 = \(shouldReverse)")
CFRunLoopRun()
