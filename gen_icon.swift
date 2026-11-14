// PortLens App 图标生成器（构建期工具）
// 设计语言：对齐 macOS Big Sur 之后的系统图标规范
//   · 1024 画布，内容区 824×824 居中（四周 100 透明留白），连续圆角 185.4
//   · 单一隐喻、单色笔画：品牌蓝渐变底 + 白色 USB-C 母座正面符号（外壳 + 舌片 + 双触点）
//   · 无霓虹辉光、无多色叠加、无文字；小尺寸（<128px）自动加粗笔画，保证 Dock 与 Finder 缩略辨识
import AppKit

/// 直接在当前绘图上下文中绘制，canvas 即目标像素数（严格 1:1）
/// 尺寸分档（跟随 Apple 系统图标"小尺寸换形态"的做法，而非等比缩小）：
///   px ≤ 32   仅空心胶囊（无内芯、无触点），保证 16/32px 干净
///   33…127    胶囊 + 加粗舌片
///   ≥ 128     完整造型：胶囊 + 舌片 + 双触点
func drawIcon(canvas: CGFloat, small: Bool = false) {
    let k = canvas / 1024.0
    let tiny = canvas <= 32

    // ============ 背景：824 连续圆角方 + 品牌蓝渐变 ============
    let inset: CGFloat = 100
    let bgRect = NSRect(x: inset * k, y: inset * k, width: 824 * k, height: 824 * k)
    let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 185.4 * k, yRadius: 185.4 * k)

    NSGraphicsContext.saveGraphicsState()
    bgPath.addClip()
    if let g = NSGradient(colors: [
        NSColor(calibratedRed: 0.145, green: 0.600, blue: 1.000, alpha: 1),  // #2599FF
        NSColor(calibratedRed: 0.024, green: 0.337, blue: 0.784, alpha: 1),  // #0656C8
    ]) {
        g.draw(in: bgRect, angle: -90)
    }
    // 统一自上光照：上半部极淡提亮，避免大色块发闷
    NSColor(calibratedWhite: 1.0, alpha: 0.05).setFill()
    NSBezierPath(rect: NSRect(x: bgRect.minX, y: bgRect.midY,
                              width: bgRect.width, height: bgRect.height / 2)).fill()
    NSGraphicsContext.restoreGraphicsState()

    // ============ 前景：USB-C 母座正面 ============
    // 笔宽按像素绝对下限兜底：16px 档不低于 1px，避免抗锯齿糊成一团
    let strokeW: CGFloat = tiny ? max(1, canvas * 0.085)
        : (small ? max(1.5, canvas * 0.055) : canvas * 0.037)

    // 外壳（横置胶囊）
    let outerRect = NSRect(x: 252 * k, y: 412 * k, width: 520 * k, height: 200 * k)
    let outer = NSBezierPath(roundedRect: outerRect, xRadius: 100 * k, yRadius: 100 * k)
    NSColor(calibratedWhite: 1.0, alpha: 1.0).setStroke()
    outer.lineWidth = strokeW * k
    outer.stroke()

    // 16/32px：仅保留空心胶囊，小尺寸下更干净的"接口"剪影
    if tiny { return }

    // 中央舌片
    let tongueH: CGFloat = small ? 68 : 56
    let tongueW: CGFloat = small ? 244 : 280
    let tongue = NSBezierPath(
        roundedRect: NSRect(x: (512 - tongueW / 2) * k, y: (512 - tongueH / 2) * k,
                            width: tongueW * k, height: tongueH * k),
        xRadius: (tongueH / 2) * k, yRadius: (tongueH / 2) * k)
    NSColor(calibratedWhite: 1.0, alpha: 1.0).setFill()
    tongue.fill()

    // 左右双触点（小尺寸下省略，避免糊成一团）
    if !small {
        let d: CGFloat = 40
        for cx in [332.0, 692.0] {
            let dot = NSBezierPath(ovalIn: NSRect(x: (CGFloat(cx) - d / 2) * k, y: (512 - d / 2) * k,
                                                  width: d * k, height: d * k))
            NSColor(calibratedWhite: 1.0, alpha: 1.0).setFill()
            dot.fill()
        }
    }
}

/// 严格按目标像素渲染 PNG（不依赖 NSImage 的 Retina 缩放）
func renderPNG(px: Int) -> Data? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                                     pixelsWide: px, pixelsHigh: px,
                                     bitsPerSample: 8, samplesPerPixel: 4,
                                     hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB,
                                     bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    drawIcon(canvas: CGFloat(px), small: px < 128)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])
}

// ============ 输出 iconset 全尺寸 ============
let fm = FileManager.default
let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? fm.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

for (px, name) in sizes {
    guard let png = renderPNG(px: px) else { fatalError("PNG 编码失败: \(name)") }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("写 \(name)  \(px)px")
}
print("完成: \(outDir)")
