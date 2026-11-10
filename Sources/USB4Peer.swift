import Foundation
import IOKit

// MARK: - USB4 / Thunderbolt 对端设备（PCIe 隧道）

/// USB4 / Thunderbolt 对端设备。
///
/// 背景：USB4 NVMe 硬盘盒、USB4 扩展坞等设备走 **PCIe 隧道**，协议层不产生任何 USB 设备，
/// 因此 `IOUSBHostDevice` / `IOUSBDevice` 枚举结果为空，仅靠 USB 设备树会误报"无设备连接"。
/// 系统实际只在 IOPort 平面留下 `IOPortTransportStateCIO` 节点，其中承载：
/// - `Device Vendor Name` / `Device Model Name` / `Device Model ID`：对端设备身份（如 ASMedia 246x）
/// - `Generation`：USB4 代数（3 = Gen3，40 Gbps）
/// - `TunneledTransportsProvisioned`：已建隧道协议（`PCIe` / `USB3` / `DisplayPort`）
/// - `ParentPortNumber`：所属 Type10 控制器端口（1 起，端口卡编号需 -1 换算）
struct USB4Peer: Identifiable, Equatable {
    let id: UInt64
    let portNumber: Int?            // TypeC 端口编号（0 起）
    let vendorName: String
    let modelName: String
    let modelID: Int?
    let vendorID: Int?
    let generation: Int?            // USB4 代数
    let provisioned: [String]       // 已建隧道协议
    let supported: [String]         // 端口支持的隧道协议
    let isActive: Bool

    /// "ASMedia 246x"
    var displayName: String {
        let v = vendorName.trimmingCharacters(in: .whitespacesAndNewlines)
        let m = modelName.trimmingCharacters(in: .whitespacesAndNewlines)
        if v.isEmpty && m.isEmpty { return "USB4 设备" }
        if m.isEmpty { return v }
        if v.isEmpty { return m }
        return "\(v) \(m)"
    }

    var generationLabel: String {
        switch generation {
        case 2: return "USB4 Gen2"
        case 3: return "USB4 Gen3"
        case 4: return "USB4 Gen4"
        default: return "USB4"
        }
    }

    /// 代数对应总带宽（对称模式）：Gen2 = 20 / Gen3 = 40 / Gen4 = 80 Gbps
    var speedGbps: Int? {
        switch generation {
        case 2: return 20
        case 3: return 40
        case 4: return 80
        default: return nil
        }
    }

    /// "PCIe 隧道 · USB4 Gen3 · 40 Gbps"
    var tunnelSummary: String {
        var parts: [String] = []
        if !provisioned.isEmpty {
            parts.append(provisioned.map { "\($0) 隧道" }.joined(separator: " / "))
        }
        parts.append(generationLabel)
        if let g = speedGbps { parts.append("\(g) Gbps") }
        return parts.joined(separator: " · ")
    }

    /// 活跃传输类型（用于端口卡的 Active transports 行）
    var activeTransports: [String] {
        var out: [String] = []
        if provisioned.contains("PCIe") { out.append("PCIe") }
        if provisioned.contains("USB3") { out.append("USB 3") }
        if provisioned.contains("DisplayPort") { out.append("DisplayPort") }
        if out.isEmpty { out.append("Thunderbolt") }
        return out
    }

    /// 技术细节行（设置"显示技术细节"时展示）
    var techDetail: String? {
        var parts: [String] = []
        if let vid = vendorID { parts.append(String(format: "VID 0x%04X", vid)) }
        if let mid = modelID { parts.append(String(format: "Model ID 0x%04X", mid)) }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }
}

// MARK: - 外置卷（USB4 NVMe 硬盘盒）

extension USB4PeerReader {

    /// 外置可浏览卷摘要（如 "新加卷 · 931 GB"），用于证明 PCIe 隧道已打通到存储层。
    /// 走 /Volumes 枚举而非端口映射：PCIe 隧道下 IOMedia 无法可靠回溯到物理端口，故按"外置卷"口径呈现。
    static func externalVolumesLine() -> String? {
        let keys: [URLResourceKey] = [.volumeIsInternalKey, .volumeIsBrowsableKey, .volumeTotalCapacityKey, .volumeNameKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: "/Volumes"),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        ) else { return nil }

        var parts: [String] = []
        for url in urls {
            guard let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
            if v.volumeIsInternal == true { continue }
            guard v.volumeIsBrowsable != false else { continue }
            let name = v.volumeName ?? url.lastPathComponent
            if let cap = v.volumeTotalCapacity {
                parts.append("\(name) · \(formatCapacity(cap))")
            } else {
                parts.append(name)
            }
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " / ")
    }

    private static func formatCapacity(_ bytes: Int) -> String {
        let gb = Double(bytes) / 1_000_000_000.0
        if gb >= 1000 { return String(format: "%.1f TB", gb / 1000.0) }
        return String(format: "%.0f GB", gb)
    }
}

// MARK: - 读取

enum USB4PeerReader {

    /// 读取全树 `IOPortTransportStateCIO` 节点，按 TypeC 端口编号（0 起）索引返回。
    /// 仅返回有实际对端（设备名非空或已建隧道）且 `Active` 的节点。
    static func readPeers() -> [Int: USB4Peer] {
        var result: [Int: USB4Peer] = [:]
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportStateCIO"), &iter) == KERN_SUCCESS else {
            return [:]
        }
        defer { IOObjectRelease(iter) }

        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }

            func read(_ key: String) -> Any? {
                IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
            }

            let parentPort = (read("ParentPortNumber") as? NSNumber)
                ?? (read("ParentBuiltInPortNumber") as? NSNumber)
            guard let pp = parentPort?.intValue else { continue }

            let vendor = (read("Device Vendor Name") as? String) ?? ""
            let model = (read("Device Model Name") as? String) ?? ""
            let provisioned = (read("TunneledTransportsProvisioned") as? [String]) ?? []
            let supported = (read("TunneledTransportsSupported") as? [String]) ?? []
            let active = (read("Active") as? NSNumber)?.boolValue ?? true

            // 空口：既无设备身份也未建隧道，跳过（避免把空端口误判为已连接）
            guard active, !(vendor.isEmpty && model.isEmpty && provisioned.isEmpty) else { continue }

            var rid: UInt64 = 0
            IORegistryEntryGetRegistryEntryID(service, &rid)

            let peer = USB4Peer(
                id: rid,
                portNumber: pp - 1,   // Type10 控制器 1 起 → 端口卡 0 起
                vendorName: vendor,
                modelName: model,
                modelID: (read("Device Model ID") as? NSNumber)?.intValue,
                vendorID: (read("Vendor ID") as? NSNumber)?.intValue,
                generation: (read("Generation") as? NSNumber)?.intValue,
                provisioned: provisioned,
                supported: supported,
                isActive: active
            )
            // 同端口多个 CIO 节点时保留信息更完整的一个
            if let old = result[peer.portNumber ?? -1], old.provisioned.count >= peer.provisioned.count, !old.vendorName.isEmpty {
                continue
            }
            result[peer.portNumber ?? -1] = peer
        }
        return result
    }
}
