import Foundation
import IOKit
import Combine

// MARK: - USBMonitor Pro 数据源扩展
// 只读 IOKit 查询：端口控制器健康计数、液体检测、完整 e-marker、PD 契约。

extension USBMonitor {

    // MARK: 轻量电源刷新（Pro 实时功率计量使用，不重枚举端口）

    func refreshPower() {
        power = readPowerState()
    }

    /// 生成当前功率样本（优先充电输入，回退电池总线）
    func currentPowerSample() -> PowerSample {
        let p = power
        let now = Date()
        // 充电输入（PowerDistribution）是最真实的“进电”功率
        if p.inputPowerMW > 0 && p.externalConnected {
            return PowerSample(
                timestamp: now,
                watts: p.inputPowerMW / 1000.0,
                amps: abs(p.inputCurrentMA) / 1000.0,
                volts: p.inputVoltageMV / 1000.0,
                source: "input"
            )
        }
        // 电池总线（Voltage/Amperage）
        return PowerSample(
            timestamp: now,
            watts: p.wattsNow,
            amps: abs(p.amperageMA) / 1000.0,
            volts: p.voltageMV / 1000.0,
            source: "battery"
        )
    }

    // MARK: 端口控制器快照

    struct PortControllerSnapshot {
        let index: Int
        let pdoValues: [UInt32]
        let activeRDO: UInt32?
        let attachCount: Int
        let detachCount: Int
        let shortDetectCount: Int
        let fetEnableFailCount: Int
        let hardResetCount: Int
        let surpriseNackCount: Int
        let vdoFailCount: Int
        let i2cErrorCount: Int
        let capMismatch: Bool
        let maxPowerW: Double
        let portMode: Int
        let ldcmIrqCount: Int
    }

    /// 读取 AppleSmartBattery 下所有端口控制器
    func readPortControllers() -> [PortControllerSnapshot] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        guard case let service = IOIteratorNext(iterator), service != 0 else { return [] }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return [] }

        guard let items = dict["PortControllerInfo"] as? [Any] else { return [] }
        var result: [PortControllerSnapshot] = []
        for (idx, item) in items.enumerated() {
            guard let d = item as? [String: Any] else { continue }
            let rawPDOs = (d["PortControllerPortPDO"] as? [Any]) ?? []
            let pdoValues: [UInt32] = rawPDOs.compactMap { v in
                if let n = v as? NSNumber { return UInt32(truncatingIfNeeded: n.uint64Value) }
                return nil
            }
            let activeRDO = (d["PortControllerActiveContractRdo"] as? NSNumber).map { UInt32(truncatingIfNeeded: $0.uint64Value) }
            let snap = PortControllerSnapshot(
                index: idx,
                pdoValues: pdoValues,
                activeRDO: activeRDO,
                attachCount: (d["PortControllerAttachCount"] as? NSNumber)?.intValue ?? 0,
                detachCount: (d["PortControllerDetachCount"] as? NSNumber)?.intValue ?? 0,
                shortDetectCount: (d["PortControllerShortDetectCount"] as? NSNumber)?.intValue ?? 0,
                fetEnableFailCount: (d["PortControllerInpFetEnFailCount"] as? NSNumber)?.intValue ?? 0,
                hardResetCount: (d["PortControllerHardResetCount"] as? NSNumber)?.intValue ?? 0,
                surpriseNackCount: (d["PortControllerSurpriseNackCount"] as? NSNumber)?.intValue ?? 0,
                vdoFailCount: (d["PortControllerVdoFailCount"] as? NSNumber)?.intValue ?? 0,
                i2cErrorCount: (d["PortControllerI2cErrCount"] as? NSNumber)?.intValue ?? 0,
                capMismatch: (d["PortControllerCapMismatch"] as? NSNumber)?.boolValue ?? false,
                maxPowerW: (d["PortControllerMaxPower"] as? NSNumber)?.doubleValue ?? 0,
                portMode: (d["PortControllerPortMode"] as? NSNumber)?.intValue ?? 0,
                ldcmIrqCount: (d["PortControllerIrqCntldcm"] as? NSNumber)?.intValue ?? 0
            )
            result.append(snap)
        }
        return result
    }

    /// 将控制器快照转为健康统计
    func healthStats(from snapshots: [PortControllerSnapshot]) -> [PortHealthStats] {
        snapshots.map { s in
            PortHealthStats(
                id: s.index,
                controllerIndex: s.index,
                attachCount: s.attachCount,
                detachCount: s.detachCount,
                shortDetectCount: s.shortDetectCount,
                fetEnableFailCount: s.fetEnableFailCount,
                hardResetCount: s.hardResetCount,
                surpriseNackCount: s.surpriseNackCount,
                vdoFailCount: s.vdoFailCount,
                i2cErrorCount: s.i2cErrorCount,
                capMismatch: s.capMismatch,
                maxPowerW: s.maxPowerW,
                portMode: s.portMode
            )
        }
    }

    // MARK: PD 契约（PDO + 活跃 RDO）

    /// 解析固定 PDO：返回 (volts, amps)
    private func decodeFixedPDO(_ pdo: UInt32) -> (Double, Double)? {
        guard (pdo >> 30) & 0x3 == 0 else { return nil } // Fixed PDO
        let volts = Double((pdo >> 10) & 0x3FF) * 0.05
        let amps = Double(pdo & 0x3FF) * 0.01
        guard volts > 0, amps > 0 else { return nil }
        return (volts, amps)
    }

    /// 从端口控制器读取当前 PD 契约信息（按物理口归属，不再全局串数）
    /// - Parameters:
    ///   - portIndex: TypeC 端口编号（实机 = PortControllerInfo 索引 0/1，与 TypeC PhyID 一致）
    ///   - isMagSafe: 是否 MagSafe 口（MagSafe 为 PortControllerInfo 末条控制器）
    func readPDContract(portIndex: Int?, isMagSafe: Bool) -> PDContractInfo {
        let snapshots = readPortControllers()
        guard !snapshots.isEmpty else { return PDContractInfo() }

        // 按端口归属：MagSafe 取末位控制器，TypeC 取自身索引控制器
        var chosen: PortControllerSnapshot? = isMagSafe ? snapshots.last : nil
        if !isMagSafe, let idx = portIndex {
            chosen = snapshots.first { $0.index == idx }
        }
        // 兜底：该控制器无快照时，优先选有活跃合约的控制器，其次选有 PDO 的控制器
        if chosen == nil {
            chosen = snapshots.first { ($0.activeRDO ?? 0) != 0 }
                ?? snapshots.first(where: { !$0.pdoValues.isEmpty })
        }
        guard let chosen else { return PDContractInfo() }

        var info = PDContractInfo()
        var activePos = 0
        if let rdo = chosen.activeRDO, rdo != 0 {
            // RDO: Object Position 位于 bit28-31（1-based）
            let pos28 = Int((rdo >> 28) & 0xF)
            let pos24 = Int((rdo >> 24) & 0x1F)
            activePos = (pos28 >= 1 && pos28 <= 7) ? pos28 : pos24
        }
        info.activePosition = activePos

        var profiles: [PDOProfile] = []
        for (i, pdo) in chosen.pdoValues.enumerated() {
            guard let decoded = decodeFixedPDO(pdo) else { continue }
            let (v, a) = decoded
            profiles.append(PDOProfile(volts: v, amps: a, watts: v * a, isActive: (i + 1) == activePos))
        }
        info.pdoList = profiles

        if let activeProfile = profiles.first(where: { $0.isActive }) {
            info.negotiatedVolts = activeProfile.volts
            info.negotiatedAmps = activeProfile.amps
        }
        return info
    }

    /// 从适配器 UsbHvcMenu 读取充电器广告档位（用于 PD 契约对比）
    func readAdapterPDOProfiles() -> [PDOProfile] {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        guard case let service = IOIteratorNext(iterator), service != 0 else { return [] }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return [] }

        guard let adapter = dict["AdapterDetails"] as? [String: Any],
              let menu = adapter["UsbHvcMenu"] as? [Any] else { return [] }

        var profiles: [PDOProfile] = []
        for item in menu {
            guard let d = item as? [String: Any] else { continue }
            let mv = (d["MaxVoltage"] as? NSNumber)?.doubleValue ?? 0
            let ma = (d["MaxCurrent"] as? NSNumber)?.doubleValue ?? 0
            guard mv > 0, ma > 0 else { continue }
            let v = mv / 1000.0
            let a = ma / 1000.0
            profiles.append(PDOProfile(volts: v, amps: a, watts: v * a, isActive: false))
        }
        return profiles
    }

    // MARK: 线缆 e-marker 详情（SOP'）

    struct CableEMarkerDetail {
        let fingerprint: String
        let vdos: [UInt32]
        let vendorVID: UInt16?
        let productID: UInt16?
        let speedLabel: String
        let currentRating: Double
        let maxWatts: Int
        let isEPR: Bool
        let lineDescription: String
        let rawVDOCable: UInt32?

        /// 厂商名（基于 VID 映射，未知返回 nil）
        var vendorName: String? { CableVendorDB.name(for: vendorVID) }
    }

    /// 读取端口下的 e-marker（返回完整指纹信息）
    /// 注意：e-marker 节点实际挂在 Port-USB-C@N/CC/SOP' 下（父链经 AppleTCControllerType10），
    /// 不在 AppleTypeCPhy 端口的直接子树上，必须全树查找 IOPortTransportComponentCCUSBPDSOPp，
    /// 再按 ParentPortNumber 归属端口。
    func readCableEMarker(for port: RawPort) -> CableEMarkerDetail? {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportComponentCCUSBPDSOPp"), &iter) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iter) }

        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            let parentPort =
                IORegistryEntryCreateCFProperty(service, "ParentPortNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
                ?? IORegistryEntryCreateCFProperty(service, "ParentBuiltInPortNumber" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            let hpmPort = parentPort?.intValue ?? Int.min
            // Apple Silicon：SOP' 的 ParentPortNumber 即 Type10 控制器 PortNumber（1 起），端口卡编号从 0 起，需 -1 换算。
            // 不能写 hpmPort == port.portNumber 的宽松分支——ParentPortNumber=1 会被 TypeC 1 误匹配。
            guard hpmPort - 1 == port.portNumber else { continue }
            if let detail = Self.parseEMarkerDetail(service: service) { return detail }
        }
        return nil
    }

    private static func parseEMarkerDetail(service: io_service_t) -> CableEMarkerDetail? {
        func read(_ key: String) -> Any? {
            IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
        }
        var metadata: [String: Any] = [:]
        if let raw = read("Metadata") as? [String: Any] {
            metadata = raw
        } else if let ns = read("Metadata") as? NSDictionary {
            for (k, v) in ns { if let ks = k as? String { metadata[ks] = v } }
        }
        let vdos: [UInt32] = ((metadata["VDOs"] as? [Any]) ?? []).compactMap { value in
            if let data = value as? Data, data.count >= 4 {
                return data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
            }
            if let num = value as? NSNumber { return UInt32(truncatingIfNeeded: num.uint64Value) }
            return nil
        }
        guard vdos.count >= 4 else { return nil }
        let cableVDO = vdos[3]
        let speedBits = Int(cableVDO & 0b111)
        let currentBits = Int((cableVDO >> 5) & 0b111)
        let epr = ((cableVDO >> 17) & 1) == 1

        // USB Type-C 2.2 / USB PD 3.1 Cable VDO B[2:0]：
        // 000=USB2.0 001=USB3.2 Gen1(5G) 010=USB3.2 Gen2/USB4 Gen2(20G)
        // 011=USB4 Gen3(40G) 100=USB4 Gen4(80G) 101..111=保留
        let speedLabel: String
        switch speedBits {
        case 0: speedLabel = "USB 2.0"
        case 1: speedLabel = "5 Gbps"
        case 2: speedLabel = "20 Gbps"
        case 3: speedLabel = "40 Gbps"
        case 4: speedLabel = "80 Gbps"
        default: speedLabel = "未知速度"
        }
        let current = currentBits == 0 ? 3.0 : 5.0
        let maxWatts = epr ? 240 : (current >= 5 ? 100 : 60)

        // VID 优先取 Metadata 中的 Vendor ID（实机验证更可靠），回退 ID Header VDO（vdo0）bit 16-31
        let idHeaderVDO = vdos[0]
        var vid: UInt16?
        if let n = metadata["Vendor ID"] as? NSNumber { vid = UInt16(truncatingIfNeeded: n.uint64Value) }
        if vid == nil { vid = UInt16((idHeaderVDO >> 16) & 0xFFFF) }
        // Product ID 同取 Metadata（与 VID 一致，回退 vdo0 bit 0-15）
        var productID: UInt16?
        if let n = metadata["Product ID"] as? NSNumber { productID = UInt16(truncatingIfNeeded: n.uint64Value) }
        if productID == nil { productID = UInt16(idHeaderVDO & 0xFFFF) }

        var fp = vdos.map { String(format: "%08X", $0) }.joined()
        if fp.isEmpty { fp = "UNKNOWN" }

        return CableEMarkerDetail(
            fingerprint: fp,
            vdos: vdos,
            vendorVID: vid,
            productID: productID,
            speedLabel: speedLabel,
            currentRating: current,
            maxWatts: maxWatts,
            isEPR: epr,
            lineDescription: "线缆 e-marker · \(speedLabel) · \(Int(current))A" + (epr ? " · EPR" : ""),
            rawVDOCable: cableVDO
        )
    }

    // MARK: 液体检测（LDCM）

    /// 读取液体检测状态：优先 TypeCPhy 子树 LDCM 属性，回退控制器中断计数
    func readLiquidDetection() -> LiquidDetectionState {
        var irqCount = 0
        for snap in readPortControllers() where snap.ldcmIrqCount > 0 {
            irqCount += snap.ldcmIrqCount
        }

        // 在 TypeCPhy / 端口子树中查找 LDCM 状态属性
        var present = false
        var rawStatus: String?
        var lastDetected: Date?

        var portIter: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleTypeCPhy"), &portIter) == KERN_SUCCESS {
            while case let service = IOIteratorNext(portIter), service != 0 {
                if let state = Self.scanLDCMProperties(service: service) {
                    present = present || state.0
                    rawStatus = rawStatus ?? state.1
                    if state.0 { lastDetected = Date() }
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(portIter)
        }
        // 控制器计数本身即视为“曾检测到液体”信号
        if irqCount > 0 {
            present = true
            if lastDetected == nil { lastDetected = Date() }
        }
        return LiquidDetectionState(present: present, lastDetected: lastDetected, irqCount: irqCount, rawStatus: rawStatus)
    }

    private static func scanLDCMProperties(service: io_service_t) -> (Bool, String?)? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }

        // 常见 LDCM 状态键
        let keys = ["LdcmState", "LDCMState", "LiquidDetectionState", "LiquidDetected", "LDCM", "LdcmStatus"]
        for key in keys {
            if let val = dict[key] {
                let str = String(describing: val)
                let active = str.lowercased().contains("contaminat") || str.lowercased().contains("liquid") || str.lowercased().contains("detect") && !str.contains("0")
                return (active, "\(key)=\(str)")
            }
        }
        return nil
    }
}
