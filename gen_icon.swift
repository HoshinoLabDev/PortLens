// PortLens App 图标生成器（运行时一次性工具）
// 概念：PortLens = "端口之镜/透镜"。深空蓝紫渐变基底 + 玻璃镜片 + 双色折射弧 +
// 发光 USB-C 端口 + MagSafe 圆环 + 底部数据流。现代扁平 + 细腻渐变 + 精致高光。
// 输出 macOS AppIcon.iconset 各尺寸 PNG（含 1024 主图）。
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

func rr(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: r, yRadius: r)
}

let cyan   = NSColor(calibratedRed: 0.16, green: 0.82, blue: 0.95, alpha: 1)   // #29D1F2
let violet = NSColor(calibratedRed: 0.63, green: 0.50, blue: 0.98, alpha: 1)   // #A17FFA
let deepBg = NSColor(calibratedRed: 0.035, green: 0.055, blue: 0.13, alpha: 1) // #091A21 深空底

// ============ 背景（圆角方，连续圆角 185） ============
let bgPath = rr(0, 0, size, size, 185)

NSGraphicsContext.saveGraphicsState()
bgPath.addClip()

// 主渐变：深海军蓝 → 深蓝紫（对角）
if let g = NSGradient(colors: [
    NSColor(calibratedRed: 0.05, green: 0.09, blue: 0.21, alpha: 1),
    NSColor(calibratedRed: 0.08, green: 0.11, blue: 0.30, alpha: 1),
    NSColor(calibratedRed: 0.17, green: 0.10, blue: 0.34, alpha: 1),
]) {
    g.draw(in: bgPath, angle: -70)
}

// 右上青蓝光晕（径向）
if let radial = NSGradient(colors: [
    NSColor(calibratedRed: 0.12, green: 0.42, blue: 0.60, alpha: 0.85),
    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.20, alpha: 0.0),
]) {
    radial.draw(in: NSRect(x: 0, y: 0, width: size, height: size), relativeCenterPosition: NSPoint(x: 0.66, y: 0.68))
}

// 左下紫光晕（径向）
if let radial2 = NSGradient(colors: [
    NSColor(calibratedRed: 0.28, green: 0.13, blue: 0.52, alpha: 0.75),
    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.20, alpha: 0.0),
]) {
    radial2.draw(in: NSRect(x: 0, y: 0, width: size, height: size), relativeCenterPosition: NSPoint(x: 0.28, y: 0.26))
}

NSGraphicsContext.restoreGraphicsState()

// 顶部高光（上半部白色 0.09 弧）
NSColor(calibratedWhite: 1.0, alpha: 0.09).setFill()
rr(0, size * 0.60, size, size * 0.40, 185).fill()

// ============ 中央玻璃镜片（透镜） ============
let lensRect = NSRect(x: 232, y: 262, width: 560, height: 500)
let lens = NSBezierPath(roundedRect: lensRect, xRadius: 118, yRadius: 118)

NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
shadow.shadowBlurRadius = 34
shadow.shadowOffset = NSSize(width: 0, height: -14)
shadow.set()
if let lg = NSGradient(colors: [
    NSColor(calibratedWhite: 1.0, alpha: 0.17),
    NSColor(calibratedWhite: 1.0, alpha: 0.06),
]) {
    lg.draw(in: lens, angle: -90)
}
NSGraphicsContext.restoreGraphicsState()

// 镜片描边（白 0.32）
NSColor(calibratedWhite: 1.0, alpha: 0.32).setStroke()
lens.lineWidth = 3
lens.stroke()

// ============ 折射弧（镜片内上部：青 + 紫，数据流语义） ============
let arcCenter = NSPoint(x: 512, y: 366)
let arc1 = NSBezierPath()
arc1.appendArc(withCenter: arcCenter, radius: 152, startAngle: 190, endAngle: -10, clockwise: false)
cyan.withAlphaComponent(0.80).setStroke()
arc1.lineWidth = 9
arc1.lineCapStyle = .round
arc1.stroke()

let arc2 = NSBezierPath()
arc2.appendArc(withCenter: arcCenter, radius: 126, startAngle: 190, endAngle: -10, clockwise: false)
violet.withAlphaComponent(0.55).setStroke()
arc2.lineWidth = 5
arc2.lineCapStyle = .round
arc2.stroke()

// ============ USB-C 端口（镜片中央） ============
let portRect = NSRect(x: 312, y: 424, width: 400, height: 176)
// 青色辉光（多层放大描边）
for (dw, a) in [(18, 0.06), (12, 0.10), (7, 0.15)] {
    cyan.withAlphaComponent(a).setStroke()
    let glow = NSBezierPath(roundedRect: portRect.insetBy(dx: -CGFloat(dw), dy: -CGFloat(dw)), xRadius: 52 + CGFloat(dw), yRadius: 52 + CGFloat(dw))
    glow.lineWidth = 2
    glow.stroke()
}

// 端口主体（深色填充 + 青色描边 + 顶部内高光）
let port = NSBezierPath(roundedRect: portRect, xRadius: 52, yRadius: 52)
NSColor(calibratedRed: 0.03, green: 0.06, blue: 0.13, alpha: 0.96).setFill()
port.fill()
cyan.withAlphaComponent(0.95).setStroke()
port.lineWidth = 6
port.stroke()

// 端口顶部内衬高光
NSColor(calibratedWhite: 1.0, alpha: 0.10).setFill()
rr(portRect.minX + 18, portRect.maxY - 22, portRect.width - 36, 9, 4.5).fill()

// 数据芯（中央白色圆角横条 = 端口内芯/透镜焦点）
NSColor(calibratedWhite: 1.0, alpha: 0.92).setFill()
let core = rr(372, 494, 280, 36, 14)
core.fill()
// 芯内青色细线
cyan.withAlphaComponent(0.85).setStroke()
let coreLine = NSBezierPath()
coreLine.move(to: NSPoint(x: 392, y: 512))
coreLine.line(to: NSPoint(x: 632, y: 512))
coreLine.lineWidth = 3
coreLine.lineCapStyle = .round
coreLine.stroke()

// 数据触点（芯上方三个发光点）
for (i, pair) in [(0, -70), (1, 0), (2, 70)].enumerated() {
    let dx = CGFloat(pair.1)
    let px = 512.0 + dx
    cyan.withAlphaComponent(pair.0 == 1 ? 0.95 : 0.55).setFill()
    NSBezierPath(ovalIn: NSRect(x: px - 9, y: 458, width: 18, height: 18)).fill()
}

// ============ MagSafe 圆环（口下方，充电语义） ============
let ringCenter = NSPoint(x: 512, y: 372 + 40)
// 位置调整：口底部 y=424，圆环放 y≈330（镜片内下部）
let ring = NSBezierPath()
ring.appendArc(withCenter: NSPoint(x: 512, y: 336), radius: 44, startAngle: 0, endAngle: 360, clockwise: false)
cyan.withAlphaComponent(0.70).setStroke()
ring.lineWidth = 5
ring.stroke()
// 环内小圆点（MagSafe 触点）
NSColor(calibratedWhite: 1.0, alpha: 0.55).setFill()
NSBezierPath(ovalIn: NSRect(x: 512 - 7, y: 336 - 7, width: 14, height: 14)).fill()

// ============ 底部数据流（镜片外下方，雷电/数据语义） ============
for (i, pair) in [(0, 300), (1, 200), (2, 110)].enumerated() {
    let w = CGFloat(pair.1)
    cyan.withAlphaComponent(0.42 - Double(i) * 0.13).setStroke()
    let line = NSBezierPath()
    let lx = size / 2 - w / 2
    let ly = 118.0 + CGFloat(i) * 26
    line.move(to: NSPoint(x: lx, y: ly))
    line.line(to: NSPoint(x: lx + w, y: ly))
    line.lineWidth = 8
    line.lineCapStyle = .round
    line.stroke()
}

image.unlockFocus()

// ============ 输出 iconset 各尺寸 PNG ============
guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff) else {
    fatalError("无法渲染图标")
}

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
    let scaled = NSImage(size: NSSize(width: px, height: px))
    scaled.lockFocus()
    image.draw(in: NSRect(x: 0, y: 0, width: px, height: px), from: .zero, operation: .sourceOver, fraction: 1)
    scaled.unlockFocus()
    guard let rep = NSBitmapImageRep(data: scaled.tiffRepresentation!),
          let png = rep.representation(using: .png, properties: [:]) else {
        fatalError("PNG 编码失败: \(name)")
    }
    try! png.write(to: URL(fileURLWithPath: "\(outDir)/\(name)"))
    print("写 \(name)")
}
print("完成: \(outDir)")
