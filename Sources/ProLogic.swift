import Foundation
import IOKit

// MARK: - Pro 业务逻辑：契约检查 / 电阻估算 / 协商诊断 / 历史指纹

enum ProLogic {

    /// 线缆电阻估算：R = (适配器输入电压 - 系统端电压) / 系统电流
    /// 数据来自 AppleSmartBattery：PowerDistribution.IPDInputVoltage 与
    /// PowerTelemetryData.SystemVoltageIn / SystemCurrentIn。
    // MARK: - 线缆电阻估算（中位数滤波）

    /// 最近有效样本数（毫欧姆），取中位数抗单点噪声
    private static let sampleLimit = 9
    private static var resistanceSamples: [Int] = []
    private static let resistanceLock = NSLock()

    /// 单点原始估算：R = (适配器输入电压 - 系统端电压) / 系统电流。
    /// 注意：IPDInputVoltage 是 PD 合约档位标称值（非实时实测），压差含全链路路径，
    /// 故单点值噪声大、且随电流变化漂移；对外统一走 estimateCableResistance 的中位数版本。
    private static func rawResistanceMilliohms(power: PowerState) -> Int? {
        let inputVolts = power.inputVoltageMV
        let systemVolts = power.systemVoltageInMV
        let systemCurrent = power.systemCurrentInMA
        guard inputVolts > 0, systemVolts > 0, systemCurrent > 500 else { return nil }
        let dv = inputVolts - systemVolts
        guard dv > 0 else { return nil }
        let r = dv / systemCurrent   // mV / mA = 欧姆
        return Int(r * 1000)
    }

    /// 线缆电阻估算：对最近多个有效单点样本取中位数，降低遥测噪声与瞬时波动影响；
    /// 电流过低（<1.5A）时压差信号弱、噪声占比高，标记低置信度。
    static func estimateCableResistance(power: PowerState) -> CableResistanceEstimate? {
        guard let mo = rawResistanceMilliohms(power: power) else { return nil }

        resistanceLock.lock()
        resistanceSamples.append(mo)
        if resistanceSamples.count > sampleLimit { resistanceSamples.removeFirst() }
        let sorted = resistanceSamples.sorted()
        let median = sorted[sorted.count / 2]
        resistanceLock.unlock()

        let lowConfidence = power.systemCurrentInMA < 1500
        let note: String
        if lowConfidence {
            note = String(format: "负载过低（%.2f A），估算偏差较大，仅供参考", power.systemCurrentInMA / 1000.0)
        } else if median <= 60 {
            note = "优良（≤60 mΩ，典型正品线缆）"
        } else if median <= 150 {
            note = "正常（60-150 mΩ）"
        } else {
            note = "偏高（>150 mΩ，可能线缆偏长或导体较细）"
        }
        return CableResistanceEstimate(ohms: Double(median) / 1000.0, milliohms: median, note: note, lowConfidence: lowConfidence)
    }

    /// 电阻不可估算时的原因（仅在已接入外部电源时返回说明；未接电源返回 nil，不打扰）。
    /// 用于 UI 如实展示数据源缺失 / 压差不足等原因，避免"不显示=没做"的误判。
    /// 注意：此函数不再调用 estimateCableResistance（避免污染滤波样本队列）。
    static func resistanceUnavailableReason(power: PowerState) -> String? {
        guard power.externalConnected else { return nil }
        let inputVolts = power.inputVoltageMV
        let systemVolts = power.systemVoltageInMV
        let systemCurrent = power.systemCurrentInMA
        if rawResistanceMilliohms(power: power) != nil { return nil }
        if inputVolts <= 0 {
            return "线缆电阻暂不可估算：未检测到适配器输入电压（IPDInputVoltage）"
        }
        if systemVolts <= 0 {
            return "线缆电阻暂不可估算：未检测到系统端进电遥测（SystemVoltageIn）"
        }
        if systemCurrent <= 500 {
            return String(format: "线缆电阻暂不可估算：系统电流过低（%.2f A）", systemCurrent / 1000.0)
        }
        if inputVolts - systemVolts <= 0 {
            return "线缆电阻暂不可估算：输入与系统端电压无压差"
        }
        return "线缆电阻暂不可估算"
    }

    /// 协商诊断：对比 Mac 端口 / 线缆 / 设备各自能力与实际协商结果。
    /// - Parameters:
    ///   - portLabel: 端口标签
    ///   - portMaxGbps: Mac 端口最大速率（Thunderbolt 控制器能力）
    ///   - cable: 线缆 e-marker 详情（可能 nil）
    ///   - devices: 已连接设备
    static func buildNegotiationDiagnostics(portLabel: String,
                                            portMaxGbps: Double?,
                                            cable: USBMonitor.CableEMarkerDetail?,
                                            devices: [USBDeviceInfo],
                                            negotiatedSpeedGbps: Double?) -> NegotiationDiagnosticsResult {
        var rows: [NegotiationRow] = []
        var weakRole: String?
        var summary = "链路正常"

        // 线缆支持标签：速度档位映射到 USB 协议名（40Gbps = USB4 Gen3 等）
        func cableSupportLabel(_ speedLabel: String) -> String {
            switch speedLabel {
            case "40 Gbps": return "USB4 (40 Gbps)"
            case "80 Gbps": return "USB4 Gen4 (80 Gbps)"
            case "20 Gbps": return "USB4 Gen2 (20 Gbps)"
            case "10 Gbps": return "USB3.2 Gen2 (10 Gbps)"
            case "5 Gbps": return "USB3.2 Gen1 (5 Gbps)"
            default: return speedLabel
            }
        }

        // 线缆行附注：保留原说明，并附上 e-marker 识别的厂商
        func cableNote(_ base: String?) -> String? {
            var parts: [String] = []
            if let base { parts.append(base) }
            if let name = cable?.vendorName { parts.append("厂商 \(name)") }
            return parts.isEmpty ? nil : parts.joined(separator: "，")
        }

        let portCap = portMaxGbps ?? 40.0 // 未知时按 USB4 40Gbps 估算
        let negotiated = negotiatedSpeedGbps ?? devices.compactMap(\.speedGbps).max()
        // MagSafe 为磁吸充电专用口，无 USB 数据链路，不参与数据协商对比
        let isMagSafePort = portLabel.contains("MagSafe")
        let portNegotiated = negotiated.map { "\(Int($0)) Gbps" } ?? "—"

        // --- Mac 端口行 ---
        if isMagSafePort {
            rows.append(NegotiationRow(role: "Mac 端口",
                                       supportsLabel: "充电专用（无数据链路）",
                                       negotiatedLabel: "—",
                                       isWeak: false,
                                       note: "MagSafe 磁吸充电口，不支持 USB 数据"))
        } else {
            let portSupport = portMaxGbps.map { "\(Int($0)) Gbps" } ?? "Thunderbolt/USB4"
            let portWeak = negotiated != nil && negotiated! > portCap
            rows.append(NegotiationRow(role: "Mac 端口",
                                       supportsLabel: portSupport,
                                       negotiatedLabel: portNegotiated,
                                       isWeak: portWeak,
                                       note: portWeak ? "协商速率高于端口能力，异常" : nil))
        }

        // --- 线缆行 ---
        // 仅当系统枚举到 e-marker（SOP' 节点）时才显示线缆行；
        // 读不到 e-marker 时（如 Mac 作为 UFP 接充电器）不显示，避免误导。
        if let cable {
            let cableCap: Double
            switch cable.speedLabel {
            case "5 Gbps": cableCap = 5
            case "10 Gbps": cableCap = 10
            case "20 Gbps": cableCap = 20
            case "40 Gbps": cableCap = 40
            case "80 Gbps": cableCap = 80
            default: cableCap = 0.48 // USB 2.0
            }
            let cableWeak = negotiated != nil && cableCap > 0 && cableCap < negotiated!
            // 线缆能力低于协商值（e-marker 与实测不符）也高亮
            if negotiated != nil && cableCap > 0 && cableCap < negotiated! {
                weakRole = "线缆"
                summary = "线缆 e-marker 声称 \(cable.speedLabel)，但链路协商到 \(Int(negotiated!)) Gbps，存在矛盾"
                rows.append(NegotiationRow(role: "线缆",
                                           supportsLabel: cableSupportLabel(cable.speedLabel),
                                           negotiatedLabel: portNegotiated,
                                           isWeak: true,
                                           note: cableNote("e-marker 与控制器交叉检查不一致")))
            } else if negotiated != nil && cableCap < portCap && cableCap < negotiated! {
                weakRole = "线缆"
                summary = "线缆限制数据速度：线缆支持 \(cableSupportLabel(cable.speedLabel))，端口可达 \(Int(portCap)) Gbps"
                rows.append(NegotiationRow(role: "线缆",
                                           supportsLabel: cableSupportLabel(cable.speedLabel),
                                           negotiatedLabel: portNegotiated,
                                           isWeak: true,
                                           note: cableNote("线缆是该链路的瓶颈")))
            } else {
                rows.append(NegotiationRow(role: "线缆",
                                           supportsLabel: cableSupportLabel(cable.speedLabel),
                                           negotiatedLabel: portNegotiated,
                                           isWeak: false,
                                           note: cableNote(nil),
                                           supportsValue: cableCap,
                                           negotiatedValue: negotiated))
            }
        }

        // --- 设备行 ---
        if let dev = devices.first {
            let devCap = dev.speedGbps
            let devSupport = devCap.map { "\(Int($0)) Gbps" } ?? dev.speedLabel
            let devWeak = devCap != nil && negotiated != nil && devCap! < portCap
            if devWeak {
                if weakRole == nil { weakRole = "设备" }
                summary = "设备最高支持 \(devSupport)，这是它自身上限，并非线缆问题"
                rows.append(NegotiationRow(role: "设备",
                                           supportsLabel: devSupport,
                                           negotiatedLabel: devCap.map { "\(Int($0)) Gbps" } ?? "—",
                                           isWeak: true,
                                           note: "设备已达自身最快速度"))
            } else {
                rows.append(NegotiationRow(role: "设备",
                                           supportsLabel: devSupport,
                                           negotiatedLabel: devCap.map { "\(Int($0)) Gbps" } ?? "—",
                                           isWeak: false,
                                           note: nil,
                                           supportsValue: devCap,
                                           negotiatedValue: devCap))
            }
        }

        // 默认汇总（无弱环节）
        if weakRole == nil {
            if isMagSafePort {
                summary = "MagSafe 充电口，仅供电，无数据协商"
            } else if let negotiated, negotiated >= portCap * 0.9 {
                summary = "全链路匹配，\(Int(negotiated)) Gbps 满速运行"
            } else if let negotiated {
                summary = "运行于 \(Int(negotiated)) Gbps"
            } else {
                summary = "链路正常（无高速数据链路）"
            }
        }

        return NegotiationDiagnosticsResult(portLabel: portLabel, rows: rows, weakRole: weakRole, summary: summary)
    }

    /// 生成线缆指纹：优先 e-marker VDO，回退到设备 VID:PID。
    static func fingerprint(for cable: USBMonitor.CableEMarkerDetail?) -> String? {
        if let cable { return cable.fingerprint }
        return nil
    }

    static func fingerprint(for device: USBDeviceInfo) -> String {
        String(format: "DEV:%04X:%04X", device.vendorID, device.productID)
    }

    /// 线缆历史匹配：返回匹配记录（若有）
    static func matchCable(cable: USBMonitor.CableEMarkerDetail?, device: USBDeviceInfo?, store: CableHistoryStore) -> CableRecord? {
        if let cable, let fp = fingerprint(for: cable) {
            return store.record(for: fp)
        }
        if let device {
            return store.record(for: fingerprint(for: device))
        }
        return nil
    }

    /// 使用结束后登记历史（健康事件 / 异常事件）
    static func recordCableUsage(cable: USBMonitor.CableEMarkerDetail?,
                                 device: USBDeviceInfo?,
                                 store: CableHistoryStore,
                                 portLabel: String,
                                 negotiatedWatts: Double,
                                 dataSpeed: String,
                                 healthy: Bool,
                                 anomaly: CableAnomalyRecord?,
                                 portFingerprint: String? = nil) {
        var fp: String?
        var vid: UInt16?
        var pid: UInt16?
        var speedLabel = "USB 2.0"
        var current = 3.0
        var maxWatts = 60
        var defaultName: String? = nil
        if let cable {
            fp = cable.fingerprint
            vid = cable.vendorVID
            pid = cable.productID
            speedLabel = cable.speedLabel
            current = cable.currentRating
            maxWatts = cable.maxWatts
        } else if let device {
            fp = Self.fingerprint(for: device)
            vid = device.vendorID
            pid = device.productID
            speedLabel = device.speedLabel
            current = Double(device.currentMA ?? 0) / 1000.0
        } else if let portFingerprint {
            // 充电器 / 未知线缆（无 e-marker 且无 USB 设备）：按物理端口建立指纹，允许保存充电线记录
            fp = portFingerprint
            defaultName = "\(portLabel) 线缆"
            if negotiatedWatts > 1 { maxWatts = Int(negotiatedWatts.rounded()) }
        }
        guard let fp else { return }
        store.recordUsage(fingerprint: fp,
                          name: defaultName,
                          vendorVID: vid,
                          productID: pid,
                          speedLabel: speedLabel,
                          currentRating: current,
                          maxWatts: maxWatts,
                          portLabel: portLabel,
                          negotiatedWatts: negotiatedWatts,
                          dataSpeed: dataSpeed,
                          healthy: healthy,
                          anomaly: anomaly)
    }
}
