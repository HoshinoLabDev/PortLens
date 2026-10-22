import Foundation
import Combine

// MARK: - 功率样本（实时功率计量）

struct PowerSample: Identifiable, Equatable {
    let id = UUID()
    let timestamp: Date
    let watts: Double
    let amps: Double
    let volts: Double
    /// 数据来源：battery=电池总线 / input=充电输入 / adapter=适配器额定
    let source: String

    var isChargingFlow: Bool { amps > 0 }
}

/// 功率历史队列：每 2 秒追加一个样本，环形保留最近 N 个（默认 300 = 10 分钟）。
final class PowerMonitorStore: ObservableObject {
    @Published private(set) var samples: [PowerSample] = []
    @Published private(set) var latest: PowerSample?
    @Published var isRunning = false

    let maxSamples: Int
    weak var monitor: USBMonitor?

    init(maxSamples: Int = 300) {
        self.maxSamples = maxSamples
    }

    /// 立即采样一次（由 2 秒定时器或手动触发）
    func sampleNow() {
        guard let monitor else { return }
        monitor.refreshPower()
        let sample = monitor.currentPowerSample()
        append(sample)
    }

    func append(_ sample: PowerSample) {
        samples.append(sample)
        if samples.count > maxSamples {
            samples.removeFirst(samples.count - maxSamples)
        }
        latest = sample
    }

    func clear() {
        samples.removeAll()
        latest = nil
    }

    /// 最近窗口内的平均值（watts）
    func averageWatts(lastMinutes: Double = 5) -> Double? {
        guard !samples.isEmpty else { return nil }
        let cutoff = Date().addingTimeInterval(-lastMinutes * 60)
        let window = samples.filter { $0.timestamp >= cutoff }
        guard !window.isEmpty else { return nil }
        return window.map(\.watts).reduce(0, +) / Double(window.count)
    }

    /// 峰值功率
    func peakWatts() -> Double {
        samples.map(\.watts).max() ?? 0
    }
}

// MARK: - 端口健康计数器（从端口控制器读取）

struct PortHealthStats: Identifiable, Equatable {
    let id: Int
    let controllerIndex: Int

    // 连接生命周期
    var attachCount: Int = 0
    var detachCount: Int = 0

    // 过流 / 硬件类
    var shortDetectCount: Int = 0       // 短路/过流检测
    var fetEnableFailCount: Int = 0     // FET 使能失败（输入保护）

    // 断连 / PD 异常
    var hardResetCount: Int = 0         // PD 硬重置
    var surpriseNackCount: Int = 0      // 意外 NACK（对端异常）
    var vdoFailCount: Int = 0           // VDO 解析失败
    var i2cErrorCount: Int = 0          // I2C 总线错误

    // 其它信号
    var capMismatch: Bool = false       // 能力不匹配标志
    var maxPowerW: Double = 0           // 该控制器最大功率（W）
    var portMode: Int = 0               // 端口模式

    var overcurrentCount: Int { shortDetectCount + fetEnableFailCount }
    var disconnectCount: Int { detachCount + surpriseNackCount + hardResetCount }
    var errorCount: Int { i2cErrorCount + vdoFailCount }

    var totalEvents: Int { attachCount + detachCount + overcurrentCount + hardResetCount + surpriseNackCount + errorCount }

    /// 是否有值得提示的问题
    var hasIssues: Bool { overcurrentCount > 0 || disconnectCount > 0 || errorCount > 0 || capMismatch }

    var summary: String {
        "过流 \(overcurrentCount) · 断连 \(disconnectCount) · 错误 \(errorCount)"
    }

    /// 英文风格摘要（端口卡显示）
    var summaryText: String {
        var parts: [String] = []
        parts.append("过流 \(overcurrentCount)")
        parts.append("断连 \(disconnectCount)")
        parts.append("错误 \(errorCount)")
        if capMismatch { parts.append("能力不匹配") }
        return "端口健康 · " + parts.joined(separator: " · ")
    }
}

// MARK: - PD 契约检查

struct PDContractInfo: Equatable {
    /// 适配器广告的完整 PDO 列表
    var pdoList: [PDOProfile] = []
    /// 当前活跃合约位置（1-based，0=无）
    var activePosition: Int = 0
    /// 协商电压（V）
    var negotiatedVolts: Double?
    /// 协商电流（A）
    var negotiatedAmps: Double?
    /// 协商功率（W）
    var negotiatedWatts: Double? {
        guard let v = negotiatedVolts, let a = negotiatedAmps else { return nil }
        return v * a
    }

    var hasContract: Bool { activePosition > 0 }

    /// 判定：充电能力是否不匹配
    /// - returns: (是否匹配, 说明文字)
    func capabilityVerdict(adapterWatts: Double, chargingWatts: Double, isCharging: Bool, fullyCharged: Bool, cableMaxWatts: Int? = nil) -> (matches: Bool, text: String) {
        if fullyCharged {
            return (true, "电量已满，Mac 不再拉取功率")
        }
        guard hasContract else {
            if adapterWatts > 1 {
                return (true, "未读到活跃 PD 合约，按适配器额定 \(Int(adapterWatts))W 充电")
            }
            return (true, "未读到 PD 合约")
        }
        guard let v = negotiatedVolts, let a = negotiatedAmps else {
            return (true, "已建立 PD 合约，正在充电")
        }
        let negotiated = v * a
        // 充电器额定 vs 协商能力：协商低于适配器能力不必然归因线缆，
        // 仅当协商超过线缆 e-marker 额定能力时才判定线缆限制。
        if adapterWatts > 1 && negotiated < adapterWatts * 0.75 {
            if let cableMax = cableMaxWatts, cableMax > 0, negotiated > Double(cableMax) {
                return (false, "线缆限制充电速度：线缆额定 \(cableMax)W，协商 \(Int(negotiated))W")
            }
            return (false, "当前协商档位低于充电器能力：协商 \(Int(negotiated))W，充电器可达 \(Int(adapterWatts))W")
        }
        if isCharging && chargingWatts > 1 {
            if chargingWatts < negotiated * 0.7 {
                return (true, "充电中 \(Int(chargingWatts))W（Mac 需求较低，合约支持 \(Int(negotiated))W）")
            }
            return (true, "充电良好 · \(Int(chargingWatts))W（合约 \(Int(negotiated))W）")
        }
        return (true, "PD 合约 \(Int(v))V / \(Int(a))A（\(Int(negotiated))W）")
    }
}

// MARK: - 线缆指纹与历史记录

struct CableUsageEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var portLabel: String
    var negotiatedWatts: Double
    var dataSpeed: String
    var healthy: Bool
}

struct CableAnomalyRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var timestamp: Date
    var kind: String      // overcurrent / disconnect / mismatch / fault
    var detail: String
}

struct CableRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    /// e-marker VDO 指纹（无 e-marker 时用 VID:PID 派生）
    var fingerprint: String
    var vendorVID: UInt16?
    var productID: UInt16?
    var speedLabel: String
    var currentRating: Double
    var maxWatts: Int
    var firstSeen: Date
    var lastSeen: Date
    var useCount: Int
    var usageTimeline: [CableUsageEvent]
    var anomalies: [CableAnomalyRecord]
    var notes: String

    var hasAnomalies: Bool { !anomalies.isEmpty }
    var isHealthy: Bool { anomalies.filter { $0.kind != "mismatch" }.isEmpty }
}

/// 线缆历史存储：JSON 持久化到 ~/Library/Application Support/PortLens/cable-history.json
final class CableHistoryStore: ObservableObject {
    @Published private(set) var cables: [CableRecord] = []

    // 编辑 UI 状态（CLT 环境不支持 SwiftUI @State 宏，提升到 store 持有）
    @Published var editingRowID: UUID?
    @Published var draftName = ""
    @Published var expandedRowID: UUID?

    private let fileURL: URL
    private let queue = DispatchQueue(label: "com.marvis.portlens.cablehistory")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent("PortLens", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("cable-history.json")
        load()
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        if let decoded = try? JSONDecoder().decode([CableRecord].self, from: data) {
            cables = decoded.sorted { $0.lastSeen > $1.lastSeen }
        }
    }

    func save() {
        queue.async { [fileURL] in
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            if let data = try? encoder.encode(self.cables) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    /// 按指纹查找线缆
    func record(for fingerprint: String) -> CableRecord? {
        cables.first { $0.fingerprint == fingerprint }
    }

    /// 记录一次使用（无则新建）
    func recordUsage(fingerprint: String,
                     name: String?,
                     vendorVID: UInt16?,
                     productID: UInt16?,
                     speedLabel: String,
                     currentRating: Double,
                     maxWatts: Int,
                     portLabel: String,
                     negotiatedWatts: Double,
                     dataSpeed: String,
                     healthy: Bool,
                     anomaly: CableAnomalyRecord? = nil) {
        let now = Date()
        if let idx = cables.firstIndex(where: { $0.fingerprint == fingerprint }) {
            var record = cables[idx]
            record.lastSeen = now
            record.useCount += 1
            record.speedLabel = speedLabel
            record.currentRating = currentRating
            record.maxWatts = maxWatts
            record.usageTimeline.append(CableUsageEvent(timestamp: now, portLabel: portLabel,
                                                        negotiatedWatts: negotiatedWatts,
                                                        dataSpeed: dataSpeed, healthy: healthy))
            if record.usageTimeline.count > 200 { record.usageTimeline.removeFirst(record.usageTimeline.count - 200) }
            if let a = anomaly {
                record.anomalies.append(a)
                if record.anomalies.count > 100 { record.anomalies.removeFirst(record.anomalies.count - 100) }
            }
            cables[idx] = record
        } else {
            let record = CableRecord(
                id: UUID(),
                name: name ?? "未命名线缆 \(String(fingerprint.prefix(6)).uppercased())",
                fingerprint: fingerprint,
                vendorVID: vendorVID,
                productID: productID,
                speedLabel: speedLabel,
                currentRating: currentRating,
                maxWatts: maxWatts,
                firstSeen: now,
                lastSeen: now,
                useCount: 1,
                usageTimeline: [CableUsageEvent(timestamp: now, portLabel: portLabel,
                                                negotiatedWatts: negotiatedWatts,
                                                dataSpeed: dataSpeed, healthy: healthy)],
                anomalies: anomaly.map { [$0] } ?? [],
                notes: ""
            )
            cables.insert(record, at: 0)
        }
        save()
    }

    /// 重命名线缆
    func rename(_ id: UUID, to newName: String) {
        guard let idx = cables.firstIndex(where: { $0.id == id }) else { return }
        cables[idx].name = newName
        save()
    }

    /// 手动记录异常
    func addAnomaly(_ id: UUID, kind: String, detail: String) {
        guard let idx = cables.firstIndex(where: { $0.id == id }) else { return }
        cables[idx].anomalies.append(CableAnomalyRecord(timestamp: Date(), kind: kind, detail: detail))
        save()
    }

    /// 删除记录（仅删除登记，不动磁盘文件）
    func remove(_ id: UUID) {
        cables.removeAll { $0.id == id }
        save()
    }

    func resetAll() {
        cables.removeAll()
        save()
    }
}

// MARK: - 协商诊断

struct NegotiationRow: Identifiable, Equatable {
    let id = UUID()
    let role: String        // "Mac 端口" / "线缆" / "设备"
    let supportsLabel: String
    let negotiatedLabel: String
    let isWeak: Bool
    let note: String?
    /// 支持速率（Gbps，用于对比条可视化；无数据链路时为 nil）
    var supportsValue: Double? = nil
    /// 实际协商速率（Gbps；无数据链路时为 nil）
    var negotiatedValue: Double? = nil
}

struct NegotiationDiagnosticsResult: Equatable {
    let portLabel: String
    let rows: [NegotiationRow]
    let weakRole: String?
    let summary: String
}

// MARK: - 液体检测（LDCM）

struct LiquidDetectionState: Equatable {
    let present: Bool
    let lastDetected: Date?
    let irqCount: Int
    let rawStatus: String?

    static let idle = LiquidDetectionState(present: false, lastDetected: nil, irqCount: 0, rawStatus: nil)
    static let notSupported = LiquidDetectionState(present: false, lastDetected: nil, irqCount: 0, rawStatus: "unsupported")

    enum Mode { case normal, detected, warning }

    var mode: Mode {
        if present { return .detected }
        if irqCount > 0 { return .warning }
        return .normal
    }
}

// MARK: - 线缆电阻估算

struct CableResistanceEstimate: Equatable {
    let ohms: Double
    let milliohms: Int
    let note: String
    /// 低置信度：系统电流 <1.5A 时压差信号弱、噪声占比高，数值仅供参考
    let lowConfidence: Bool

    var formatted: String {
        if ohms >= 1 { return String(format: "%.2f Ω", ohms) }
        return "\(milliohms) mΩ"
    }
}

// MARK: - 引脚图

struct PinRow: Identifiable, Equatable {
    let id = UUID()
    let side: String    // "A" / "B"
    let number: Int
    let name: String
    let group: String
}

struct PinDiagramData {
    let title: String
    let subtitle: String
    let rows: [PinRow]

    static let usbC = PinDiagramData(
        title: "USB-C 24 引脚",
        subtitle: "面向插头（公头）视角 · A 排左侧，B 排右侧",
        rows: [
            PinRow(side: "A", number: 1, name: "GND", group: "电源"),
            PinRow(side: "A", number: 2, name: "SSTXp1", group: "SuperSpeed TX1"),
            PinRow(side: "A", number: 3, name: "SSTXn1", group: "SuperSpeed TX1"),
            PinRow(side: "A", number: 4, name: "VBUS", group: "电源"),
            PinRow(side: "A", number: 5, name: "CC1", group: "配置"),
            PinRow(side: "A", number: 6, name: "DP1", group: "USB 2.0"),
            PinRow(side: "A", number: 7, name: "DN1", group: "USB 2.0"),
            PinRow(side: "A", number: 8, name: "SBU1", group: "边带"),
            PinRow(side: "A", number: 9, name: "VBUS", group: "电源"),
            PinRow(side: "A", number: 10, name: "SSRXn1", group: "SuperSpeed RX1"),
            PinRow(side: "A", number: 11, name: "SSRXp1", group: "SuperSpeed RX1"),
            PinRow(side: "A", number: 12, name: "GND", group: "电源"),
            PinRow(side: "B", number: 1, name: "GND", group: "电源"),
            PinRow(side: "B", number: 2, name: "SSTXp2", group: "SuperSpeed TX2"),
            PinRow(side: "B", number: 3, name: "SSTXn2", group: "SuperSpeed TX2"),
            PinRow(side: "B", number: 4, name: "VBUS", group: "电源"),
            PinRow(side: "B", number: 5, name: "CC2", group: "配置"),
            PinRow(side: "B", number: 6, name: "DP2", group: "USB 2.0"),
            PinRow(side: "B", number: 7, name: "DN2", group: "USB 2.0"),
            PinRow(side: "B", number: 8, name: "SBU2", group: "边带"),
            PinRow(side: "B", number: 9, name: "VBUS", group: "电源"),
            PinRow(side: "B", number: 10, name: "SSRXn2", group: "SuperSpeed RX2"),
            PinRow(side: "B", number: 11, name: "SSRXp2", group: "SuperSpeed RX2"),
            PinRow(side: "B", number: 12, name: "GND", group: "电源"),
        ]
    )
}
