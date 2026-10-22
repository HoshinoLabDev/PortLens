import SwiftUI
import Charts
import AppKit
import Combine

// MARK: - Pro 窗口管理器（独立成窗）

final class ProWindowManager {
    static let shared = ProWindowManager()
    private var windows: [String: NSWindow] = [:]

    private init() {}

    func openWindow<Content: View>(id: String, title: String, content: Content, width: CGFloat, height: CGFloat) {
        if let existing = windows[id], existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: width, height: height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = title
        window.setContentSize(NSSize(width: width, height: height))
        // 毛玻璃材质：以 NSVisualEffectView 作为背景层，SwiftUI 内容叠在其上
        let hosting = NSHostingController(rootView: content)
        // 禁止 hosting 用 SwiftUI 理想尺寸收缩窗口（内容较空时窗口会塌缩）
        hosting.sizingOptions = []
        let effect = NSVisualEffectView()
        effect.material = .underWindowBackground
        effect.blendingMode = .behindWindow
        effect.state = .active
        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        effect.frame = container.bounds
        effect.autoresizingMask = [.width, .height]
        container.addSubview(effect, positioned: .below, relativeTo: nil)
        hosting.view.frame = container.bounds
        hosting.view.autoresizingMask = [.width, .height]
        hosting.view.wantsLayer = true
        hosting.view.layer?.backgroundColor = NSColor.clear.cgColor
        container.addSubview(hosting.view)
        window.contentView = container
        window.minSize = NSSize(width: width, height: height)
        window.setContentSize(NSSize(width: width, height: height))
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        windows[id] = window
    }

    func closeWindow(id: String) {
        windows[id]?.close()
        windows[id] = nil
    }

    func closeAll() {
        for (_, w) in windows { w.close() }
        windows.removeAll()
    }

    var hasOpenWindows: Bool { !windows.isEmpty }
}

// MARK: - 功率监控窗口（SwiftUI Charts 实时功率输入图）

struct PowerMonitorView: View {
    @ObservedObject var powerStore: PowerMonitorStore
    @ObservedObject var monitor: USBMonitor

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            header
            Divider().opacity(0.5)
            liveValues
            chart
            statsRow
        }
        .padding(Theme.spacingL)
        .frame(minWidth: 560, minHeight: 500)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                Image(systemName: "bolt.badge.clock")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("Power Monitor")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("实时功率输入遥测")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                if powerStore.isRunning {
                    powerStore.isRunning = false
                } else {
                    powerStore.isRunning = true
                }
            } label: {
                Image(systemName: powerStore.isRunning ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 18))
                    .foregroundStyle(powerStore.isRunning ? Color.orange : Color.green)
            }
            .buttonStyle(.plain)
            .help(powerStore.isRunning ? "暂停采样" : "开始采样")

            Button {
                powerStore.clear()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("清空历史")
        }
    }

    private var liveValues: some View {
        let p = monitor.power
        // 实时进电遥测优先（SystemPowerIn 为实时值；IPDInputPower 是协商电流档×电压，恒定虚高）
        let hasTelemetry = p.externalConnected && p.systemPowerInMW > 1
        let inputW = hasTelemetry ? p.systemPowerInMW / 1000.0 : 0
        let displayW = inputW > 0 ? inputW : p.wattsNow
        let displayV = inputW > 0 ? p.systemVoltageInMV / 1000.0 : p.voltageMV / 1000.0
        let displayA = inputW > 0 ? abs(p.systemCurrentInMA) / 1000.0 : abs(p.amperageMA) / 1000.0
        let stateText = p.externalConnected ? (p.isCharging ? "充电中" : (p.fullyCharged ? "已充满" : "已接电源")) : "使用电池"
        let stateColor: Color = p.isCharging ? .green : (p.fullyCharged ? .green : .secondary)

        return ZStack(alignment: .topTrailing) {
            HStack(spacing: 24) {
                metric(label: "功率", value: String(format: "%.1f W", displayW), color: .green, size: 30)
                metric(label: "电流", value: String(format: "%.2f A", displayA), color: .blue, size: 22)
                metric(label: "电压", value: String(format: "%.1f V", displayV), color: .orange, size: 22)
                Spacer()
            }
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: p.isCharging ? "bolt.fill" : "battery.100")
                        .font(.system(size: 9, weight: .semibold))
                    Text(stateText)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                }
                .foregroundStyle(stateColor)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(stateColor.opacity(0.13)))
                .overlay(Capsule().strokeBorder(stateColor.opacity(0.28), lineWidth: 1))
                Text("电池 \(p.batteryPercent)%")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(Theme.spacingL)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(
                    LinearGradient(colors: [.green.opacity(0.4), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.glassShadow, radius: 6, y: 1)
    }

    private func metric(label: String, value: String, color: Color, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: size, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }

    private var chart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("实时功率输入")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                if let last = powerStore.samples.last {
                    HStack(spacing: 4) {
                        Image(systemName: "circle.fill")
                            .font(.system(size: 7))
                            .foregroundStyle(.green)
                        Text("当前 \(String(format: "%.1f W", last.watts))")
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.12)))
                    .overlay(Capsule().strokeBorder(Color.green.opacity(0.28), lineWidth: 1))
                }
            }
            Group {
                if powerStore.samples.isEmpty {
                    emptyChart
                } else {
                    Chart {
                        ForEach(powerStore.samples) { sample in
                            AreaMark(
                                x: .value("时间", sample.timestamp),
                                y: .value("功率", sample.watts)
                            )
                            .foregroundStyle(
                                LinearGradient(colors: [.green.opacity(0.5), .green.opacity(0.02)],
                                               startPoint: .top, endPoint: .bottom)
                            )
                            .interpolationMethod(.catmullRom)
                            LineMark(
                                x: .value("时间", sample.timestamp),
                                y: .value("功率", sample.watts)
                            )
                            .foregroundStyle(.green)
                            .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                            .interpolationMethod(.catmullRom)
                        }
                        if let last = powerStore.samples.last {
                            RuleMark(y: .value("当前", last.watts))
                                .foregroundStyle(.green.opacity(0.5))
                                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                            PointMark(
                                x: .value("时间", last.timestamp),
                                y: .value("功率", last.watts)
                            )
                            .foregroundStyle(.green)
                            .symbolSize(70)
                        }
                    }
                    .chartYScale(domain: 0...(max(powerStore.peakWatts() * 1.15, 20)))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                            AxisGridLine().foregroundStyle(.tertiary.opacity(0.4))
                            AxisValueLabel(format: .dateTime.hour().minute().second(), centered: false)
                                .font(.system(size: 9))
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { _ in
                            AxisGridLine().foregroundStyle(.tertiary.opacity(0.4))
                            AxisValueLabel().font(.system(size: 9))
                        }
                    }
                }
            }
            .frame(height: 240)
            .padding(4)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                        .fill(Theme.glassCardFill)
                    RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                        .fill(Theme.glassTopHighlight)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )
        }
    }

    private var emptyChart: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Color.green.opacity(0.08)).frame(width: 48, height: 48)
                Image(systemName: "chart.xyaxis.line")
                    .font(.system(size: 20))
                    .foregroundStyle(.green.opacity(0.7))
            }
            Text("正在等待采样…每 2 秒一个样本")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var statsRow: some View {
        HStack(spacing: Theme.spacingL) {
            stat(title: "5 分钟均值", value: powerStore.averageWatts().map { String(format: "%.1f W", $0) } ?? "—")
            stat(title: "峰值", value: String(format: "%.1f W", powerStore.peakWatts()))
            stat(title: "样本数", value: "\(powerStore.samples.count)")
            stat(title: "采样间隔", value: "2 s")
            Spacer()
            Text("来源：\(powerStore.latest?.source == "input" ? "充电输入 (IPDInputPower)" : "电池总线")")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .padding(Theme.spacingM)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
    }

    private func stat(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
    }
}

// MARK: - 协商诊断窗口

struct NegotiationDiagnosticsView: View {
    @ObservedObject var monitor: USBMonitor
    @ObservedObject var cableStore: CableHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            header
            Divider().opacity(0.5)
            if diagnostics.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacingL) {
                        ForEach(diagnostics, id: \.portLabel) { result in
                            negotiationCard(result)
                        }
                    }
                }
            }
        }
        .padding(Theme.spacingL)
        .frame(minWidth: 560, minHeight: 420)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("协商诊断")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("对比 Mac 端口 / 线缆 / 设备各自支持能力与实际协商结果，弱环节高亮。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !diagnostics.isEmpty {
                Text("\(diagnostics.count) 个端口")
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Capsule().fill(Theme.accent.opacity(0.12)))
                    .foregroundStyle(Theme.accent)
                    .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
            }
        }
    }

    private var diagnostics: [NegotiationDiagnosticsResult] {
        var results: [NegotiationDiagnosticsResult] = []
        for port in monitor.ports where port.isConnected {
            let devices = port.devices
            let cable = monitor.eMarkerDetail(portIndex: port.portNumber ?? port.portIndex)
            let negotiated = devices.compactMap(\.speedGbps).max()
            results.append(
                ProLogic.buildNegotiationDiagnostics(
                    portLabel: portLabel(for: port),
                    portMaxGbps: nil,
                    cable: cable,
                    devices: devices,
                    negotiatedSpeedGbps: negotiated
                )
            )
        }
        return results
    }

    private func portLabel(for card: PortCardModel) -> String {
        if card.isMagSafe { return "MagSafe" }
        return "TypeC \(card.portNumber ?? 0)"
    }

    private func negotiationCard(_ result: NegotiationDiagnosticsResult) -> some View {
        let weak = result.weakRole
        let maxValue = (result.rows.compactMap { $0.supportsValue }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: weak == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 15))
                    .foregroundStyle(weak == nil ? .green : .orange)
                Text(result.portLabel)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                Spacer()
                if result.portLabel.contains("MagSafe") {
                    statusPill("充电专用", color: .secondary, icon: "bolt.fill")
                } else if let weak = weak {
                    statusPill("弱环节：\(weak)", color: .orange, icon: "exclamationmark.triangle.fill")
                } else {
                    statusPill("全链路匹配", color: .green, icon: "checkmark.circle.fill")
                }
            }
            Text(result.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                ForEach(result.rows, id: \.id) { row in
                    DiagnosticComparisonBar(
                        label: row.role,
                        supports: row.supportsValue ?? 0,
                        negotiated: row.negotiatedValue ?? 0,
                        isWeak: row.isWeak,
                        maxValue: maxValue
                    )
                }
            }
            .padding(Theme.spacingM)
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                        .fill(Theme.glassCardFill.opacity(0.7))
                    RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                        .fill(Theme.glassTopHighlight)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .strokeBorder(weak != nil ? Color.orange.opacity(0.35) : Color.green.opacity(0.25), lineWidth: 1)
            )
        }
        .padding(Theme.spacingL)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(
                    weak != nil
                        ? LinearGradient(colors: [.orange.opacity(0.45), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.green.opacity(0.35), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.glassShadow, radius: 8, y: 1)
    }

    private func statusPill(_ text: String, color: Color, icon: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            Text(text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.13)))
        .overlay(Capsule().strokeBorder(color.opacity(0.3), lineWidth: 1))
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.08)).frame(width: 56, height: 56)
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent.opacity(0.7))
            }
            Text("当前没有已连接端口，无法生成协商诊断")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// 协商对比条：支持能力（蓝底轨） vs 协商结果（绿/橙实条），弱链橙色高亮
private struct DiagnosticComparisonBar: View {
    let label: String
    let supports: Double
    let negotiated: Double
    let isWeak: Bool
    var maxValue: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .frame(width: 58, alignment: .leading)
                Text("支持 \(String(format: "%.1f Gbps", supports))")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("协商 \(String(format: "%.1f Gbps", negotiated))")
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(isWeak ? Color.orange : Color.green)
                if isWeak {
                    Text("瓶颈")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.orange))
                }
            }
            GeometryReader { geo in
                let norm = maxValue > 0 ? maxValue : 1
                let supportW = geo.size.width * CGFloat(min(supports / norm, 1))
                let negotiatedW = geo.size.width * CGFloat(min(negotiated / norm, 1))
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.glassCardFill)
                        .frame(width: geo.size.width, height: 7)
                    Capsule().fill(Color.blue.opacity(0.3))
                        .frame(width: max(8, supportW), height: 7)
                    Capsule().fill(isWeak ? Color.orange : Color.green)
                        .frame(width: max(8, negotiatedW), height: 7)
                }
            }
            .frame(height: 7)
        }
    }
}

// MARK: - Saved Cables（线缆历史）

struct SavedCablesView: View {
    @ObservedObject var cableStore: CableHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            header
            Divider().opacity(0.5)
            if cableStore.cables.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spacingM) {
                        ForEach(cableStore.cables) { cable in
                            CableRowView(cable: cable, store: cableStore)
                        }
                    }
                }
            }
        }
        .padding(Theme.spacingL)
        .frame(minWidth: 480, minHeight: 420)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                Image(systemName: "cable.connector")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("线缆历史")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("插入带 e-marker 的线缆后自动建立指纹记录")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Text("\(cableStore.cables.count) 条记录")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Theme.accent.opacity(0.12)))
                .foregroundStyle(Theme.accent)
                .overlay(Capsule().strokeBorder(Theme.accent.opacity(0.28), lineWidth: 1))
            Button {
                cableStore.resetAll()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 11))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
            .help("清空全部历史")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.08)).frame(width: 56, height: 56)
                Image(systemName: "cable.connector.slash")
                    .font(.system(size: 24))
                    .foregroundStyle(Theme.accent.opacity(0.7))
            }
            Text("还没有保存过线缆。插入带 e-marker 的线缆后会自动建立指纹记录。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct CableRowView: View {
    let cable: CableRecord
    @ObservedObject var store: CableHistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: cable.hasAnomalies ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(cable.hasAnomalies ? .orange : .green)
                if store.editingRowID == cable.id {
                    TextField("线缆名称", text: Binding(get: { store.draftName }, set: { store.draftName = $0 }))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 180)
                        .onSubmit { commitRename() }
                    Button("保存") { commitRename() }
                        .controlSize(.small)
                    Button("取消") { store.editingRowID = nil }
                        .controlSize(.small)
                } else {
                    Text(cable.name)
                        .font(.system(size: 13, weight: .semibold))
                    Button {
                        store.draftName = cable.name
                        store.editingRowID = cable.id
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
                Spacer()
                Text(cable.speedLabel)
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.purple.opacity(0.14)))
                    .foregroundStyle(.purple)
                Text("\(cable.maxWatts)W")
                    .font(.system(size: 10, weight: .semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Color.green.opacity(0.14)))
                    .foregroundStyle(.green)
            }

            HStack(spacing: 12) {
                Label("使用 \(cable.useCount) 次", systemImage: "arrow.triangle.2.circlepath")
                Label("最近 \(cable.lastSeen.formatted(date: .abbreviated, time: .shortened))", systemImage: "clock")
                if cable.hasAnomalies {
                    Label("\(cable.anomalies.count) 条异常", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
                Spacer()
                Button(store.expandedRowID == cable.id ? "收起" : "详情") {
                    store.expandedRowID = (store.expandedRowID == cable.id ? nil : cable.id)
                }
                .controlSize(.small)
                Button {
                    store.remove(cable.id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                        .foregroundStyle(.red.opacity(0.7))
                }
                .buttonStyle(.plain)
                .help("删除记录")
            }
            .font(.system(size: 10))
            .foregroundStyle(.secondary)

            if store.expandedRowID == cable.id {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    if let vid = cable.vendorVID {
                        Text("厂商：\(CableVendorDB.displayName(for: vid))")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                    Text("指纹：\(cable.fingerprint)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .textSelection(.enabled)
                    if cable.usageTimeline.isEmpty == false {
                        Text("使用时间线（最近 5 次）")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(cable.usageTimeline.suffix(5).reversed()) { ev in
                            HStack(spacing: 6) {
                                Circle().fill(ev.healthy ? Color.green : Color.orange).frame(width: 5, height: 5)
                                Text(ev.timestamp.formatted(date: .abbreviated, time: .shortened))
                                Text("· \(ev.portLabel)")
                                Text("· \(Int(ev.negotiatedWatts))W")
                                Text("· \(ev.dataSpeed)")
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                    }
                    if !cable.anomalies.isEmpty {
                        Text("异常记录")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.orange)
                        ForEach(cable.anomalies.suffix(5).reversed()) { a in
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 8))
                                    .foregroundStyle(.orange)
                                Text(a.timestamp.formatted(date: .abbreviated, time: .shortened))
                                Text("· \(a.kind)")
                                Text("· \(a.detail)")
                            }
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .padding(Theme.spacingM)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(
                    cable.hasAnomalies
                        ? LinearGradient(colors: [.orange.opacity(0.5), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.glassShadow, radius: 6, y: 1)
    }

    private func commitRename() {
        let trimmed = store.draftName.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            store.rename(cable.id, to: trimmed)
        }
        store.editingRowID = nil
    }
}

// MARK: - 引脚图窗口

struct PinDiagramView: View {
    private let data = PinDiagramData.usbC

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Theme.brandGradient)
                        .frame(width: 32, height: 32)
                        .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                    Image(systemName: "cpu")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("引脚图")
                        .font(.system(size: 15, weight: .bold, design: .rounded))
                    Text(data.subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
            Divider().opacity(0.5)

            HStack(alignment: .top, spacing: Theme.spacingL) {
                pinColumn("A 排", side: "A", groupColor: .blue)
                pinColumn("B 排", side: "B", groupColor: .green)
            }
            .frame(maxWidth: .infinity, alignment: .center)

            Divider().opacity(0.5)
            legend
            Spacer()
        }
        .padding(Theme.spacingL)
        .frame(minWidth: 440, minHeight: 540)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private func pinColumn(_ title: String, side: String, groupColor: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
            ForEach(data.rows.filter { $0.side == side }) { pin in
                HStack(spacing: 8) {
                    Text("\(pin.side)\(pin.number)")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .frame(width: 26, alignment: .trailing)
                        .foregroundStyle(groupColor)
                    Text(pin.name)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .frame(width: 70, alignment: .leading)
                    Text(pin.group)
                        .font(.system(size: 9))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                        .fill(Theme.glassCardFill.opacity(0.5))
                )
            }
        }
        .padding(Theme.spacingM)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
    }

    private var legend: some View {
        HStack(spacing: 16) {
            legendItem("电源", color: .red)
            legendItem("配置 (CC/SBU)", color: .blue)
            legendItem("SuperSpeed", color: .green)
            legendItem("USB 2.0 (DP/DN)", color: .orange)
        }
        .font(.system(size: 10))
    }

    private func legendItem(_ text: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 7, height: 7)
            Text(text).foregroundStyle(.secondary)
        }
    }
}

// MARK: - 液体检测视图（端口卡内嵌小卡片）

struct LiquidDetectionBadge: View {
    let state: LiquidDetectionState

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: state.present ? "drop.triangle.fill" : "drop")
                .font(.system(size: 10))
                .foregroundStyle(state.present ? .orange : .green)
            Text(state.present ? "液体检测：已检测到接触/污染" : "液体检测：正常")
                .font(.system(size: 10))
                .foregroundStyle(state.present ? .orange : .secondary)
            if state.irqCount > 0 {
                Text("IRQ \(state.irqCount)")
                    .font(.system(size: 9, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

// MARK: - 显示诊断（Display Diagnostics）

struct DisplayDiagnosticsView: View {
    let displays: [DisplayModeInfo]
    let adapters: [String]

    init(usbDeviceNames: [String]) {
        self.displays = DisplayDiagnostics.scanDisplays(usbDeviceNames: usbDeviceNames)
        self.adapters = DisplayDiagnostics.adapterNames(from: usbDeviceNames)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            header
            Divider().opacity(0.5)
            if displays.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(spacing: Theme.spacingL) {
                        ForEach(displays) { d in
                            displayCard(d)
                        }
                        if !adapters.isEmpty {
                            adapterBanner
                        }
                    }
                }
            }
        }
        .padding(Theme.spacingL)
        .frame(minWidth: 620, minHeight: 460)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                Image(systemName: "display")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("显示诊断")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("读取显示器实时显示模式，与 DisplayPort 链路承载能力对比，解释分辨率/刷新率受限原因。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(Theme.accent.opacity(0.08)).frame(width: 56, height: 56)
                Image(systemName: "display.slash")
                    .font(.system(size: 26))
                    .foregroundStyle(Theme.accent.opacity(0.7))
            }
            Text("未检测到活跃显示器")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var adapterBanner: some View {
        HStack(spacing: 6) {
            Image(systemName: "cable.connector")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
            Text("链路中发现可能的转接器/扩展坞：\(adapters.joined(separator: " · "))")
                .font(.system(size: 10))
                .foregroundStyle(.orange)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.spacingM)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                .fill(Color.orange.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.3), lineWidth: 1)
        )
    }

    private func displayCard(_ d: DisplayModeInfo) -> some View {
        let maxBw = max(max(d.bandwidthGbps, d.linkCapacityGbps), 0.1)
        let overload = d.bandwidthGbps > d.linkCapacityGbps + 0.01
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "display")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.accent)
                Text(d.name)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                if d.is5K || d.is6K {
                    Text(d.sizeLabel)
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(LinearGradient(colors: [.blue, .cyan], startPoint: .leading, endPoint: .trailing)))
                } else {
                    Text(d.sizeLabel)
                        .font(.system(size: 10, weight: .semibold, design: .rounded))
                        .foregroundStyle(.blue)
                }
                Spacer()
                Text(String(format: "%.1f Hz", d.refreshRate))
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.glassCardFill))
                    .overlay(Capsule().strokeBorder(Theme.glassBorder, lineWidth: 1))
            }

            Text(d.resolutionText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            VStack(spacing: 4) {
                HStack(spacing: 6) {
                    Text("模式带宽")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(String(format: "%.1f Gbps", d.bandwidthGbps))
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(overload ? .orange : .blue)
                    Spacer()
                    Text(String(format: "链路承载 ~%.1f Gbps", d.linkCapacityGbps))
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(overload ? .orange : .green)
                }
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Theme.glassCardFill)
                            .frame(width: geo.size.width, height: 6)
                        Capsule().fill(Color.blue.opacity(0.35))
                            .frame(width: geo.size.width * CGFloat(min(d.bandwidthGbps / maxBw, 1)), height: 6)
                        Capsule().fill(overload ? Color.orange : Color.green)
                            .frame(width: geo.size.width * CGFloat(min(d.linkCapacityGbps / maxBw, 1)), height: 6)
                    }
                }
                .frame(height: 6)
            }

            HStack(spacing: 6) {
                Image(systemName: d.dscRequired ? "waveform.badge.minus" : "checkmark.seal.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(d.dscRequired ? .purple : .green)
                Text("DSC 压缩：\(d.dscText)")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(d.dscRequired ? .purple : .green)
            }

            Text(d.verdict)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !d.adapters.isEmpty {
                Text("链路转接：\(d.adapters.joined(separator: " · "))")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
        }
        .padding(Theme.spacingL)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(
                    overload
                        ? LinearGradient(colors: [.orange.opacity(0.45), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                        : LinearGradient(colors: [.white.opacity(0.12), .clear], startPoint: .topLeading, endPoint: .bottomTrailing),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.glassShadow, radius: 6, y: 1)
    }
}

