import Cocoa
import ApplicationServices

private let targetBundleIdentifier = "com.netease.uuremote"
private let configuredScale: Double = {
    guard let value = ProcessInfo.processInfo.environment["UU_TRACKPAD_SCALE"],
          let number = Double(value) else { return 0.18 }
    return min(max(number, 0.05), 1.0)
}()
private let shouldReverse = ProcessInfo.processInfo.environment["UU_TRACKPAD_REVERSE"] != "0"
private var eventScale: Double { shouldReverse ? -configuredScale : configuredScale }

private var targetCache: [pid_t: Bool] = [:]
private var verticalResidual = 0.0
private var horizontalResidual = 0.0

private func log(_ message: String) {
    let output = "[UUTrackpadFix] \(message)\n"
    FileHandle.standardError.write(Data(output.utf8))
}

private func isUURemoteTarget(_ event: CGEvent) -> Bool {
    let pid = pid_t(event.getIntegerValueField(.eventTargetUnixProcessID))
    guard pid > 1 else { return false }
    if let cached = targetCache[pid] { return cached }

    guard let app = NSRunningApplication(processIdentifier: pid) else {
        targetCache[pid] = false
        return false
    }
    let bundleMatch = app.bundleIdentifier == targetBundleIdentifier
    let pathMatch = app.executableURL?.path.contains("/UURemote.app/") == true
    let matched = bundleMatch || pathMatch
    targetCache[pid] = matched
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
    let deltaValue = event.getIntegerValueField(delta)
    let pointValue = event.getDoubleValueField(point)
    let fixedValue = event.getDoubleValueField(fixed)

    event.setIntegerValueField(delta, value: scaledInteger(deltaValue, residual: &residual))
    event.setDoubleValueField(point, value: pointValue * eventScale)
    event.setDoubleValueField(fixed, value: fixedValue * eventScale)
}

private let eventCallback: CGEventTapCallBack = { proxy, type, event, _ in
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
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

var eventTap: CFMachPort?
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
        log("等待辅助功能权限；请在系统设置中允许 UU远程触控板调速器")
        Thread.sleep(forTimeInterval: 2.0)
    }
}

let runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
CGEvent.tapEnable(tap: eventTap!, enable: true)
log("已启动；UU 触控板滚动倍率 = \(configuredScale)，反转方向 = \(shouldReverse)")
CFRunLoopRun()
