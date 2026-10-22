import SwiftUI
import AppKit

// MARK: - Pro 功能统一入口

enum ProIntegration {

    /// 打开 Power Monitor（独立窗口）
    static func openPowerMonitor(monitor: USBMonitor) {
        let store: PowerMonitorStore
        if let existing = monitor.powerStore {
            store = existing
        } else {
            let s = PowerMonitorStore()
            s.monitor = monitor
            monitor.powerStore = s
            store = s
        }
        ProWindowManager.shared.openWindow(
            id: "power-monitor",
            title: "Power Monitor",
            content: PowerMonitorView(powerStore: store, monitor: monitor),
            width: 640, height: 620
        )
    }

    /// 打开协商诊断（独立窗口）
    static func openNegotiationDiagnostics(monitor: USBMonitor, store: CableHistoryStore) {
        ProWindowManager.shared.openWindow(
            id: "negotiation-diagnostics",
            title: "Negotiation Diagnostics",
            content: NegotiationDiagnosticsView(monitor: monitor, cableStore: store),
            width: 660, height: 500
        )
    }

    /// 打开 Saved Cables（独立窗口）
    static func openSavedCables(store: CableHistoryStore, monitor: USBMonitor) {
        ProWindowManager.shared.openWindow(
            id: "saved-cables",
            title: "Saved Cables",
            content: SavedCablesView(cableStore: store),
            width: 560, height: 480
        )
    }

    /// 打开引脚图（独立窗口）
    static func openPinDiagrams() {
        ProWindowManager.shared.openWindow(
            id: "pin-diagrams",
            title: "Pin Diagrams",
            content: PinDiagramView(),
            width: 480, height: 560
        )
    }

    /// 打开显示诊断（独立窗口）
    static func openDisplayDiagnostics() {
        let deviceNames = (USBMonitor.shared?.ports ?? []).flatMap { $0.devices.map(\.displayName) }
        ProWindowManager.shared.openWindow(
            id: "display-diagnostics",
            title: "Display Diagnostics",
            content: DisplayDiagnosticsView(usbDeviceNames: deviceNames),
            width: 640, height: 520
        )
    }

    /// 端口卡判定：是否已保存的线缆（按 e-marker 指纹，回退设备 VID:PID）
    static func savedCableName(for card: PortCardModel, monitor: USBMonitor, store: CableHistoryStore) -> String? {
        guard let match = matchedRecord(for: card, store: store) else { return nil }
        return match.name
    }

    /// 端口健康：按控制器索引匹配到当前端口卡
    static func healthForCard(_ card: PortCardModel, cache: [PortHealthStats], cardCount: Int) -> PortHealthStats? {
        guard !cache.isEmpty else { return nil }
        // 端口卡顺序与控制器索引对齐（MagSafe 一般排最后/单独索引）
        let idx = card.portIndex
        return cache.first { $0.controllerIndex == idx } ?? (idx < cache.count ? cache[idx] : nil)
    }

    /// 保存当前端口的线缆到历史库（无则新建，已存在则记录一次使用）
    static func saveCurrentCable(for card: PortCardModel, monitor: USBMonitor, store: CableHistoryStore) {
        let cable = monitor.eMarkerDetail(portIndex: card.portNumber ?? card.portIndex)
        let device = card.devices.first
        let negotiatedWatts = monitor.power.inputPowerMW > 0 ? monitor.power.inputPowerMW / 1000.0 : monitor.power.wattsNow
        let dataSpeed = device?.speedLabel ?? cable?.speedLabel ?? "USB 2.0"
        // 充电器线缆无 e-marker 且无 USB 设备时，用物理端口指纹兜底（保证"保存"按钮真正写盘）
        let portFP = cable == nil && device == nil ? "PORT:\(cardLabel(for: card))" : nil
        ProLogic.recordCableUsage(
            cable: cable,
            device: device,
            store: store,
            portLabel: cardLabel(for: card),
            negotiatedWatts: negotiatedWatts,
            dataSpeed: dataSpeed,
            healthy: true,
            anomaly: nil,
            portFingerprint: portFP
        )
    }

    static func cardLabel(for card: PortCardModel) -> String {
        if card.isMagSafe { return "MagSafe \(card.portNumber ?? 0)" }
        return "USB-C \(card.portNumber ?? 0)"
    }

    private static func matchedRecord(for card: PortCardModel, store: CableHistoryStore) -> CableRecord? {
        // 仅当读到 e-marker（SOP' 节点）时才匹配线缆历史并显示名称；
        // 无 e-marker 时不做设备/端口指纹回退，避免把设备或端口信息误当"线缆识别"展示。
        guard let cable = USBMonitor.shared?.eMarkerDetail(portIndex: card.portNumber ?? card.portIndex),
              let fp = ProLogic.fingerprint(for: cable) else { return nil }
        return store.record(for: fp)
    }
}

// MARK: - 端口卡 Pro 行（PD 契约检查 + Saved Cable 判定）

struct PortCardProRow: View {
    let card: PortCardModel
    let savedCableName: String?
    let contract: PDContractInfo
    @ObservedObject var monitor: USBMonitor
    @ObservedObject var cableStore: CableHistoryStore

    var body: some View {
        if card.isConnected {
            VStack(alignment: .leading, spacing: 4) {
                Divider().opacity(0.4)
                HStack(spacing: 6) {
                    Image(systemName: verdict.matches ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(verdict.matches ? .green : .orange)
                    Text(verdict.text)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                HStack(spacing: 6) {
                    Image(systemName: "bookmark")
                        .font(.system(size: 10))
                        .foregroundStyle(.purple)
                    if let name = savedCableName {
                        Text("已保存线缆：\(name)")
                            .font(.system(size: 10))
                            .foregroundStyle(.purple)
                    } else {
                        Text("未保存线缆")
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                        Button("保存") {
                            ProIntegration.saveCurrentCable(for: card, monitor: monitor, store: cableStore)
                        }
                        .buttonStyle(.borderless)
                        .controlSize(.mini)
                        .foregroundStyle(.blue)
                    }
                    Spacer()
                    if contract.activePosition > 0, let w = contract.negotiatedWatts {
                        Text("PDO #\(contract.activePosition) · \(Int(w))W")
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 8)
        }
    }

    private var verdict: (matches: Bool, text: String) {
        let cableMaxWatts = monitor.eMarkerDetail(portIndex: card.portNumber ?? card.portIndex)?.maxWatts
        return contract.capabilityVerdict(
            adapterWatts: monitor.power.adapterWatts,
            chargingWatts: monitor.power.wattsNow,
            isCharging: monitor.power.isCharging,
            fullyCharged: monitor.power.fullyCharged,
            cableMaxWatts: cableMaxWatts
        )
    }
}
