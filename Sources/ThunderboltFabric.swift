import Foundation
import IOKit

// MARK: - Thunderbolt fabric 读取

/// Thunderbolt fabric：每 lane 速度、代数（TB3/TB4/TB5）、多跳 switch 拓扑、
/// 活跃 tunnel 及其承载协议。全部为只读 IORegistry 遍历，无轮询。
struct ThunderboltFabric: Equatable {
    struct Hop: Identifiable, Equatable {
        let id: String
        let depth: Int
        let name: String
        let laneSpeedGbps: Int      // 每 lane Gbps（40 = TB3/TB4 单 lane；80 = TB5）
        let generation: String      // "TB1"/"TB2"/"TB3"/"TB4"/"TB5"/"—"
        let children: [Hop]
    }

    struct Tunnel: Identifiable, Equatable {
        let id: String
        let name: String
        let protocolName: String
        let isActive: Bool
    }

    var hops: [Hop] = []
    var tunnels: [Tunnel] = []
    var detected: Bool { !hops.isEmpty }

    /// 端口是否有 Thunderbolt 能力（任一 hop 存在）
    var generationSummary: String {
        let gens = Set(hops.flatMap { flatten($0) }.map(\.generation).filter { $0 != "—" })
        if gens.isEmpty { return "未检测到" }
        return gens.sorted().joined(separator: "/")
    }

    private func flatten(_ hop: Hop) -> [Hop] {
        [hop] + hop.children.flatMap { flatten($0) }
    }

    /// 活跃 tunnel 协议摘要
    var activeTunnelSummary: String {
        let active = tunnels.filter(\.isActive).map(\.protocolName)
        guard !active.isEmpty else { return "无活跃 tunnel" }
        return active.joined(separator: " · ")
    }
}

enum ThunderboltFabricReader {

    /// 从 IORegistry 读取当前 Thunderbolt fabric。
    /// 数据来源：IOThunderboltSwitch（拓扑跳）、IOThunderboltPort / 端口属性
    /// （每 lane 速率）、IOThunderboltTunnel 及子类（tunnel 与协议）。
    static func readFabric() -> ThunderboltFabric {
        var fabric = ThunderboltFabric()
        fabric.hops = readSwitches()
        fabric.tunnels = readTunnels()
        return fabric
    }

    // MARK: - Switch 拓扑

    private static func readSwitches() -> [ThunderboltFabric.Hop] {
        var services: [(service: io_service_t, name: String, depth: Int)] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOThunderboltSwitch"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            services.append((service, entryName(of: service), 0))
            IOObjectRelease(service)
        }
        guard !services.isEmpty else { return [] }

        // 多跳拓扑：每个 switch 通过 "Parent Port" / 父 switch 链确定深度。
        // IORegistry 服务平面中 IOThunderboltSwitch 通过 IOThunderboltPort 级联。
        // 简化实现：按父链向上计数确定深度，构建 hop 树。
        let rootDepths = computeDepths(services)
        var hops: [ThunderboltFabric.Hop] = []
        for (idx, item) in services.enumerated() {
            let depth = rootDepths[idx] ?? 0
            let speed = laneSpeed(of: item.service)
            let gen = generation(forSpeed: speed)
            hops.append(ThunderboltFabric.Hop(
                id: "switch-\(idx)",
                depth: depth,
                name: item.name,
                laneSpeedGbps: speed,
                generation: gen,
                children: []
            ))
        }
        // 按深度排序展示（根 0 在前）
        hops.sort { $0.depth < $1.depth }
        return hops
    }

    /// 计算每个 switch 的深度：沿父链找 IOThunderboltSwitch 祖先。
    /// 无法解析父链时按 0 处理（单 switch 场景常见）。
    private static func computeDepths(_ services: [(service: io_service_t, name: String, depth: Int)]) -> [Int] {
        var depths: [Int] = []
        for item in services {
            var depth = 0
            walkUp(from: item.service) { parent in
                if className(of: parent).contains("IOThunderboltSwitch") {
                    // 确认该 parent 不在当前 services 集合外时仍计数：多跳真实场景父 switch 应被枚举到
                    depth += 1
                    return true
                }
                return true
            }
            // 自身也算一级根；深度从 0 开始，父链计数即深度
            depths.append(depth)
        }
        return depths
    }

    /// 端口链路速率（Gbps/每 lane）：优先读 "LinkRate"，回退 "MaxLinkRate"，
    /// 再回退 "AppleThunderboltLinkRate"；单位取 Gbps。
    private static func laneSpeed(of service: io_service_t) -> Int {
        for key in ["LinkRate", "MaxLinkRate", "AppleThunderboltLinkRate", "Speed"] {
            if let v = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber {
                let d = v.doubleValue
                if d >= 5 { return Int(d.rounded()) }
            }
            if let v = IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? String,
               let d = Double(v.trimmingCharacters(in: .whitespaces)), d >= 5 {
                return Int(d.rounded())
            }
        }
        // 兜底：查父链端口属性
        var speed = 0
        walkUp(from: service) { parent in
            for key in ["LinkRate", "MaxLinkRate", "AppleThunderboltLinkRate", "Speed"] {
                if let v = IORegistryEntryCreateCFProperty(parent, key as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber {
                    let d = v.doubleValue
                    if d >= 5 { speed = Int(d.rounded()); return false }
                }
            }
            return true
        }
        return speed
    }

    /// 按每 lane 速率推断代数：80Gbps→TB5、40Gbps→TB3/TB4、20Gbps→TB2、10Gbps→TB1。
    /// TB3 与 TB4 同为 40Gbps 单 lane，硬件层无法区分，统一标注 TB3/TB4。
    static func generation(forSpeed gbps: Int) -> String {
        switch gbps {
        case 80: return "TB5"
        case 40: return "TB3/TB4"
        case 20: return "TB2"
        case 10: return "TB1"
        default: return "—"
        }
    }

    // MARK: - Tunnel

    private static func readTunnels() -> [ThunderboltFabric.Tunnel] {
        var result: [ThunderboltFabric.Tunnel] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOThunderboltTunnel"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            var dict: [String: Any] = [:]
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS {
                dict = (props?.takeRetainedValue() as? [String: Any]) ?? [:]
            }
            let name = entryName(of: service)
            let proto = tunnelProtocol(dict: dict, service: service, name: name)
            let active = (dict["Active"] as? NSNumber)?.boolValue
                ?? (dict["IsActive"] as? NSNumber)?.boolValue
                ?? name.localizedCaseInsensitiveContains("active")
            result.append(ThunderboltFabric.Tunnel(
                id: name,
                name: name,
                protocolName: proto,
                isActive: active
            ))
            IOObjectRelease(service)
        }
        return result
    }

    /// tunnel 承载协议：优先 "Protocol"/"TunnelType"，回退从类名推断。
    /// 常见：PCIe（NHI）、DisplayPort（DP）、XDomain。
    private static func tunnelProtocol(dict: [String: Any], service: io_service_t, name: String) -> String {
        for key in ["Protocol", "TunnelType", "TunnelProtocol"] {
            if let s = dict[key] as? String, !s.isEmpty { return s }
            if let n = dict[key] as? NSNumber {
                switch n.intValue {
                case 1: return "PCIe"
                case 2: return "DisplayPort"
                case 3: return "XDomain"
                case 4: return "USB4"
                default: return "协议#\(n.intValue)"
                }
            }
        }
        let cn = className(of: service)
        if cn.contains("NHI") || cn.contains("PCIe") { return "PCIe" }
        if cn.contains("DisplayPort") || cn.contains("DP") { return "DisplayPort" }
        if cn.contains("XDomain") { return "XDomain" }
        if name.contains("PCIe") { return "PCIe" }
        if name.contains("DP") || name.contains("DisplayPort") { return "DisplayPort" }
        if name.contains("XDomain") { return "XDomain" }
        return cn
    }

    // MARK: - IOKit 小工具

    private static func className(of service: io_service_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &buf) == KERN_SUCCESS else { return "?" }
        return String(cString: buf)
    }

    private static func entryName(of service: io_service_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        guard IORegistryEntryGetName(service, &buf) == KERN_SUCCESS else { return "" }
        return String(cString: buf)
    }

    private static func walkUp(from service: io_service_t, handler: (io_service_t) -> Bool) {
        var current: io_service_t = service
        while true {
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if kr != KERN_SUCCESS || parent == 0 { break }
            let keepGoing = handler(parent)
            if !keepGoing {
                IOObjectRelease(parent)
                break
            }
            if current != service { IOObjectRelease(current) }
            current = parent
        }
    }
}
