import Foundation
import CoreGraphics
import IOKit

// MARK: - 显示诊断（Display Diagnostics）
// 读取显示器实时显示模式（CoreGraphics），与 DisplayPort 链路承载能力对比，
// 解释屏幕分辨率/刷新率受限原因；识别 5K/6K 真实分辨率；推断 DSC 压缩；识别链路中的转接器。
// 纯逻辑文件（无 SwiftUI），App 与 CLI 共用。

struct DisplayModeInfo: Identifiable, Equatable {
    let id: UInt32
    let displayIndex: Int
    let name: String
    let physicalWidth: Int
    let physicalHeight: Int
    let logicalWidth: Int
    let logicalHeight: Int
    let refreshRate: Double
    let bandwidthGbps: Double
    let linkCapacityGbps: Double
    let dscRequired: Bool
    let dscRatio: Int
    let adapters: [String]

    /// macOS 在 Retina/缩放模式下逻辑分辨率低于物理像素，即为 HiDPI 缩放
    var isScaled: Bool { physicalWidth != logicalWidth || physicalHeight != logicalHeight }

    var is5K: Bool { physicalWidth >= 4800 && physicalWidth < 5900 && physicalHeight >= 2600 }
    var is6K: Bool { physicalWidth >= 5900 && physicalHeight >= 3000 }

    var isRetina: Bool {
        physicalWidth >= 2 * logicalWidth - 10 && physicalHeight >= 2 * logicalHeight - 10
    }

    var sizeLabel: String {
        if is6K { return "6K" }
        if is5K { return "5K" }
        return "\(physicalWidth) × \(physicalHeight)"
    }

    var resolutionText: String {
        if isScaled {
            return "真实面板 \(physicalWidth) × \(physicalHeight)（\(sizeLabel)），macOS 逻辑显示 \(logicalWidth) × \(logicalHeight)（HiDPI 缩放），分辨率未受链路限制"
        }
        return "\(physicalWidth) × \(physicalHeight)（\(sizeLabel)），原生模式，未缩放"
    }

    var dscText: String {
        if dscRequired {
            return "已启用（带宽推断：需要 \(String(format: "%.1f", bandwidthGbps)) Gbps > 链路承载 \(String(format: "%.1f", linkCapacityGbps)) Gbps，采用约 \(dscRatio):1 压缩）"
        }
        return "未启用（带宽充裕，全质量输出）"
    }

    var verdict: String {
        if dscRequired {
            return "当前模式需要原始带宽约 \(String(format: "%.1f", bandwidthGbps)) Gbps，超过 DisplayPort 链路未压缩承载（约 \(String(format: "%.1f", linkCapacityGbps)) Gbps）。屏幕依赖 DSC 压缩（约 \(dscRatio):1）才到达该顶级模式；DSC 为视觉无损，分辨率与刷新率为面板真实能力，链路未构成瓶颈。"
        }
        if isScaled {
            return "当前显示为 HiDPI 缩放模式，物理面板分辨率高于逻辑显示；链路带宽充裕（需要 \(String(format: "%.1f", bandwidthGbps)) Gbps ≤ 承载 \(String(format: "%.1f", linkCapacityGbps)) Gbps），无需压缩，全质量输出。若屏幕未达顶级模式，通常为 macOS 缩放设置或显示器自身输入限制所致，而非链路带宽不足。"
        }
        return "显示以原生模式输出，链路带宽充裕（需要 \(String(format: "%.1f", bandwidthGbps)) Gbps ≤ 承载 \(String(format: "%.1f", linkCapacityGbps)) Gbps），无压缩、无缩放宽限，全质量输出。"
    }
}

enum DisplayDiagnostics {

    /// 转接器/扩展坞关键词（匹配 USB 设备名，识别链路中的 HDMI/DP 转接器）
    static let adapterKeywords = [
        "hdmi", "displayport", "dp adapter", "dp 转", "adapter", "adaptor",
        "转换", "转接", "dock", "hub", "扩展坞", "dvi", "usb-c to", "usb c to",
        "type-c to", "type c to", "c to hdmi", "c to dp"
    ]

    /// 从 USB 设备名中识别可能位于显示链路中的转接器
    static func adapterNames(from usbDeviceNames: [String]) -> [String] {
        usbDeviceNames.filter { name in
            let lower = name.lowercased()
            return adapterKeywords.contains { lower.contains($0) }
        }
    }

    /// DP 链路未压缩承载能力：Apple Silicon 外接 DP 常用 HBR3 × 4 lanes，
    /// 有效载荷约 21.6 Gbps（若经 Thunderbolt/USB4 隧道，理论更高；此处取保守值）
    static func linkCapacityGbps() -> Double { 21.6 }

    /// 扫描所有活跃显示器，输出显示模式诊断
    static func scanDisplays(usbDeviceNames: [String]) -> [DisplayModeInfo] {
        let maxDisplays: UInt32 = 16
        var displayList = [CGDirectDisplayID](repeating: 0, count: Int(maxDisplays))
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(maxDisplays, &displayList, &count) == .success else { return [] }
        guard count > 0 else { return [] }
        let displays = Array(displayList.prefix(Int(count)))

        let adapters = adapterNames(from: usbDeviceNames)

        var result: [DisplayModeInfo] = []
        for (i, display) in displays.enumerated() {
            guard let mode = CGDisplayCopyDisplayMode(display) else { continue }
            let px = Int(mode.pixelWidth)
            let py = Int(mode.pixelHeight)
            guard px > 0, py > 0 else { continue }
            let bounds = CGDisplayBounds(display)
            let lx = Int(bounds.width)
            let ly = Int(bounds.height)
            var hz = mode.refreshRate
            if hz <= 0 { hz = 60 }

            let bandwidth = Double(px) * Double(py) * hz * 24.0 / 1_000_000_000.0
            let capacity = linkCapacityGbps()
            let dsc = bandwidth > capacity
            var ratio = 1
            if dsc {
                ratio = max(2, Int((bandwidth / capacity).rounded(.up)))
                if ratio > 4 { ratio = 4 } // DSC 通常 2~3:1，超出仅作警示上限
            }

            result.append(DisplayModeInfo(
                id: display,
                displayIndex: i,
                name: "显示器 \(i + 1)",
                physicalWidth: px,
                physicalHeight: py,
                logicalWidth: lx,
                logicalHeight: ly,
                refreshRate: hz,
                bandwidthGbps: bandwidth,
                linkCapacityGbps: capacity,
                dscRequired: dsc,
                dscRatio: ratio,
                adapters: adapters
            ))
        }
        return result
    }
}
