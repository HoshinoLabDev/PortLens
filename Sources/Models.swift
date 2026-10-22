import Foundation
import Combine
import AppKit

// MARK: - 设置存储（避免 @State macro，兼容 CLT 工具链）

final class SettingsStore: ObservableObject {
    /// 菜单栏图标显示模式
    enum IconMode: String, CaseIterable {
        case simple = "simple"              // 简约：静态原版图标
        case dynamic = "dynamic"            // 动态（电量）
        case wideBar = "wideBar"            // 宽体色块（参考 ThinkPad 电源管理，融合 Mac 审美）

        var displayName: String {
            switch self {
            case .simple: return "简约"
            case .dynamic: return "动态（电量/输入功率）"
            case .wideBar: return "宽体色块"
            }
        }
    }

    /// Dock 应用模式：菜单栏专属（accessory）或带 Dock 图标（regular）
    enum DockMode: String, CaseIterable {
        case accessory = "accessory"
        case regular = "regular"

        var displayName: String {
            switch self {
            case .accessory: return "菜单栏专属"
            case .regular: return "Dock 应用模式"
            }
        }
    }

    /// 菜单栏实时充电瓦数显示方式：关闭 / 数字 / 填充条
    enum IconChargeDisplay: String, CaseIterable {
        case off = "off"
        case number = "number"
        case bar = "bar"

        var displayName: String {
            switch self {
            case .off: return "不显示"
            case .number: return "数字（如 89W）"
            case .bar: return "填充条"
            }
        }
    }

    @Published var iconMode: IconMode {
        didSet { UserDefaults.standard.set(iconMode.rawValue, forKey: "iconMode") }
    }
    @Published var hideEmptyPorts = false {
        didSet { UserDefaults.standard.set(hideEmptyPorts, forKey: "hideEmptyPorts") }
    }
    @Published var showBatterySummary = true {
        didSet { UserDefaults.standard.set(showBatterySummary, forKey: "showBatterySummary") }
    }

    // 第二批设置：Dock 模式 / 图标充电瓦数 / 字号 / 透明度 / 开机启动 / KVM 开关 / 技术细节 / 通知
    @Published var dockMode: DockMode {
        didSet {
            UserDefaults.standard.set(dockMode.rawValue, forKey: "dockMode")
            applyDockMode()
        }
    }
    @Published var iconChargeDisplay: IconChargeDisplay {
        didSet { UserDefaults.standard.set(iconChargeDisplay.rawValue, forKey: "iconChargeDisplay") }
    }
    @Published var fontSizeScale: Double = 1.0 {
        didSet { UserDefaults.standard.set(fontSizeScale, forKey: "fontSizeScale") }
    }
    @Published var windowOpacity: Double = 1.0 {
        didSet { UserDefaults.standard.set(windowOpacity, forKey: "windowOpacity") }
    }
    @Published var launchAtLogin = false {
        didSet {
            UserDefaults.standard.set(launchAtLogin, forKey: "launchAtLogin")
            LoginLauncher.apply(enabled: launchAtLogin)
        }
    }
    @Published var skipDeepUSBProbe = false {
        didSet { UserDefaults.standard.set(skipDeepUSBProbe, forKey: "skipDeepUSBProbe") }
    }
    @Published var showTechDetails = false {
        didSet { UserDefaults.standard.set(showTechDetails, forKey: "showTechDetails") }
    }
    @Published var notificationsEnabled = true {
        didSet { UserDefaults.standard.set(notificationsEnabled, forKey: "notificationsEnabled") }
    }

    // 第三批设置：动画效果（能量流粒子 / 扫描透视 / 呼吸图标），默认全部开启
    @Published var energyFlowEnabled = true {
        didSet { UserDefaults.standard.set(energyFlowEnabled, forKey: "energyFlowEnabled") }
    }
    @Published var scanEffectEnabled = true {
        didSet { UserDefaults.standard.set(scanEffectEnabled, forKey: "scanEffectEnabled") }
    }
    @Published var breathingIconEnabled = true {
        didSet { UserDefaults.standard.set(breathingIconEnabled, forKey: "breathingIconEnabled") }
    }

    init() {
        // 兼容旧版本已保存的 dynamicConsumption（动态含消耗功率）档：统一映射为动态（电量）
        let raw = UserDefaults.standard.string(forKey: "iconMode") ?? ""
        if raw == "dynamicConsumption" {
            iconMode = .dynamic
        } else {
            iconMode = IconMode(rawValue: raw) ?? .simple
        }
        hideEmptyPorts = UserDefaults.standard.bool(forKey: "hideEmptyPorts")
        showBatterySummary = UserDefaults.standard.object(forKey: "showBatterySummary") as? Bool ?? true
        dockMode = DockMode(rawValue: UserDefaults.standard.string(forKey: "dockMode") ?? "") ?? .accessory
        iconChargeDisplay = IconChargeDisplay(rawValue: UserDefaults.standard.string(forKey: "iconChargeDisplay") ?? "") ?? .off
        fontSizeScale = UserDefaults.standard.object(forKey: "fontSizeScale") as? Double ?? 1.0
        windowOpacity = UserDefaults.standard.object(forKey: "windowOpacity") as? Double ?? 1.0
        launchAtLogin = UserDefaults.standard.bool(forKey: "launchAtLogin")
        skipDeepUSBProbe = UserDefaults.standard.bool(forKey: "skipDeepUSBProbe")
        showTechDetails = UserDefaults.standard.bool(forKey: "showTechDetails")
        notificationsEnabled = UserDefaults.standard.object(forKey: "notificationsEnabled") as? Bool ?? true
        energyFlowEnabled = UserDefaults.standard.object(forKey: "energyFlowEnabled") as? Bool ?? true
        scanEffectEnabled = UserDefaults.standard.object(forKey: "scanEffectEnabled") as? Bool ?? true
        breathingIconEnabled = UserDefaults.standard.object(forKey: "breathingIconEnabled") as? Bool ?? true
    }

    /// 应用 Dock 模式（在 AppDelegate 初始化绑定后由设置窗口触发）
    func applyDockMode() {
        switch dockMode {
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        case .regular:
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - 开机启动（LaunchAgent，桌面自签名 App 无 SMAppService 授权路径）

enum LoginLauncher {
    private static var agentURL: URL {
        let base = FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library")
        return base.appendingPathComponent("LaunchAgents/com.marvis.portlens.plist")
    }

    static func apply(enabled: Bool) {
        if enabled {
            guard let bundle = Bundle.main.executableURL else { return }
            let appPath = bundle.deletingLastPathComponent().deletingLastPathComponent().path
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>com.marvis.portlens</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(appPath)/Contents/MacOS/PortLens</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
            </dict>
            </plist>
            """
            try? FileManager.default.createDirectory(
                at: agentURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plist.write(to: agentURL, atomically: true, encoding: .utf8)
        } else {
            try? FileManager.default.removeItem(at: agentURL)
        }
    }
}

// MARK: - Widget 共享快照（AppGroup 文件：主 App 写，Widget Extension 读）

struct PortLensWidgetSnapshot: Codable {
    var connectedCount: Int = 0
    var batteryPercent: Int = 0
    var isCharging: Bool = false
    var chargingWatts: Double = 0
    var certificationText: String = ""
    var trustWarning: String = ""
    var lastUpdate: Date = Date()

    static let suiteName = "group.com.marvis.portlens"

    /// 共享快照路径：统一使用用户 Application Support（主 App 与 Widget 均可读写，
    /// 不依赖 AppGroup 容器权限——ad-hoc 签名下容器文件访问会被系统拒绝）
    static var sharedURL: URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("PortLens/widgetSnapshot.json")
    }

    static func read() -> PortLensWidgetSnapshot {
        let url = sharedURL
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(PortLensWidgetSnapshot.self, from: data) else {
            return PortLensWidgetSnapshot()
        }
        return snap
    }

    @discardableResult
    func write() -> Bool {
        let url = Self.sharedURL
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - USB 设备信息

struct USBDeviceInfo: Identifiable, Hashable {
    let id: UInt64
    let locationID: UInt32
    let vendorID: UInt16
    let productID: UInt16
    let vendorName: String?
    let productName: String?
    let serialNumber: String?
    let usbVersion: String?
    let speedRaw: UInt8
    let busPowerMA: Int?
    let currentMA: Int?
    let ioClassName: String
    let portNumber: Int?
    let portType: String?
    let deviceClass: UInt8?
    let isBillboard: Bool
    /// 到物理端口经过的集线器数量（0 = 直连；记录扩展坞/集线器挂载层级）
    let hubCount: Int
    /// 链路中集线器/扩展坞的产品名（由近到远）
    let hubChain: [String]

    var displayName: String {
        let product = (productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if !product.isEmpty {
            if let vendor = vendorName?.trimmingCharacters(in: .whitespacesAndNewlines), !vendor.isEmpty {
                return "\(product) · \(vendor)"
            }
            return product
        }
        return String(format: "未知设备 (0x%04X:0x%04X)", vendorID, productID)
    }

    var shortName: String {
        let product = (productName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return product.isEmpty ? String(format: "0x%04X", productID) : product
    }

    var speedLabel: String {
        switch speedRaw {
        case 0: return "1.5 Mbps"
        case 1: return "12 Mbps"
        case 2: return "480 Mbps"
        case 3: return "5 Gbps"
        case 4: return "10 Gbps"
        case 5: return "20 Gbps"
        default: return "—"
        }
    }

    var speedGbps: Double? {
        switch speedRaw {
        case 3: return 5
        case 4: return 10
        case 5: return 20
        default: return nil
        }
    }

    /// 是否属于低速（USB 2.0 及以下）
    var isSlowUSB: Bool { speedRaw <= 2 }

    /// 是否高速（SuperSpeed+）
    var isSuperSpeed: Bool { speedRaw >= 3 }
}

// MARK: - 端口卡片

enum PortTint: String {
    case green, blue, purple, orange, red, gray
}

struct PDOProfile: Identifiable, Equatable {
    let id = UUID()
    let volts: Double
    let amps: Double
    let watts: Double
    let isActive: Bool
}

struct PortCardModel: Identifiable {
    let id: Int
    let portIndex: Int
    let portNumber: Int?
    let portType: String?
    let devices: [USBDeviceInfo]

    // 诊断结果
    let headline: String
    let headlineIcon: String
    let tint: PortTint
    let chargingBanner: String?
    let chargingSub: String?
    let dataLine: String?
    let cableLine: String?
    var cableSpec: String? = nil
    let deviceLine: String?
    let pdoList: [PDOProfile]?
    let faultText: String?
    let isConnected: Bool
    let isMagSafe: Bool

    // 第二批功能：USB-IF 认证 / 信任警告 / Thunderbolt fabric / Active transports / 技术细节
    var trustWarning: String? = nil          // 线缆信任信号（中性措辞 "this looks unusual"）
    var certification: String? = nil         // "certified" / "certified but unlisted"
    var certificationManufacturer: String? = nil
    var xidRaw: UInt16? = nil                // 原始 XID（USB-IF 证书 ID）
    var cableVDO: UInt32? = nil              // 原始 Cable VDO（技术细节）
    var fabric: ThunderboltFabric? = nil     // Thunderbolt fabric 拓扑
    var activeTransports: [String] = []      // USB 2 / USB 3 / Thunderbolt / DisplayPort
    var techDetailLine: String? = nil        // 原始 VID/PID 等技术细节行
    var connectedDevices: [ConnectedDevice] = []  // 结构化"已连接设备"（充电器/手机/显示器/扩展坞/外设）
}

// MARK: - 电源/电池状态

struct PowerState {
    var externalConnected = false
    var isCharging = false
    var fullyCharged = false
    var voltageMV: Double = 0
    var amperageMA: Double = 0
    var batteryPercent: Int = 0

    // 充电器/适配器信息（AppleSmartBattery AdapterDetails / PowerDistribution）
    var adapterWatts: Double = 0        // 适配器额定功率（如 100W）
    var adapterVoltageMV: Double = 0    // 适配器额定电压（20V → 20000mV）
    var adapterCurrentMA: Double = 0    // 适配器额定电流（4.99A → 4990mA）
    var adapterDescription: String?     // "pd charger"
    var isMagSafeAdapter = false        // 当前活动电源源是否 MagSafe 无线充电器（AdapterDetails.IsWireless）
    var magSafeConnected = false        // MagSafe 充电器物理接入（AppleTCControllerType11.ConnectionActive），与活动电源源无关
    var usbCChargerAttached = false     // USB-C 端口物理接入（AppleTCControllerType10.ConnectionActive 任一为 true；USB-C 专属，MagSafe=AppleTCControllerType11 天然排除）
    var usbCChargerPortNumbers: [Int] = []   // 实际有物理接入的 Type10 控制器 PortNumber（1/2…），用于把充电器归入正确物理口
    var inputPowerMW: Double = 0        // 当前实际输入功率（IPDInputPower）
    var inputVoltageMV: Double = 0      // 当前输入电压（IPDInputVoltage）
    var inputCurrentMA: Double = 0      // 当前输入电流（IPDInputCurrent）

    // PowerTelemetryData（系统端进电，用于线缆电阻估算）
    var systemVoltageInMV: Double = 0   // 系统端电压（SystemVoltageIn）
    var systemCurrentInMA: Double = 0   // 系统端电流（SystemCurrentIn）
    var systemPowerInMW: Double = 0     // 系统端功率（SystemPowerIn）

    var wattsNow: Double {
        let v = voltageMV / 1000.0
        let a = abs(amperageMA) / 1000.0
        return v * a
    }
    var batteryLine: String {
        var parts: [String] = []
        if externalConnected {
            parts.append("已接入电源")
            if isCharging { parts.append("充电中") }
            else if fullyCharged { parts.append("电量已满") }
            else { parts.append("未充电") }
        } else {
            parts.append("使用电池")
        }
        parts.append("\(batteryPercent)%")
        return parts.joined(separator: " · ")
    }
}

// MARK: - 设置

struct AppSettings {
    var hideEmptyPorts = false
    var launchAtLogin = false
    var showBatterySummary = true
}
