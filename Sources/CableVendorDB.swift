import Foundation

// MARK: - 线缆厂商识别（e-marker VID → 厂商名）

/// USB-IF Vendor ID → 厂商名映射。
/// VID 由 USB-IF 统一分配（https://usb.org / usb-ids 数据库），
/// e-marker 的 Vendor ID 字段即线缆/芯片厂商编号，与充电头、设备共用同一套编号。
/// 未知 VID 由调用方回退显示十六进制编号；本表可随实测持续扩充。
enum CableVendorDB {
    /// 已知常见线缆 / e-marker / 充电器相关厂商（VID 以 0x 十六进制写，保持与 IORegistry 一致）。
    /// 充电头、设备与线缆共用 USB-IF VID 编号，因此同一张表覆盖线缆厂商与充电器品牌。
    private static let known: [UInt16: String] = [
        0x05AC: "Apple",
        0x8087: "英特尔 Intel",       // 实测：当前 USB4 被动线缆 e-marker VID=0x8087
        0x2717: "小米 Xiaomi",           // 实测：小米 USB4 线 VID=0x2717
        0x291A: "安克 Anker",             // 实测：当前 100W USB4 线 VID=0x291A；Anker 充电器同 VID
        0x04E8: "三星 Samsung",
        0x050D: "贝尔金 Belkin",
        0x17EF: "联想 Lenovo",
        0x18D1: "Google",
        0x12D1: "华为 Huawei",
        0x0951: "金士顿 Kingston",
        // 充电器 / 适配器常见品牌
        0x413C: "戴尔 Dell",
        0x03F0: "惠普 HP",
        0x046D: "罗技 Logitech",
        0x22D9: "OPPO",
        0x2A70: "vivo",
        0x1E91: "OWC",
        // e-marker / PD 控制器芯片厂商（贴牌线/贴牌充电器常见）
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
        // 集线器 / 扩展坞控制器芯片
        0x05E3: "旺矽 Genesys Logic",
        0x045B: "瑞萨 Renesas",
        0x0483: "意法半导体 ST",
        0x04D8: "微芯 Microchip",
        0x04F2: "群光 Chicony",
        0x0424: "SMSC / Microchip",
        0x1532: "雷蛇 Razer",
        0x1B1C: "海盗船 Corsair",
    ]

    /// 返回 VID 对应的厂商名；未知返回 nil
    static func name(for vid: UInt16?) -> String? {
        guard let vid else { return nil }
        return known[vid]
    }

    /// 展示用厂商标签：已知返回 "厂商名"，未知返回 "未知厂商 (0xXXXX)"
    static func displayName(for vid: UInt16?) -> String {
        guard let vid else { return "未知厂商" }
        if let name = known[vid] { return name }
        return String(format: "未知厂商 (0x%04X)", vid)
    }
}
