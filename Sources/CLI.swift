import Foundation
import Darwin
import IOKit

// MARK: - PortLens CLI（命令行工具）
// 独立二进制，随 .app 打包于 Contents/Helpers/。
// 支持：默认摘要 / --monitor 实时功率遥测 / --monitor-json NDJSON /
//       --dashboard 全屏 TUI（Overview/Negotiation/Power 三屏）/
//       --pro 功能清单 / --version / --help

/// 无捕获的 SIGINT 处理器：恢复终端后退出（TUI 使用）
private func portlensSigintHandler(_ sig: Int32) {
    PortLensCLI.restoreTerminal()
    PortLensCLI.clearScreen()
    exit(130)
}

@main
struct PortLensCLI {

    static let version = "2.0.0"

    // MARK: - 入口

    static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--version") {
            print("PortLens CLI \(version)")
            return
        }
        if args.contains("--help") || args.contains("-h") {
            printHelp()
            return
        }
        if args.contains("--pro") {
            printProFeatures()
            return
        }
        if args.contains("--ports-json") {
            runPortsJSON()
            return
        }
        if args.contains("--monitor-json") {
            runMonitor(json: true)
            return
        }
        if args.contains("--monitor") {
            runMonitor(json: false)
            return
        }
        if args.contains("--dashboard") {
            runDashboard()
            return
        }
        runSummary()
    }

    // MARK: - 基础设施

    static func makeMonitor() -> USBMonitor {
        let monitor = USBMonitor()
        USBMonitor.shared = monitor
        monitor.start()
        return monitor
    }

    static func portLabel(_ card: PortCardModel) -> String {
        if card.isMagSafe { return "MagSafe" }
        return "TypeC \(card.portNumber ?? card.portIndex)"
    }

    static func cableHealth(_ card: PortCardModel) -> (tag: String, color: Int) {
        guard card.isConnected else { return ("未连接", 37) }
        if let fault = card.faultText, !fault.isEmpty { return ("异常", 31) }
        let banner = card.chargingBanner ?? ""
        if banner.localizedCaseInsensitiveContains("限制")
            || banner.localizedCaseInsensitiveContains("limiting")
            || banner.localizedCaseInsensitiveContains("limit") {
            return ("注意", 33)
        }
        return ("良好", 32)
    }

    /// 实时输入功率（W）：SystemPowerIn 优先（IPDInputPower 是 PMU 协商电流档×电压的恒定值，弃用）
    static func realtimeInputW(_ p: PowerState) -> Double {
        p.externalConnected && p.systemPowerInMW > 1 ? p.systemPowerInMW / 1000.0 : p.wattsNow
    }

    static func powerLine(_ p: PowerState) -> String {
        let watts = realtimeInputW(p)
        return String(format: "%@ %.1f W (适配器额定 %.0f W) · 电池 %d%%",
                      p.isCharging ? "充电中" : "未充电", watts, p.adapterWatts, p.batteryPercent)
    }

    // MARK: - 默认摘要

    static func runSummary() {
        let monitor = makeMonitor()
        Thread.sleep(forTimeInterval: 0.5)
        let p = monitor.power
        print("PortLens — 端口概览")
        print("电源: \(powerLine(p))")
        print("")
        if monitor.ports.isEmpty {
            print("未检测到端口")
        }
        for card in monitor.ports {
            print(portLabel(card))
            if card.isConnected {
                print("  ✓ \(card.headline)")
                if let banner = card.chargingBanner, !banner.isEmpty { print("  \(banner)") }
                if let cable = card.cableLine, !cable.isEmpty { print("  Cable: \(cable)") }
                if let device = card.deviceLine, !device.isEmpty { print("  Device: \(device)") }
                if let fault = card.faultText, !fault.isEmpty { print("  ! \(fault)") }
            } else {
                print("  - \(card.headline)")
                if let cable = card.cableLine, !cable.isEmpty { print("  Cable: \(cable)") }
                if let spec = card.cableSpec, !spec.isEmpty { print("  Spec: \(spec)") }
            }
            print("")
        }
        print("Pro 功能可用：--monitor / --monitor-json / --dashboard / --pro")
    }

    // MARK: - 端口 JSON（含 USB-IF XID / 认证 / 信任 / Active transports / Thunderbolt fabric）

    static func runPortsJSON() {
        let monitor = makeMonitor()
        Thread.sleep(forTimeInterval: 0.5)
        var portsArray: [[String: Any]] = []
        for card in monitor.ports {
            var obj: [String: Any] = [
                "port": card.isMagSafe ? "MagSafe" : "TypeC \(card.portNumber ?? card.portIndex)",
                "connected": card.isConnected,
                "headline": card.headline,
                "certification": (card.certificationManufacturer ?? card.certification ?? "") as Any,
                "xid_raw": (card.xidRaw.map { String(format: "0x%04X", $0) } ?? "") as Any,
                "trust_warning": (card.trustWarning ?? "") as Any,
                "active_transports": card.activeTransports,
            ]
            if let cable = card.cableLine, !cable.isEmpty { obj["cable"] = cable }
            if let device = card.deviceLine, !device.isEmpty { obj["device"] = device }
            if let spec = card.cableSpec, !spec.isEmpty { obj["spec"] = spec }
            if let fault = card.faultText, !fault.isEmpty { obj["fault"] = fault }
            if let banner = card.chargingBanner, !banner.isEmpty { obj["charging_banner"] = banner }
            if !card.connectedDevices.isEmpty {
                obj["devices"] = card.connectedDevices.map { (d: ConnectedDevice) -> [String: Any] in
                    var dObj: [String: Any] = [
                        "kind": d.kind.rawValue,
                        "summary": d.summary,
                        "icon": d.icon,
                        "vid": d.vid.map { String(format: "0x%04X", $0) } ?? "",
                        "pid": d.pid.map { String(format: "0x%04X", $0) } ?? "",
                    ]
                    if let detail = d.detail { dObj["detail"] = detail }
                    if let via = d.viaText { dObj["via"] = via }
                    if d.hops > 0 { dObj["hops"] = d.hops }
                    return dObj
                }
            }
            portsArray.append(obj)
        }
        let fabricObj: [String: Any] = [
            "switches": monitor.fabric.hops.count,
            "hops": monitor.fabric.hops.map { ["depth": $0.depth, "name": $0.name, "lane_speed_gbps": $0.laneSpeedGbps, "generation": $0.generation] },
            "tunnels": monitor.fabric.tunnels.map { ["name": $0.name, "protocol": $0.protocolName, "active": $0.isActive] },
        ]
        let payload: [String: Any] = [
            "ports": portsArray,
            "fabric": fabricObj,
        ]
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]),
           let str = String(data: data, encoding: .utf8) {
            print(str)
        } else {
            fputs("error: JSON 序列化失败\n", stderr)
            exit(2)
        }
    }

    // MARK: - 实时功率遥测

    static func runMonitor(json: Bool) {
        let monitor = makeMonitor()
        if !json {
            print("PortLens 实时功率遥测（Ctrl+C 退出）")
            print("时间                       功率     电流    电压   来源")
        }
        let formatter = ISO8601DateFormatter()
        while true {
            monitor.refreshPower()
            let s = monitor.currentPowerSample()
            let p = monitor.power
            if json {
                // 手动拼接 NDJSON（两位小数，避免浮点长尾）
                let watts = String(format: "%.2f", (s.watts * 100).rounded() / 100)
                let amps = String(format: "%.3f", (s.amps * 1000).rounded() / 1000)
                let volts = String(format: "%.2f", (s.volts * 100).rounded() / 100)
                let inputW = String(format: "%.2f", (realtimeInputW(p) * 100).rounded() / 100)
                let line = "{\"ts\":\"\(formatter.string(from: s.timestamp))\",\"watts\":\(watts),\"amps\":\(amps),\"volts\":\(volts),\"source\":\"\(s.source)\",\"adapter_watts\":\(Int(p.adapterWatts)),\"battery_percent\":\(p.batteryPercent),\"charging\":\(p.isCharging),\"external_connected\":\(p.externalConnected),\"input_power_w\":\(inputW),\"input_voltage_mv\":\(p.inputVoltageMV),\"input_current_ma\":\(p.inputCurrentMA),\"system_voltage_mv\":\(p.systemVoltageInMV),\"system_current_ma\":\(p.systemCurrentInMA)}"
                print(line)
                fflush(stdout)
            } else {
                print(String(format: "%@  %6.1f W  %5.2f A  %5.1f V  %@",
                             formatter.string(from: s.timestamp), s.watts, s.amps, s.volts, s.source))
                print(String(format: "  充电: %@  外部电源: %@  电池: %d%%  适配器额定: %.0f W  输入功率: %.1f W",
                             p.isCharging ? "是" : "否",
                             p.externalConnected ? "已连接" : "未连接",
                             p.batteryPercent, p.adapterWatts,
                             realtimeInputW(p)))
                fflush(stdout)
            }
            Thread.sleep(forTimeInterval: 2)
        }
    }

    // MARK: - Terminal Dashboard（TUI）

    // ANSI 输出到 stdout
    static func emit(_ s: String) {
        let bytes = Array(s.utf8)
        bytes.withUnsafeBufferPointer { _ = write(STDOUT_FILENO, $0.baseAddress, $0.count) }
    }

    static func clearScreen() {
        emit("\u{1B}[2J\u{1B}[H\u{1B}[0m")
    }

    static func runDashboard() {
        guard isatty(STDOUT_FILENO) == 1, isatty(STDIN_FILENO) == 1 else {
            fputs("error: --dashboard 需要交互式终端（SSH/tmux 环境可用）\n", stderr)
            exit(2)
        }
        let monitor = makeMonitor()
        setRawMode()
        signal(SIGINT, portlensSigintHandler)
        defer {
            restoreTerminal()
            clearScreen()
        }
        _ = fcntl(STDIN_FILENO, F_SETFL, O_NONBLOCK)

        var screen = 0
        var running = true
        while running {
            monitor.refresh()
            render(monitor: monitor, screen: screen)
            var buf = [UInt8](repeating: 0, count: 32)
            while true {
                let n = read(STDIN_FILENO, &buf, 32)
                if n <= 0 { break }
                for b in buf[0..<Int(n)] {
                    if b == 9 { screen = (screen + 1) % 3 }              // Tab
                    else if b == 113 || b == 3 { running = false }        // q / Ctrl+C
                }
            }
            Thread.sleep(forTimeInterval: 0.8)
        }
    }

    static func render(monitor: USBMonitor, screen: Int) {
        let titles = ["Overview", "Negotiation", "Power"]
        emit("\u{1B}[2J\u{1B}[H")
        emit("\u{1B}[1;36mPortLens Terminal Dashboard — \(titles[screen])\u{1B}[0m")
        emit("   (Tab: 切换屏幕 · q: 退出)\n")
        emit("\u{1B}[90m" + String(repeating: "─", count: 76) + "\u{1B}[0m\n")
        switch screen {
        case 0: renderOverview(monitor)
        case 1: renderNegotiation(monitor)
        default: renderPower(monitor)
        }
    }

    static func renderOverview(_ monitor: USBMonitor) {
        let p = monitor.power
        emit("系统: ")
        if p.externalConnected {
            emit("\u{1B}[32m外部电源 ✓\u{1B}[0m")
        } else {
            emit("\u{1B}[90m外部电源 ✗\u{1B}[0m")
        }
        emit(" | \(powerLine(p))\n\n")
        if monitor.ports.isEmpty { emit("未检测到端口\n"); return }
        for card in monitor.ports {
            let h = cableHealth(card)
            emit("\(portLabel(card))  [\u{1B}[\(h.color)m\(h.tag)\u{1B}[0m]  \(card.headline)\n")
            if let banner = card.chargingBanner, !banner.isEmpty { emit("  充电: \(banner)\n") }
            if let cable = card.cableLine, !cable.isEmpty { emit("  线缆: \(cable)\n") }
            if let spec = card.cableSpec, !spec.isEmpty { emit("  规格: \(spec)\n") }
            if let device = card.deviceLine, !device.isEmpty { emit("  设备: \(device)\n") }
            if let fault = card.faultText, !fault.isEmpty { emit("  \u{1B}[31m⚠ \(fault)\u{1B}[0m\n") }
            emit("\n")
        }
    }

    static func renderNegotiation(_ monitor: USBMonitor) {
        var has = false
        for card in monitor.ports where card.isConnected {
            has = true
            let cable = monitor.eMarkerDetail(portIndex: card.portNumber ?? card.portIndex)
            let devices = card.devices
            let negotiated = devices.compactMap(\.speedGbps).max()
            let result = ProLogic.buildNegotiationDiagnostics(
                portLabel: portLabel(card),
                portMaxGbps: nil,
                cable: cable,
                devices: devices,
                negotiatedSpeedGbps: negotiated
            )
            emit("\u{1B}[1;33m\(result.portLabel)\u{1B}[0m")
            if let weak = result.weakRole {
                emit("  \u{1B}[1;31m弱环节: \(weak)\u{1B}[0m")
            } else {
                emit("  \u{1B}[1;32m全链路匹配\u{1B}[0m")
            }
            emit("\n  说明: \(result.summary)\n")
            for row in result.rows {
                emit("  · \(row.role): 支持 \(row.supportsLabel) | 协商 \(row.negotiatedLabel)")
                if let note = row.note { emit("（\(note)）") }
                emit("\n")
            }
            emit("\n")
        }
        if !has { emit("暂无已连接端口\n") }
    }

    static func renderPower(_ monitor: USBMonitor) {
        let p = monitor.power
        emit("系统功率输入\n")
        emit(String(format: "  当前: %.1f W  (%.2f A @ %.1f V)\n",
                    realtimeInputW(p),
                    p.externalConnected && p.systemPowerInMW > 1 ? abs(p.systemCurrentInMA) / 1000.0 : abs(p.inputCurrentMA) / 1000.0,
                    p.externalConnected && p.systemPowerInMW > 1 ? p.systemVoltageInMV / 1000.0 : p.inputVoltageMV / 1000.0))
        emit(String(format: "  适配器额定: %.0f W  充电中: %@  电池: %d%%\n\n",
                    p.adapterWatts, p.isCharging ? "是" : "否", p.batteryPercent))
        if p.systemVoltageInMV > 0 {
            emit(String(format: "  系统端进电: %.1f V / %.2f A  →  估算线缆电阻: %@\n\n",
                        p.systemVoltageInMV / 1000.0,
                        abs(p.systemCurrentInMA) / 1000.0,
                        ProLogic.estimateCableResistance(power: p)?.formatted ?? "—"))
        }
        emit("端口 PD 契约\n")
        var has = false
        for card in monitor.ports where card.isConnected {
            has = true
            emit("\(portLabel(card)): ")
            if let active = card.pdoList?.first(where: { $0.isActive }) {
                emit(String(format: "\u{1B}[32mPDO 活动   %.1fV · %.2fA = %.1fW\u{1B}[0m\n",
                            active.volts, active.amps, active.watts))
            } else if let pdoList = card.pdoList, !pdoList.isEmpty {
                emit("无活动契约（PDO: \(pdoList.map { String(format: "%.0fV", $0.volts) }.joined(separator: "/"))）\n")
            } else {
                emit("无 PDO 信息\n")
            }
        }
        if !has { emit("暂无已连接端口\n") }
    }

    // MARK: - termios raw mode

    static var savedTermios = termios()
    static var savedTermiosValid = false

    static func setRawMode() {
        var t = termios()
        guard tcgetattr(STDIN_FILENO, &t) == 0 else { return }
        savedTermios = t
        savedTermiosValid = true
        var raw = t
        raw.c_lflag &= ~(tcflag_t(ECHO) | tcflag_t(ICANON))
        let ccSize = MemoryLayout.size(ofValue: raw.c_cc)
        withUnsafeMutablePointer(to: &raw.c_cc) { ptr in
            ptr.withMemoryRebound(to: UInt8.self, capacity: ccSize) { bp in
                bp[Int(VMIN)] = 0
                bp[Int(VTIME)] = 0
            }
        }
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &raw)
    }

    static func restoreTerminal() {
        guard savedTermiosValid else { return }
        _ = tcsetattr(STDIN_FILENO, TCSANOW, &savedTermios)
        savedTermiosValid = false
    }

    // MARK: - 功能清单与帮助

    static func printProFeatures() {
        print("""
        PortLens Pro 功能
        ─────────────────────────────────────
        第一批:
          · 实时功率计量与 PD 契约检查
          · Power Monitor 系统功率输入实时图
          · Negotiation Diagnostics 协商诊断（Mac/线缆/设备三方对比）
          · 端口健康计数器与线缆电阻估算
          · 线缆历史（Saved Cables）
          · 引脚图与液体检测
          · Pro 独立窗口
        第二批:
          · Display Diagnostics 显示诊断（5K/6K 真实分辨率、DSC 确认、转接器识别）
          · Terminal Dashboard 终端仪表盘（Overview/Negotiation/Power 三屏 TUI）
          · CLI 命令行工具（--monitor / --monitor-json / --dashboard）
        安装位置: PortLens.app/Contents/Helpers/portlens
        """)
    }

    static func printHelp() {
        print("""
        PortLens CLI \(version) — USB-C 端口与线缆诊断

        用法:
          portlens                          端口摘要（人读）
          portlens --monitor                Pro: 实时功率遥测（Ctrl+C 退出）
          portlens --monitor-json           Pro: 实时功率遥测 NDJSON 流
          portlens --dashboard              Pro: 全屏终端仪表盘（Tab 切换，q 退出）
          portlens --pro                    显示 Pro 功能清单
          portlens --version                版本信息
          portlens --help                   本帮助

        说明: CLI 随 .app 打包于 Contents/Helpers/，可用以下命令加入 PATH:
          ln -s /Applications/PortLens.app/Contents/Helpers/portlens /usr/local/bin/portlens
        """)
    }
}
