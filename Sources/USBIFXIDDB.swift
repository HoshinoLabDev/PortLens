import Foundation

// MARK: - USB-IF 认证 XID 数据库

/// e-marker / PD 设备经 USB-IF 认证时会被分配一个 16-bit 的 XID（证书 ID），
/// 由 USB-IF 在认证通过后颁发。XID 本身不直接编码厂商名，需要对照公布列表
/// 才能还原制造商。本表为小型内置库（可随实测扩充），未命中的 XID 一律按
/// "certified but unlisted" 中性提示，绝不猜测厂商。
///
/// 取值来源：IORegistry e-marker 节点 Metadata 中的 "Product XID" / "XID"
/// 字段（实机可能缺省），回退到 ID Header VDO 的 Product ID 字段。
enum USBIFXIDDB {

    /// 常见认证线缆 / e-marker 芯片厂商的 XID → 厂商名映射。
    /// 与 CableVendorDB 的 VID 表同源但独立维护：VID 表示"厂商编号"，
    /// XID 表示"USB-IF 认证证书编号"，二者通常一致（同一厂商申请的编号段）。
    private static let knownXID: [UInt16: String] = [
        0x05AC: "Apple",
        0x8087: "英特尔 Intel",
        0x2717: "小米 Xiaomi",
        0x291A: "安克 Anker",
        0x04E8: "三星 Samsung",
        0x050D: "贝尔金 Belkin",
        0x17EF: "联想 Lenovo",
        0x18D1: "Google",
        0x12D1: "华为 Huawei",
        0x0951: "金士顿 Kingston",
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
    ]

    /// USB-IF 公布列表中常见 VID（用于信任评估：VID 是否属于已知厂商）。
    /// 此集合为"已收录/常见"集合，未命中不必然代表伪造，但值得中性提示。
    private static let knownVID: Set<UInt16> = {
        var s = Set<UInt16>(knownXID.keys)
        s.formUnion([
            0x03EB, // Atmel / Microchip
            0x0456, // Analog Devices
            0x046D, // Logitech
            0x0471, // Philips
            0x0483, // STMicroelectronics
            0x04F2, // Chicony
            0x054C, // Sony
            0x0557, // ATEN
            0x056A, // Wacom
            0x058F, // Alcor Micro
            0x05E3, // Genesys Logic
            0x067B, // Prolific
            0x0781, // SanDisk
            0x0930, // Toshiba
            0x0A12, // Cambridge Silicon Radio
            0x0B95, // ASIX
            0x0C45, // Microdia
            0x1058, // Western Digital
            0x13D3, // AzureWave
            0x152D, // JMicron
            0x1B1C, // Corsair
            0x20A0, // Clay Logic
            0x262A, // Satechi
            0x2BDE, // Voxx / Plantronics
            0x8086, // Intel（与 0x8087 不同，双写兼容）
            0x10C4, // Silicon Labs
            0x1BC0, // AVerMedia
            0x174C, // ASMedia
            0x2109, // VIA Labs
            0x1A6E, // Global Unichip
            0x2188, // 立锜 Richtek
            0x2304, // 士兰微 Silan
            0x1F3A, // 杰华特 Joulwatt
        ])
        return s
    }()

    /// 按 XID 返回认证厂商名；未公布返回 nil（调用方显示 "certified but unlisted"）
    static func manufacturerName(forXID xid: UInt16?) -> String? {
        guard let xid else { return nil }
        return knownXID[xid]
    }

    /// VID 是否属于已知 USB-IF 公布列表
    static func isKnownVID(_ vid: UInt16?) -> Bool {
        guard let vid else { return false }
        return knownVID.contains(vid)
    }

    /// 认证状态描述：
    /// - e-marker 存在即视为携带认证信息；
    /// - XID 命中 → "certified" + 厂商名；
    /// - XID 未命中 → "certified but unlisted"（中性，不猜厂商）。
    /// 返回 (状态标签, 厂商名?)
    static func certificationLabel(xid: UInt16?, hasEMarker: Bool) -> (status: String, manufacturer: String?) {
        guard hasEMarker else { return ("uncertified", nil) }
        if let name = manufacturerName(forXID: xid) {
            return ("certified", name)
        }
        return ("certified but unlisted", nil)
    }
}

// MARK: - 线缆信任信号评估

/// 线缆信任评估：当 e-marker 报告异常值时给出中性警告（"this looks unusual"），
/// 不做"fake/伪造"式指控。
enum CableTrust {

    struct Assessment: Equatable {
        let isTrusted: Bool
        let warnings: [String]

        var summary: String? {
            guard !warnings.isEmpty else { return nil }
            return warnings.joined(separator: "；")
        }
    }

    /// 评估 e-marker 异常信号：
    /// - 零 Vendor ID；
    /// - 速度字段落在保留位（B[2:0] >= 5）；
    /// - 电流字段落在保留位（B[5:3] >= 2）；
    /// - 线缆延迟字段保留位（B[13:11] == 111）；
    /// - VID 不在已知 USB-IF 公布列表。
    static func assess(cableVDO: UInt32?, vendorVID: UInt16?, speedBits: Int, currentBits: Int) -> Assessment {
        var warnings: [String] = []

        if vendorVID == nil || vendorVID == 0 {
            warnings.append("e-marker 携带零 Vendor ID，this looks unusual")
        } else if !USBIFXIDDB.isKnownVID(vendorVID) {
            warnings.append("Vendor ID 0x\(String(format: "%04X", vendorVID ?? 0)) 未在已知 USB-IF 列表中，this looks unusual")
        }

        if speedBits >= 5 {
            warnings.append("线缆速度字段使用保留位（\(speedBits)），this looks unusual")
        }

        if currentBits >= 2 {
            warnings.append("线缆电流字段使用保留位（\(currentBits)），this looks unusual")
        }

        if let vdo = cableVDO, ((vdo >> 11) & 0x7) == 0x7 {
            warnings.append("线缆延迟字段使用保留位（111），this looks unusual")
        }

        // 0x8087 Intel 作为 VID 出现在被动线缆 e-marker 属正常（实测），
        // 但 VID 与"已知厂商"集合匹配时不做额外告警；此处只收集异常项。
        return Assessment(isTrusted: warnings.isEmpty, warnings: warnings)
    }
}
