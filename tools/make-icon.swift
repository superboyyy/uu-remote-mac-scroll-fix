// 生成设置应用的图标。
// 用法：xcrun swift tools/make-icon.swift <输出.icns> [预览.png]
//
// 图标是用代码画的原创图形（蓝色圆角方块 + 白色鼠标 + 上下箭头），
// 不使用 UU 远程或 Mos 的标志，也不使用 SF Symbols（其许可不允许用作应用图标）。

import AppKit

// 所有坐标都在 1024×1024 的画布上，原点在左下角。
func drawIcon(in context: CGContext) {
    let deviceRGB = CGColorSpaceCreateDeviceRGB()
    func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
        CGColor(colorSpace: deviceRGB, components: [r, g, b, a])!
    }
    let white = color(1, 1, 1)
    let deepBlue = color(0.08, 0.36, 0.92)

    // macOS 图标规范：1024 画布里放 824 的圆角方块，四周留白给投影。
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

    // 底板投影
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.30))
    context.addPath(tilePath)
    context.setFillColor(deepBlue)
    context.fillPath()
    context.restoreGState()

    // 底板渐变 + 顶部高光
    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    let background = CGGradient(
        colorsSpace: deviceRGB,
        colors: [color(0.27, 0.70, 1.00), color(0.06, 0.30, 0.88)] as CFArray,
        locations: [0, 1]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: 512, y: tile.maxY),
        end: CGPoint(x: 512, y: tile.minY),
        options: []
    )
    let highlight = CGGradient(
        colorsSpace: deviceRGB,
        colors: [color(1, 1, 1, 0.22), color(1, 1, 1, 0)] as CFArray,
        locations: [0, 1]
    )!
    context.drawRadialGradient(
        highlight,
        startCenter: CGPoint(x: 512, y: tile.maxY + 80), startRadius: 0,
        endCenter: CGPoint(x: 512, y: tile.maxY + 80), endRadius: 620,
        options: []
    )
    context.restoreGState()

    // 鼠标
    let mouse = CGRect(x: 512 - 125, y: 512 - 215, width: 250, height: 430)
    let mousePath = CGPath(roundedRect: mouse, cornerWidth: 125, cornerHeight: 125, transform: nil)
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: color(0, 0.10, 0.40, 0.35))
    context.addPath(mousePath)
    context.setFillColor(white)
    context.fillPath()
    context.restoreGState()

    // 滚轮
    let wheel = CGRect(x: 512 - 23, y: mouse.maxY - 62 - 118, width: 46, height: 118)
    context.addPath(CGPath(roundedRect: wheel, cornerWidth: 23, cornerHeight: 23, transform: nil))
    context.setFillColor(deepBlue)
    context.fillPath()

    // 左侧向上、右侧向下的箭头：表示切换滚动方向。
    context.saveGState()
    context.setStrokeColor(color(1, 1, 1, 0.95))
    context.setLineWidth(46)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    let top: CGFloat = 628
    let bottom: CGFloat = 396
    let head: CGFloat = 62

    let leftX: CGFloat = 262
    context.move(to: CGPoint(x: leftX, y: bottom))
    context.addLine(to: CGPoint(x: leftX, y: top))
    context.move(to: CGPoint(x: leftX - head, y: top - head))
    context.addLine(to: CGPoint(x: leftX, y: top))
    context.addLine(to: CGPoint(x: leftX + head, y: top - head))

    let rightX: CGFloat = 762
    context.move(to: CGPoint(x: rightX, y: top))
    context.addLine(to: CGPoint(x: rightX, y: bottom))
    context.move(to: CGPoint(x: rightX - head, y: bottom + head))
    context.addLine(to: CGPoint(x: rightX, y: bottom))
    context.addLine(to: CGPoint(x: rightX + head, y: bottom + head))
    context.strokePath()
    context.restoreGState()
}

func renderPNG(pixels: Int) -> Data {
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    )!
    let graphics = NSGraphicsContext(bitmapImageRep: bitmap)!
    let context = graphics.cgContext
    context.interpolationQuality = .high
    context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
    drawIcon(in: context)
    graphics.flushGraphics()
    return bitmap.representation(using: .png, properties: [:])!
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write(Data("用法：make-icon.swift <输出.icns> [预览.png]\n".utf8))
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])

let iconset = FileManager.default.temporaryDirectory
    .appendingPathComponent("AppIcon-\(ProcessInfo.processInfo.processIdentifier).iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
defer { try? FileManager.default.removeItem(at: iconset) }

// iconutil 要求的文件名和像素尺寸。
for points in [16, 32, 128, 256, 512] {
    try renderPNG(pixels: points).write(to: iconset.appendingPathComponent("icon_\(points)x\(points).png"))
    try renderPNG(pixels: points * 2).write(to: iconset.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    FileHandle.standardError.write(Data("iconutil 失败\n".utf8))
    exit(1)
}

if arguments.count >= 3 {
    try renderPNG(pixels: 1024).write(to: URL(fileURLWithPath: arguments[2]))
}
print("已生成：\(output.path)")
