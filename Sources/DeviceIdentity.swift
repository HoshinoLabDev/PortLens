import Foundation
import IOKit

// MARK: - 已连接设备（展示模型）

/// 设备类型标签
enum DeviceKind: String {
    case charger = "充电器"
    case phone = "手机"
    case tablet = "平板"
    case computer = "电脑"
    case display = "显示器"
    case dock = "扩展坞"
    case hub = "集线器"
    case peripheral = "外设"
    case unknown = "设备"

    /// 类型标签（英文兜底，与 UI 中性展示一致）
    var enTag: String {
        switch self {
        case .charger: return "Charger"
        case .phone: return "iPhone"
        case .tablet: return "iPad"
        case .computer: return "Computer"
        case .display: return "Display"
        case .dock: return "Dock"
        case .hub: return "Hub"
        case .peripheral: return "Device"
        case .unknown: return "Device"
        }
    }
}

/// 结构化"已连接设备"条目：图标 + 品牌型号 + 类型标签 + 挂载层级
struct ConnectedDevice: Identifiable, Hashable {
    let id: UInt64
    let kind: DeviceKind
    let brand: String?          // 品牌（如 Anker / Apple / Dell）
    let model: String?          // 型号/描述（如 100W 充电器 / iPhone / U2723QE）
    let detail: String?         // 补充（如 VID 0x291A · PID 0x2345 / 经 2 级集线器）
    let icon: String            // SF Symbol
    let hops: Int               // 到物理端口经过的 hub 数量（0 = 直连）
    let vid: UInt16?
    let pid: UInt16?

    var summary: String {
        var parts: [String] = []
        if let b = brand, !b.isEmpty { parts.append(b) }
        if let m = model, !m.isEmpty { parts.append(m) }
        if parts.isEmpty { return kind.rawValue }
        return parts.joined(separator: " ")
    }

    /// 挂载层级提示：直连 / 经 N 级集线器
    var viaText: String? {
        hops > 0 ? "经 \(hops) 级集线器" : nil
    }
}

// MARK: - 设备/充电器厂商库（VID → 品牌 + 品牌名匹配）

enum DeviceVendorDB {
    /// VID → 品牌名（充电器/适配器/设备共用 USB-IF VID 编号）
    private static let known: [UInt16: String] = [
        0x05AC: "Apple",
        0x291A: "Anker",
        0x2717: "小米 Xiaomi",
        0x04E8: "三星 Samsung",
        0x17EF: "联想 Lenovo",
        0x12D1: "华为 Huawei",
        0x050D: "贝尔金 Belkin",
        0x18D1: "Google",
        0x8087: "英特尔 Intel",
        0x413C: "戴尔 Dell",
        0x03F0: "惠普 HP",
        0x046D: "罗技 Logitech",
        0x22D9: "OPPO",
        0x2A70: "vivo",
        // 常用协议/集线器芯片厂商（贴牌充电器/扩展坞常见）
        0x04B4: "Cypress / Infineon",
        0x0451: "德州仪器 TI",
        0x0BDA: "瑞昱 Realtek",
        0x2109: "威锋 VIA Labs",
        0x1A86: "沁恒 WCH",
        0x1D5C: "谱瑞 Parade",
        0x15A2: "NXP",
        0x1027: "钰创 Etron",
        0x0E8D: "联发科 MediaTek",
        0x090A: "慧荣 Silicon Motion",
        0x1987: "群联 Phison",
        0x05E3: "旺矽 Genesys Logic",
        0x045B: "瑞萨 Renesas",
        0x0483: "意法半导体 ST",
        0x04D8: "微芯 Microchip",
        0x04F2: "群光 Chicony",
        0x0424: "SMSC / Microchip",
        0x1E91: "OWC",
        0x1532: "雷蛇 Razer",
        0x1B1C: "海盗船 Corsair",
    ]

    /// 厂商名字符串匹配品牌（覆盖无稳定 VID 的充电器品牌：倍思/绿联/紫米等）
    private static let nameAliases: [(keyword: String, brand: String)] = [
        ("baseus", "倍思 Baseus"),
        ("倍思", "倍思 Baseus"),
        ("ugreen", "绿联 UGREEN"),
        ("绿联", "绿联 UGREEN"),
        ("zmi", "紫米 ZMI"),
        ("紫米", "紫米 ZMI"),
        ("aukey", "Aukey"),
        ("ravpower", "RAVPower"),
        ("satechi", "Satechi"),
        ("hyperdrive", "HyperDrive"),
        ("cable matters", "Cable Matters"),
        ("ankr", "Anker"),
        ("anker", "Anker"),
        ("belkin", "贝尔金 Belkin"),
        ("xiaomi", "小米 Xiaomi"),
        ("mi ", "小米 Xiaomi"),
        ("huawei", "华为 Huawei"),
        ("honor", "荣耀 Honor"),
        ("samsung", "三星 Samsung"),
        ("lenovo", "联想 Lenovo"),
        ("dell", "戴尔 Dell"),
        ("hp ", "惠普 HP"),
        ("logitech", "罗技 Logitech"),
        ("oppo", "OPPO"),
        ("vivo", "vivo"),
        ("oneplus", "一加 OnePlus"),
        ("realme", "真我 realme"),
        ("nubia", "努比亚 nubia"),
        ("motorola", "摩托罗拉 Motorola"),
    ]

    /// 返回品牌名：优先 VID 库，其次厂商名字符串匹配，最后原样返回厂商名
    static func brandName(vid: UInt16?, vendorName: String?) -> String? {
        if let vid, let name = known[vid] { return name }
        if let raw = vendorName?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty {
            let lower = raw.lowercased()
            for (kw, brand) in nameAliases where lower.contains(kw) {
                return brand
            }
            return raw
        }
        return nil
    }

    /// 兜底文案：未知充电器（VID:xxxx, PID:xxxx）
    static func unknownChargerLabel(vid: UInt16?, pid: UInt16?) -> String {
        if let vid, let pid {
            return String(format: "未知充电器（VID:0x%04X, PID:0x%04X）", vid, pid)
        }
        if let vid { return String(format: "未知充电器（VID:0x%04X）", vid) }
        return "未知充电器"
    }
}

// MARK: - 充电器识别（PD Discover Identity · SOP 节点）

struct ChargerIdentity {
    let vid: UInt16?
    let pid: UInt16?
    let bcdDevice: UInt16?
    let productType: String?
    let vdos: [UInt32]

    /// 生成展示条目（结合系统适配器额定功率）
    func makeConnectedDevice(watts: Double?) -> ConnectedDevice {
        let brand = DeviceVendorDB.brandName(vid: vid, vendorName: nil)
        var model: String
        if let pt = productType, !pt.isEmpty, pt.lowercased() != "power adapter" {
            model = pt
        } else {
            model = "USB-C 充电器"
        }
        if let w = watts, w > 1 {
            model += " · \(Int(w.rounded()))W"
        }
        var detail: String?
        if let vid, let pid {
            detail = String(format: "VID 0x%04X · PID 0x%04X", vid, pid)
        }
        return ConnectedDevice(
            id: 0, kind: .charger,
            brand: brand ?? DeviceVendorDB.unknownChargerLabel(vid: vid, pid: pid),
            model: model, detail: detail, icon: "bolt.fill", hops: 0,
            vid: vid, pid: pid
        )
    }
}

/// 充电器识别器：从 SOP 节点（IOPortTransportComponentCCUSBPDSOP，无 p 后缀）读 PD Discover Identity
/// 的 VID/PID/bcdDevice/Product Type Description/VDOs。SOP'（带 p 后缀）是线缆 e-marker，见 Diagnostics。
enum ChargerIdentityReader {
    /// 按端口号读取该口下充电器身份
    static func read(for portNumber: Int) -> ChargerIdentity? {
        // 关键修复：区分真实外部充电器与扩展坞链内 PD 芯片。
        // 扩展坞/集线器具备 USB-C 供电能力时，其内部 PD 控制器也会暴露 SOP 节点
        // （VID/PID 常与 Hub 相同，如 Anker 扩展坞 PID 0x8383），但没有向 Mac 供电，
        // 其 Power In 子树下不存在 IOPortFeaturePowerSource（电源源）节点。
        // 真实充电器则必有该节点（Port-USB-C@2/Power In/USB-PD，PowerSourceType=2）。
        // 因此：仅当该口存在电源源节点时才识别为充电器；扩展坞链内 PD 芯片不显示为充电器。
        guard hasPowerSource(portNumber: portNumber) else { return nil }

        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortTransportComponentCCUSBPDSOP"), &iter) == KERN_SUCCESS else {
            return nil
        }
        defer { IOObjectRelease(iter) }
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            let parentPort =
                property(service, "ParentPortNumber").flatMap { ($0 as? NSNumber)?.intValue }
                ?? property(service, "ParentBuiltInPortNumber").flatMap { ($0 as? NSNumber)?.intValue }
                ?? Int.min
            // Apple Silicon：SOP 的 ParentPortNumber 即 Type10 控制器 PortNumber（1 起），端口卡编号从 0 起，需 -1 换算。
            // 注意：不能写 parentPort == portNumber 的宽松分支——ParentPortNumber=1 会被 TypeC 1 误匹配，
            // 导致 TypeC 1 显示成 TypeC 0 的充电器。
            guard parentPort - 1 == portNumber else { continue }

            let metadata = dictProperty(service, "Metadata")
            let vid = num(metadata?["Vendor ID"]).map { UInt16(truncatingIfNeeded: $0.uint64Value) }
            let pid = num(metadata?["Product ID"]).map { UInt16(truncatingIfNeeded: $0.uint64Value) }
            let bcd = num(metadata?["bcdDevice"]).map { UInt16(truncatingIfNeeded: $0.uint64Value) }
            let productType = metadata?["Product Type Description"] as? String
            let vdos: [UInt32] = ((metadata?["VDOs"] as? [Any]) ?? []).compactMap { value in
                if let data = value as? Data, data.count >= 4 {
                    return data.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
                }
                if let n = value as? NSNumber { return UInt32(truncatingIfNeeded: n.uint64Value) }
                return nil
            }
            guard vid != nil || pid != nil || !vdos.isEmpty else { continue }
            return ChargerIdentity(vid: vid, pid: pid, bcdDevice: bcd, productType: productType, vdos: vdos)
        }
        return nil
    }

    private static func property(_ service: io_service_t, _ key: String) -> Any? {
        IORegistryEntryCreateCFProperty(service, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// 判断该 TypeC 口是否存在 PD 电源源节点（IOPortFeaturePowerSource）。
    /// 真实充电器接入时，其 Power In 子树会挂 USB-PD（PowerSourceType=2）/ Brick ID 节点；
    /// 扩展坞/集线器链内 PD 芯片（仅宣称供电能力、实际未向 Mac 供电）则没有该节点。
    /// 注意：枚举全树按 ParentPortNumber 归属（与 SOP 节点同源，1 起，端口卡编号 0 起需 -1）。
    private static func hasPowerSource(portNumber: Int) -> Bool {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOPortFeaturePowerSource"), &iter) == KERN_SUCCESS else {
            return false
        }
        defer { IOObjectRelease(iter) }
        while case let service = IOIteratorNext(iter), service != 0 {
            defer { IOObjectRelease(service) }
            let parentPort =
                property(service, "ParentPortNumber").flatMap { ($0 as? NSNumber)?.intValue }
                ?? property(service, "ParentBuiltInPortNumber").flatMap { ($0 as? NSNumber)?.intValue }
                ?? Int.min
            guard parentPort - 1 == portNumber else { continue }
            return true
        }
        return false
    }

    private static func dictProperty(_ service: io_service_t, _ key: String) -> [String: Any]? {
        guard let raw = property(service, key) else { return nil }
        if let d = raw as? [String: Any] { return d }
        if let ns = raw as? NSDictionary {
            var out: [String: Any] = [:]
            for (k, v) in ns { if let ks = k as? String { out[ks] = v } }
            return out
        }
        return nil
    }

    private static func num(_ v: Any?) -> NSNumber? { v as? NSNumber }
}

// MARK: - 通用设备分类（IOUSBHostDevice / IOUSBDevice）

enum DeviceClassifier {
    /// 从 USB 设备信息分类出展示条目
    static func makeConnectedDevice(from info: USBDeviceInfo) -> ConnectedDevice {
        let lower = (info.productName ?? "").lowercased()
        var kind: DeviceKind = .unknown
        var icon = "externaldrive.fill"
        var model = info.productName?.trimmingCharacters(in: .whitespacesAndNewlines)
        if model?.isEmpty == true { model = nil }

        // 集线器/扩展坞优先（bDeviceClass=0x09 或名称）
        let isHubClass = info.deviceClass == 0x09
        if isHubClass || lower.contains("hub") || lower.contains("dock") || lower.contains("扩展坞") || lower.contains("集线") || lower.contains("坞") {
            kind = (isHubClass && !lower.contains("dock")) || lower.contains("hub") || lower.contains("集线") ? .hub : .dock
            icon = "hubs"
        }

        // Apple 设备（VID 0x05AC）：iPhone / iPad / iPod
        if info.vendorID == 0x05AC, kind == .unknown {
            if lower.contains("iphone") || lower.contains("apple mobile device") {
                kind = .phone
                icon = "iphone"
                if model == nil { model = "iPhone" }
            } else if lower.contains("ipad") {
                kind = .tablet
                icon = "ipad"
            } else if lower.contains("ipod") {
                kind = .peripheral
                icon = "music.note"
            } else if lower.contains("watch") {
                kind = .peripheral
                icon = "applewatch"
            } else {
                kind = .phone
                icon = "iphone"
                if model == nil { model = "Apple 设备" }
            }
        }

        // 充电器标识：USB 设备树中出现的纯电源设备（Apple 充电器通常不枚举为 USB 设备，兜底判 class）
        if kind == .unknown, info.deviceClass == 0x00, lower.contains("charger") || lower.contains("adapter") || lower.contains("电源") {
            kind = .charger
            icon = "bolt.fill"
        }

        // 通用外设
        if kind == .unknown {
            if lower.contains("keyboard") || lower.contains("键盘") { icon = "keyboard" }
            else if lower.contains("mouse") || lower.contains("trackpad") || lower.contains("鼠标") { icon = "computermouse.fill" }
            else if lower.contains("camera") || lower.contains("webcam") || lower.contains("摄像头") { icon = "web.camera.fill" }
            else if lower.contains("audio") || lower.contains("耳机") || lower.contains("headphone") || lower.contains("speaker") || lower.contains("音箱") { icon = "headphones" }
            else if lower.contains("display") || lower.contains("monitor") || lower.contains("屏幕") { icon = "display" }
            else if lower.contains("disk") || lower.contains("ssd") || lower.contains("storage") || lower.contains("移动硬盘") || lower.contains("u盘") { icon = "externaldrive.fill" }
        }

        let brand = DeviceVendorDB.brandName(vid: info.vendorID, vendorName: info.vendorName)
        var detail: String?
        if info.vendorID != 0 || info.productID != 0 {
            detail = String(format: "VID 0x%04X · PID 0x%04X", info.vendorID, info.productID)
        }
        return ConnectedDevice(
            id: info.id, kind: kind, brand: brand, model: model, detail: detail,
            icon: icon, hops: info.hubCount, vid: info.vendorID, pid: info.productID
        )
    }
}

// MARK: - 显示器识别（IODisplayConnect + EDID）

enum EDIDParser {
    struct Info {
        let pnpID: String?
        let manufacturer: String?
        let productCode: UInt16
        let displayName: String?
        let serial: String?
    }

    /// 解析 128 字节 EDID
    static func parse(_ data: Data) -> Info? {
        guard data.count >= 128 else { return nil }
        let bytes = [UInt8](data.prefix(128))
        guard bytes[0] == 0x00, bytes[1] == 0xFF, bytes[2] == 0xFF, bytes[3] == 0xFF,
              bytes[4] == 0xFF, bytes[5] == 0xFF, bytes[6] == 0xFF, bytes[7] == 0x00 else { return nil }
        // 厂商 PNP ID（byte8-9 共 16 位，3 个 5-bit 字符）
        let pnpBits = (UInt16(bytes[8]) << 8) | UInt16(bytes[9])
        let pnp = pnpID(from: pnpBits)
        let productCode = (UInt16(bytes[11]) << 8) | UInt16(bytes[10])
        // Descriptor 块：从 54 开始每 18 字节；tag 0xFC=名称，0xFF=序列号
        var name: String?
        var serial: String?
        var offset = 54
        while offset + 18 <= 126 {
            let tag = bytes[offset + 3]
            if tag == 0xFC {
                name = asciiDescriptor(bytes, offset: offset + 5)
            } else if tag == 0xFF {
                serial = asciiDescriptor(bytes, offset: offset + 5)
            }
            offset += 18
        }
        return Info(pnpID: pnp, manufacturer: manufacturerName(for: pnp), productCode: productCode,
                    displayName: name, serial: serial)
    }

    /// PNP ID 三位字母解码（A=1 ... Z=26）
    static func pnpID(from bits: UInt16) -> String {
        func char(_ shift: Int) -> Character {
            let v = Int((bits >> shift) & 0x1F)
            guard v >= 1, v <= 26, let scalar = UnicodeScalar(64 + v) else { return "?" }
            return Character(scalar)
        }
        return String([char(10), char(5), char(0)])
    }

    /// PNP ID → 显示器厂商名（常见映射）
    static func manufacturerName(for pnp: String?) -> String? {
        guard let pnp else { return nil }
        let map: [String: String] = [
            "DEL": "戴尔 Dell", "LGD": "LG", "SAM": "三星 Samsung", "PHI": "飞利浦 Philips",
            "HPN": "惠普 HP", "BNQ": "明基 BenQ", "ACR": "宏碁 Acer", "VSC": "优派 ViewSonic",
            "LEN": "联想 Lenovo", "APP": "Apple", "AUO": "友达 AUO", "BOE": "京东方 BOE",
            "CMO": "奇美 CMO", "HSD": "惠科 HKC", "TCL": "TCL", "AUS": "华硕 ASUS",
            "GSM": "LG GSM", "SHP": "夏普 Sharp", "SON": "索尼 Sony", "PAN": "松下 Panasonic",
            "NEC": "NEC", "SEC": "三星 Samsung", "HEI": "海尔 Haier", "KON": "康佳 Konka",
            "CHR": "冠捷 AOC", "YHX": "YHX",
        ]
        return map[pnp.uppercased()]
    }

    /// ASCII 描述文本（0x0A 截断，去尾空格）
    private static func asciiDescriptor(_ bytes: [UInt8], offset: Int) -> String? {
        var out = ""
        for i in offset..<min(offset + 13, bytes.count) {
            let b = bytes[i]
            if b == 0x0A || b == 0x00 { break }
            out.append(Character(UnicodeScalar(b)))
        }
        let trimmed = out.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}

enum DisplayEDIDReader {
    /// 枚举外接显示器（IODisplayConnect 节点读 IODisplayEDID 属性），附带挂载的 TypeC 端口编号。
    /// 当前无头/笔记本内置屏（AppleCLCD）不暴露 EDID，返回空数组。
    /// portNumber 语义与端口卡一致（TypeC 编号 0/1；Apple Silicon 由父链 IOPort/XHCI PortNumber-1 换算）。
    static func readDisplays() -> [(portNumber: Int?, device: ConnectedDevice)] {
        var result: [(portNumber: Int?, device: ConnectedDevice)] = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IODisplayConnect"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        var uid: UInt64 = 1
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard let edidData = IORegistryEntryCreateCFProperty(service, "IODisplayEDID" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? Data,
                let info = EDIDParser.parse(edidData) else { continue }
            var brand = info.manufacturer ?? info.pnpID
            if brand == nil { brand = "显示器" }
            var model = info.displayName
            if model == nil, let pnp = info.pnpID {
                model = "显示器 (\(pnp)\(info.productCode != 0 ? " #\(String(format: "%04X", info.productCode))" : ""))"
            }
            let detail = info.pnpID.map { "PNP \($0)" }
            result.append((
                portNumber: displayPortNumber(of: service),
                device: ConnectedDevice(
                    id: uid, kind: .display, brand: brand, model: model, detail: detail,
                    icon: "display", hops: 0, vid: nil, pid: nil
                )
            ))
            uid += 1
        }
        return result
    }

    /// 沿父链找最近的 IOPort/XHCI 端口，PortNumber-1 换算为 TypeC 编号（拿不到返回 nil）
    private static func displayPortNumber(of service: io_service_t) -> Int? {
        var current: io_registry_entry_t = service
        while current != 0 {
            var parent: io_registry_entry_t = 0
            let kr = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            if kr != KERN_SUCCESS || parent == 0 { break }
            if let pn = (IORegistryEntryCreateCFProperty(parent, "PortNumber" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? NSNumber)?.intValue {
                IOObjectRelease(parent)
                current = 0
                return pn - 1
            }
            if current != service {
                IOObjectRelease(current)
            }
            current = parent
        }
        if current != service {
            IOObjectRelease(current)
        }
        return nil
    }
}

// MARK: - MagSafe 充电器条目

enum MagSafeDevice {
    static func make(power: PowerState) -> ConnectedDevice {
        var model = "MagSafe 电源适配器"
        if power.adapterWatts > 1 {
            model += " · \(Int(power.adapterWatts.rounded()))W"
        }
        return ConnectedDevice(id: 0, kind: .charger, brand: "Apple", model: model,
                               detail: nil, icon: "magsafe.charger", hops: 0, vid: nil, pid: nil)
    }
}
