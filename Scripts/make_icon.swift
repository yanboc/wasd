// 生成 AppIcon.icns：深色圆角键帽 + 白色 ⇪ 与方向箭头。
// 用法: swift Scripts/make_icon.swift   （在项目根目录执行，产出 Resources/AppIcon.icns）
import AppKit

let canvas: CGFloat = 1024

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    guard let ctx = NSGraphicsContext.current?.cgContext else { return image }
    let s = size / canvas // 缩放系数

    // macOS 图标圆角（约 22.37%）
    let bodyRect = NSRect(x: 32 * s, y: 32 * s, width: 960 * s, height: 960 * s)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 215 * s, yRadius: 215 * s)

    // 深蓝灰渐变键帽
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.16, green: 0.20, blue: 0.30, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.15, alpha: 1),
    ])!
    bodyPath.addClip()
    gradient.draw(in: bodyPath, angle: -90)

    // 顶部高光描边
    ctx.saveGState()
    bodyPath.addClip()
    NSColor(white: 1, alpha: 0.18).setStroke()
    bodyPath.lineWidth = 6 * s
    bodyPath.stroke()
    ctx.restoreGState()

    // ⇪ 符号
    let symbolFont = NSFont.systemFont(ofSize: 380 * s, weight: .bold)
    let symbolAttrs: [NSAttributedString.Key: Any] = [
        .font: symbolFont,
        .foregroundColor: NSColor.white,
    ]
    let symbol = NSAttributedString(string: "⇪", attributes: symbolAttrs)
    let symbolSize = symbol.size()
    symbol.draw(at: NSPoint(x: (size - symbolSize.width) / 2, y: 470 * s - symbolSize.height / 2 + 120 * s))

    // 底部四枚方向箭头 ↑ ← ↓ →（呼应 WASD 导航）
    let arrowColor = NSColor(calibratedRed: 0.45, green: 0.75, blue: 1.0, alpha: 1)
    arrowColor.setFill()
    let aw: CGFloat = 88 * s  // 箭头半宽
    let ah: CGFloat = 70 * s  // 箭头高度
    let cy: CGFloat = 240 * s
    let gap: CGFloat = 150 * s
    func arrow(centerX: CGFloat, centerY: CGFloat, angle: CGFloat) {
        let path = NSBezierPath()
        path.move(to: NSPoint(x: 0, y: ah / 2))           // 顶点
        path.line(to: NSPoint(x: aw / 2, y: -ah / 4))     // 右翼
        path.line(to: NSPoint(x: aw / 6, y: -ah / 4))
        path.line(to: NSPoint(x: aw / 6, y: -ah / 2))     // 尾右
        path.line(to: NSPoint(x: -aw / 6, y: -ah / 2))    // 尾左
        path.line(to: NSPoint(x: -aw / 6, y: -ah / 4))
        path.line(to: NSPoint(x: -aw / 2, y: -ah / 4))    // 左翼
        path.close()
        // 先旋转再平移到目标点（append 顺序：translate 后再 rotate，得到 p' = T·R·p）
        var t = AffineTransform(translationByX: centerX, byY: centerY)
        t.rotate(byRadians: angle)
        path.transform(using: t)
        path.fill()
    }
    // 上
    arrow(centerX: size / 2, centerY: cy + gap * 0.55, angle: 0)
    // 左 下 右
    arrow(centerX: size / 2 - gap, centerY: cy - gap * 0.45, angle: .pi / 2)
    arrow(centerX: size / 2, centerY: cy - gap * 0.45, angle: .pi)
    arrow(centerX: size / 2 + gap, centerY: cy - gap * 0.45, angle: -.pi / 2)

    image.unlockFocus()
    return image
}

func pngData(_ image: NSImage, size: CGFloat) -> Data? {
    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff) else { return nil }
    rep.size = NSSize(width: size, height: size)
    guard let scaled = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: scaled)
    NSGraphicsContext.current?.imageInterpolation = .high
    rep.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
    NSGraphicsContext.restoreGraphicsState()
    return scaled.representation(using: .png, properties: [:])
}

let fm = FileManager.default
let iconsetPath = "AppIcon.iconset"
try? fm.removeItem(atPath: iconsetPath)
try fm.createDirectory(atPath: iconsetPath, withIntermediateDirectories: true)
try fm.createDirectory(atPath: "Resources", withIntermediateDirectories: true)

let master = drawIcon(size: canvas)
// iconset 命名: icon_{points}x{points}(@2x).png
let entries: [(String, CGFloat)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in entries {
    guard let data = pngData(master, size: px) else {
        FileHandle.standardError.write("导出 \(name) 失败\n".data(using: .utf8)!)
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: "\(iconsetPath)/\(name).png"))
}

let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", iconsetPath, "-o", "Resources/AppIcon.icns"]
try task.run()
task.waitUntilExit()
guard task.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil 失败: \(task.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}
try? fm.removeItem(atPath: iconsetPath)
print("已生成 Resources/AppIcon.icns")
