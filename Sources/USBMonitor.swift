import Foundation
import IOKit
import IOKit.usb
import IOKit.ps
import Combine

/// IOKit 数据源：枚举 USB 端口/设备、读取电源状态，全部为只读操作。
/// 采用事件驱动（IOServiceAddMatchingNotification + IOPS 通知），
/// 仅在硬件状态变化时刷新，无轮询、无辅助进程。
final class USBMonitor: ObservableObject {
    @Published private(set) var ports: [PortCardModel] = []
    @Published var power: PowerState = PowerState()
    /// 最近一次全量刷新时间（刷新按钮反馈：点击后时间戳立即更新，UI 可见刷新生效）
    @Published private(set) var lastRefreshAt: Date?
    /// Thunderbolt fabric（每 lane 速度 / 代数 / switch 拓扑 / 活跃 tunnel）
    @Published private(set) var fabric: ThunderboltFabric = ThunderboltFabric()
    /// Pro：功率历史采样存储（由 AppDelegate 挂接，2 秒定时采样）
    var powerStore: PowerMonitorStore?
    /// 连接/断开变化回调（AppDelegate 挂接弹系统通知；CLI 不触发）
    var onConnectionChange: ((String, String) -> Void)?

    /// 插拔事件（扫描透视 / 粒子爆开动画触发源；仅 UI 使用，不影响 CLI 输出）
    struct PlugEvent: Equatable {
        let portKey: String      // "C1" / "MS"（与 detectConnectionChanges 的 key 一致）
        let isInsert: Bool
        let timestamp: Date
    }
    /// 最近一次插拔事件；变化时发布（无插拔变化则不更新）
    @Published var lastPlugEvent: PlugEvent?

    private var rawPorts: [RawPort] = []
    private var rawDevices: [USBDeviceInfo] = []
    private var lastConnectionMap: [String: Bool] = [:]

    private var usbMatchedIterator: io_iterator_t = 0
    private var usbTerminatedIterator: io_iterator_t = 0
    private var notificationPort: IONotificationPortRef?
    private var runLoopSource: CFRunLoopSource?
    private var psSource: CFRunLoopSource?

    struct RawPort {
        let id: UInt64
        let portNumber: Int
        let portType: String      // "SS" / "HS"
        let isMagSafe: Bool
        let service: io_service_t
    }

    // MARK: - 生命周期

    func start() {
        refresh()
        registerUSBNotifications()
        registerPowerNotifications()
    }

    func stop() {
        if let port = notificationPort {
            IONotificationPortDestroy(port)
            notificationPort = nil
        }
        if runLoopSource != nil {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            runLoopSource = nil
        }
        if psSource != nil {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), psSource, .commonModes)
            psSource = nil
        }
    }

    /// 全量刷新快照（事件驱动触发）
    func refresh() {
        let start = CFAbsoluteTimeGetCurrent()
        rawPorts = enumeratePorts()
        rawDevices = enumerateDevices()
        power = readPowerState()
        fabric = ThunderboltFabricReader.readFabric()
        ports = Diagnostics.buildCards(ports: rawPorts, devices: rawDevices, power: power, fabric: fabric)
        detectConnectionChanges()
        lastRefreshAt = Date()
        _ = start
    }

    /// 连接/断开变化检测：对比各端口连接状态快照，变化时回调通知描述。
    private func detectConnectionChanges() {
        var currentMap: [String: Bool] = [:]
        for card in ports {
            let key = card.isMagSafe ? "MS\(card.portNumber)" : "C\(card.portNumber)"
            currentMap[key] = card.isConnected
        }
        guard !lastConnectionMap.isEmpty else {
            lastConnectionMap = currentMap
            return
        }
        var inserted: [String] = []
        var removed: [String] = []
        for (key, connected) in currentMap where connected {
            if lastConnectionMap[key] != true { inserted.append(key) }
        }
        for (key, connected) in lastConnectionMap where connected {
            if currentMap[key] != true { removed.append(key) }
        }
        lastConnectionMap = currentMap
        // 发布插拔事件（UI 动画触发源；与系统通知互不干扰）
        if let firstInsert = inserted.first {
            lastPlugEvent = PlugEvent(portKey: firstInsert, isInsert: true, timestamp: Date())
        } else if let firstRemove = removed.first {
            lastPlugEvent = PlugEvent(portKey: firstRemove, isInsert: false, timestamp: Date())
        }
        guard let callback = onConnectionChange, !inserted.isEmpty || !removed.isEmpty else { return }

        var title: String
        var body: String
        if !inserted.isEmpty {
            title = "线缆已连接"
            body = inserted.map { portLabel($0) }.joined(separator: "、") + " 检测到连接"
        } else {
            title = "线缆已断开"
            body = removed.map { portLabel($0) }.joined(separator: "、") + " 已断开"
        }
        callback(title, body)
    }

    private func portLabel(_ key: String) -> String {
        key.hasPrefix("MS") ? "MagSafe" : "TypeC \(key.dropFirst())"
    }

    /// 事件驱动双读：插拔瞬间 IOKit 电源/控制器状态存在固件级更新延迟
    /// （IOPS 通知先到、AppleSmartBattery.ExternalConnected / Type10 ConnectionActive 后更新），
    /// 立即刷新一次后延迟 300ms 再刷新一次，保证"插上即正确识别"。
    private func refreshTwice() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.refresh()
        }
    }

    /// 便捷：按端口号（物理端口编号）读取该端口下的线缆 e-marker 详情（Pro 协商诊断用）
    func eMarkerDetail(portIndex: Int) -> USBMonitor.CableEMarkerDetail? {
        guard let raw = rawPorts.first(where: { $0.portNumber == portIndex }) else { return nil }
        return readCableEMarker(for: raw)
    }

    // MARK: - 端口枚举

    private func enumeratePorts() -> [RawPort] {
        var result: [RawPort] = []
        var iterator: io_iterator_t = 0
        // Apple Silicon: AppleTypeCPhy（含 AppleT8122TypeCPhy）；Intel: IOUSBHostPort；MagSafe 3: AppleTCControllerType11
        let matchNames = ["AppleTypeCPhy", "IOUSBHostPort", "AppleTCControllerType11"]
        for name in matchNames {
            guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(name), &iterator) == KERN_SUCCESS else {
                continue
            }
            while case let service = IOIteratorNext(iterator), service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                      let dict = props?.takeRetainedValue() as? [String: Any] else {
                    IOObjectRelease(service)
                    continue
                }
                let className = className(of: service)
                let isMagSafe = className.contains("TCControllerType11") || className.contains("MagSafe")
                let portNumber: Int
                if isMagSafe {
                    // 从节点名 "Port-MagSafe 3@1" 提取端口号
                    let name = entryName(of: service)
                    portNumber = extractMagSafePortNumber(from: name)
                } else {
                    portNumber = (dict["AppleTypeCPhyID"] as? NSNumber)?.intValue
                        ?? (dict["PortNumber"] as? NSNumber)?.intValue
                        ?? 0
                }
                let portType = isMagSafe ? "MS" : "SS" // MagSafe 3 专用充电口
                let entryID = registryEntryID(of: service)
                result.append(RawPort(id: entryID, portNumber: portNumber, portType: portType, isMagSafe: isMagSafe, service: service))
                IOObjectRelease(service)
            }
            IOObjectRelease(iterator)
        }
        // 按端口号排序
        result.sort { $0.portNumber < $1.portNumber }
        return result
    }

    // MARK: - 设备枚举

    /// 调试入口：暴露私有枚举结果
    func debugEnumerateAll() -> [USBDeviceInfo] { return enumerateDevices() }

    private func enumerateDevices() -> [USBDeviceInfo] {
        // KVM 兼容开关：跳过深度 USB 探测（不枚举设备树，仅保留端口/电源状态）
        if UserDefaults.standard.bool(forKey: "skipDeepUSBProbe") { return [] }
        var result: [USBDeviceInfo] = []
        var seen: Set<UInt64> = []
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            if let info = makeDeviceInfo(for: service) {
                seen.insert(registryEntryID(of: service))
                result.append(info)
            }
            IOObjectRelease(service)
        }
        // 补充 IOUSBDevice 匹配（Intel 旧平台 / 未暴露 IOUSBHostDevice 的节点），按 registry id 去重
        var legacyIterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBDevice"), &legacyIterator) == KERN_SUCCESS {
            while case let service = IOIteratorNext(legacyIterator), service != 0 {
                let eid = registryEntryID(of: service)
                if !seen.contains(eid), let info = makeDeviceInfo(for: service) {
                    seen.insert(eid)
                    result.append(info)
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(legacyIterator)
        }
        return result
    }

    private func makeDeviceInfo(for service: io_service_t) -> USBDeviceInfo? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else {
            return nil
        }

        let entryID = registryEntryID(of: service)
        let locationID = (dict["locationID"] as? NSNumber)?.uint32Value ?? 0
        let vendorID = (dict["idVendor"] as? NSNumber)?.uint16Value ?? 0
        let productID = (dict["idProduct"] as? NSNumber)?.uint16Value ?? 0
        let vendorName = dict["USB Vendor Name"] as? String
        let productName = dict["USB Product Name"] as? String
        let serial = dict["USB Serial Number"] as? String
        let speedRaw = (dict["Device Speed"] as? NSNumber)?.uint8Value ?? 0
        let bcdUSB = (dict["bcdUSB"] as? NSNumber)?.uint16Value
        let usbVersion = bcdUSB.map { String(format: "%x.%02x", $0 >> 8, $0 & 0xFF) }
        let busPower = (dict["Bus Power Available"] as? NSNumber).map { $0.intValue * 2 }
        let current = (dict["Requested Power"] as? NSNumber).map { $0.intValue * 2 }
        let deviceClass = (dict["bDeviceClass"] as? NSNumber)?.uint8Value

        // 向上遍历找所属物理端口。
        // Apple Silicon：AppleUSB20/30XHCIARMPort（PortNumber=1/2，与 Type10 控制器 PortNumber 一致，
        // 但端口卡编号用 AppleTypeCPhyID=0/1，故 PortNumber-1 换算为 TypeC 编号）；
        // Intel：IOUSBHostPort（PortNumber 直接对应端口卡编号）。
        // 挂载层级：设备经扩展坞/集线器时，walkUp 会经过 hub 内部 IOUSBHostPort，需识别并计数，
        // 继续向上直到物理端口锚点（保留 "via N hubs" 语义）。
        var portNumber: Int?
        var portType: String?
        var hubCount = 0
        var hubNames: [String] = []
        walkUp(from: service) { parent in
            var pprops: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(parent, &pprops, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let pdict = pprops?.takeRetainedValue() as? [String: Any],
               let pn = (pdict["PortNumber"] as? NSNumber)?.intValue {
                let cn = className(of: parent)
                if ProcessInfo.processInfo.environment["WALKUP_DEBUG"] != nil {
                    let pnm = entryName(of: parent)
                    let conf = IOObjectConformsTo(parent, "IOUSBHostPort")
                    let hp = parentService(of: parent)
                    let hhub = hp != 0 ? isHubService(hp) : false
                    if hp != 0 { IOObjectRelease(hp) }
                    print("  [WALKUP] \(cn) name=\(pnm) PortNumber=\(pn) conformsIOUSBHostPort=\(conf) parentIsHub=\(hhub) product=\(serviceProductName(of: parent) ?? "-")")
                }
                if IOObjectConformsTo(parent, "IOUSBHostPort") != 0 {
                    // hub 内部下行口：父节点是集线器/扩展坞 → 计数并继续向上
                    let hubParent = parentService(of: parent)
                    if hubParent != 0, isHubService(hubParent) {
                        let hn = serviceProductName(of: hubParent)
                        IOObjectRelease(hubParent)
                        hubCount += 1
                        if let hn, !hn.isEmpty { hubNames.append(hn) }
                        return true
                    }
                    portNumber = pn
                    portType = cn.contains("USB30") ? "SS" : "HS"
                    return false
                }
                if cn.contains("AppleUSB20XHCIARMPort") || cn.contains("AppleUSB30XHCIARMPort") {
                    portNumber = pn - 1  // XHCI PortNumber=1/2 → TypeC 编号 0/1
                    portType = cn.contains("USB30") ? "SS" : "HS"
                    return false
                }
            }
            return true
        }

        let isBillboard = deviceClass == 0x11
        return USBDeviceInfo(
            id: entryID,
            locationID: locationID,
            vendorID: vendorID,
            productID: productID,
            vendorName: vendorName,
            productName: productName,
            serialNumber: serial,
            usbVersion: usbVersion,
            speedRaw: speedRaw,
            busPowerMA: busPower,
            currentMA: current,
            ioClassName: className(of: service),
            portNumber: portNumber,
            portType: portType,
            deviceClass: deviceClass,
            isBillboard: isBillboard,
            hubCount: hubCount,
            hubChain: hubNames
        )
    }

    // MARK: - 电源状态

    func readPowerState() -> PowerState {
        var state = PowerState()

        // AppleSmartBattery（本机唯一电源数据源，IOPS 描述不在 CLT SDK 中暴露）
        var iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iterator) == KERN_SUCCESS {
            if case let service = IOIteratorNext(iterator), service != 0 {
                var props: Unmanaged<CFMutableDictionary>?
                if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                   let dict = props?.takeRetainedValue() as? [String: Any] {
                    state.externalConnected = (dict["ExternalConnected"] as? NSNumber)?.boolValue ?? false
                    // IsCharging 优先读顶层键，偶发缺失/固件切换延迟时用 ChargerData.IsCharging 兜底（实机验证两值一致）
                    var isCharging = (dict["IsCharging"] as? NSNumber)?.boolValue ?? false
                    if !isCharging, let cd = dict["ChargerData"] as? [String: Any],
                       (cd["IsCharging"] as? NSNumber)?.boolValue == true {
                        isCharging = true
                    }
                    state.isCharging = isCharging
                    state.fullyCharged = (dict["FullyCharged"] as? NSNumber)?.boolValue ?? false
                    state.voltageMV = (dict["Voltage"] as? NSNumber)?.doubleValue ?? 0
                    let amp = (dict["Amperage"] as? NSNumber)?.doubleValue ?? 0
                    // Amperage 为 int32 位模式存储，负值表示放电
                    state.amperageMA = Double(Int32(bitPattern: UInt32(truncatingIfNeeded: Int64(amp))))
                    state.batteryPercent = (dict["CurrentCapacity"] as? NSNumber)?.intValue ?? 0

                    // 充电器信息：AdapterDetails（额定规格）
                    if let adapter = dict["AdapterDetails"] as? [String: Any] {
                        state.adapterWatts = (adapter["Watts"] as? NSNumber)?.doubleValue ?? 0
                        state.adapterVoltageMV = (adapter["AdapterVoltage"] as? NSNumber)?.doubleValue ?? 0
                        state.adapterCurrentMA = (adapter["Current"] as? NSNumber)?.doubleValue ?? 0
                        state.adapterDescription = adapter["Description"] as? String
                        if let wireless = (adapter["IsWireless"] as? NSNumber)?.boolValue {
                            state.isMagSafeAdapter = wireless
                        }
                    }
                    // 修正适配器额定功率：AdapterDetails.Watts 可能命中系统缓存的旧适配器条目
                    // （实机验证：仅插 70W USB-C Power Adapter（68W）时 BestAdapterIndex 仍指向
                    // 缓存的 100W 条目，导致 adapterWatts 误报 100W）。AppleRawAdapterDetails
                    // 数组中带 Name 的条目才是真实物理接入的原装适配器，用其 Watts 覆盖缓存值。
                    if let rawList = dict["AppleRawAdapterDetails"] as? [Any] {
                        for case let raw as [String: Any] in rawList {
                            guard let rawName = raw["Name"] as? String, !rawName.isEmpty else { continue }
                            if let rawWatts = (raw["Watts"] as? NSNumber)?.doubleValue, rawWatts > 1 {
                                state.adapterWatts = rawWatts
                                break
                            }
                        }
                    }
                    // 充电器信息：PowerDistribution（实时输入）
                    if let dist = dict["PowerDistribution"] as? [String: Any] {
                        state.inputPowerMW = (dist["IPDInputPower"] as? NSNumber)?.doubleValue ?? 0
                        state.inputVoltageMV = (dist["IPDInputVoltage"] as? NSNumber)?.doubleValue ?? 0
                        state.inputCurrentMA = (dist["IPDInputCurrent"] as? NSNumber)?.doubleValue ?? 0
                    }
                    // 系统端进电遥测（线缆电阻估算）
                    if let tel = dict["PowerTelemetryData"] as? [String: Any] {
                        state.systemVoltageInMV = (tel["SystemVoltageIn"] as? NSNumber)?.doubleValue ?? 0
                        state.systemCurrentInMA = (tel["SystemCurrentIn"] as? NSNumber)?.doubleValue ?? 0
                        state.systemPowerInMW = (tel["SystemPowerIn"] as? NSNumber)?.doubleValue ?? 0
                    }
                }
                IOObjectRelease(service)
            }
            IOObjectRelease(iterator)
        }

        // MagSafe 物理接入：读 AppleTCControllerType11（Port-MagSafe 3）的 ConnectionActive。
        // 该信号独立于 AdapterDetails（AdapterDetails 只描述当前活动电源源，
        // 同时插入 MagSafe + USB-C 时即使 MagSafe 插着也会显示 USB-C 充电器数据，不能用它判断 MagSafe）。
        var msIterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleTCControllerType11"), &msIterator) == KERN_SUCCESS {
            while case let ms = IOIteratorNext(msIterator), ms != 0 {
                if let conn = IORegistryEntryCreateCFProperty(ms, "ConnectionActive" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber, conn.boolValue {
                    state.magSafeConnected = true
                }
                IOObjectRelease(ms)
            }
            IOObjectRelease(msIterator)
        }

        // USB-C 端口物理接入：枚举 AppleTCControllerType10（USB-C 专属控制器，本机 2 个），
        // 任一 ConnectionActive==true 即 USB-C 端口有物理接入（充电器或设备，配合设备树为空确认充电器）。
        // 注意不能用 PortControllerInfo.MaxPower 判定——实机确认 MagSafe 充电时其 [2] 条目
        // PortControllerMaxPower=99800 非 0，会被误判为 USB-C 充电器；MagSafe 控制器是
        // AppleTCControllerType11，此处枚举 Type10 天然排除。
        var tc10Iterator: io_iterator_t = 0
        if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleTCControllerType10"), &tc10Iterator) == KERN_SUCCESS {
            while case let tc10 = IOIteratorNext(tc10Iterator), tc10 != 0 {
                if let conn = IORegistryEntryCreateCFProperty(tc10, "ConnectionActive" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber, conn.boolValue {
                    state.usbCChargerAttached = true
                    // 记录实际有物理接入的控制器 PortNumber（实机：近 MagSafe 口=1，远 MagSafe 口=2，与 AppleTypeCPhyID 差 1）
                    if let pn = IORegistryEntryCreateCFProperty(tc10, "PortNumber" as CFString, kCFAllocatorDefault, 0)?
                        .takeRetainedValue() as? NSNumber {
                        state.usbCChargerPortNumbers.append(pn.intValue)
                    }
                }
                IOObjectRelease(tc10)
            }
            IOObjectRelease(tc10Iterator)
        }
        return state
    }

    // MARK: - 通知注册

    private func registerUSBNotifications() {
        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        notificationPort = port

        let matching = IOServiceMatching("IOUSBHostDevice")
        let matched = IOServiceAddMatchingNotification(
            port, "IOServiceFirstMatch", matching,
            { _, _ in
                DispatchQueue.main.async { USBMonitor.shared?.refreshTwice() }
            },
            Unmanaged.passUnretained(self).toOpaque(), &usbMatchedIterator
        )
        if matched == KERN_SUCCESS {
            // 排空初始通知
            drain(iterator: usbMatchedIterator)
            attachRunLoop(port: port)
        }

        let matching2 = IOServiceMatching("IOUSBHostDevice")
        let terminated = IOServiceAddMatchingNotification(
            port, "IOServiceTerminate", matching2,
            { _, _ in
                DispatchQueue.main.async { USBMonitor.shared?.refresh() }
            },
            Unmanaged.passUnretained(self).toOpaque(), &usbTerminatedIterator
        )
        if terminated == KERN_SUCCESS {
            drain(iterator: usbTerminatedIterator)
            attachRunLoop(port: port)
        }
    }

    private func attachRunLoop(port: IONotificationPortRef) {
        guard runLoopSource == nil else { return }
        if let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = source
        }
    }

    /// 电源事件双读：IOPS 电源通知先于 AppleSmartBattery 固件字段更新到达，
    /// 立即刷新一次后延迟 3.0s 再刷新一次，覆盖充电器插入握手（PD 协商、充电
    /// 管理决策）延迟窗口。实机验证握手期间 ExternalConnected 先翻 Yes、而
    /// IsCharging / Amperage 需 1~3s 才稳定，1.0s 双读落在窗口内会误报
    /// "已接入电源 · 未充电"，故二次读延迟放宽到 3.0s。
    /// 充电器插入不触发 USB 设备通知，仅依赖此电源通知路径，延迟需比 USB 双读更宽裕。
    private func refreshPowerTwice() {
        refresh()
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.refresh()
        }
    }

    private func registerPowerNotifications() {
        if let source = IOPSNotificationCreateRunLoopSource({ _ in
            DispatchQueue.main.async { USBMonitor.shared?.refreshPowerTwice() }
        }, nil)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            psSource = source
        }
    }

    private func drain(iterator: io_iterator_t) {
        while case let service = IOIteratorNext(iterator), service != 0 {
            IOObjectRelease(service)
        }
    }

    // MARK: - IOKit 小工具

    private func className(of service: io_service_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        guard IOObjectGetClass(service, &buf) == KERN_SUCCESS else { return "?" }
        return String(cString: buf)
    }

    private func registryEntryID(of service: io_service_t) -> UInt64 {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        return id
    }

    private func entryName(of service: io_service_t) -> String {
        var buf = [CChar](repeating: 0, count: 128)
        guard IORegistryEntryGetName(service, &buf) == KERN_SUCCESS else { return "" }
        return String(cString: buf)
    }

    /// 取父节点（kIOServicePlane），调用方负责 IOObjectRelease
    private func parentService(of service: io_service_t) -> io_service_t {
        var parent: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(service, kIOServicePlane, &parent) == KERN_SUCCESS else { return 0 }
        return parent
    }

    /// 读节点的 USB 产品名
    private func serviceProductName(of service: io_service_t) -> String? {
        IORegistryEntryCreateCFProperty(service, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? String
    }

    /// 判断节点是否集线器/扩展坞（IOUSBHostHub / IOUSBHub / 类名含 Hub）
    private func isHubService(_ service: io_service_t) -> Bool {
        if IOObjectConformsTo(service, "IOUSBHostHub") != 0 { return true }
        if IOObjectConformsTo(service, "IOUSBHub") != 0 { return true }
        let cn = className(of: service)
        return cn.contains("Hub") || cn.contains("hub")
    }

    /// 从 "Port-MagSafe 3@1" 提取端口号 1
    private func extractMagSafePortNumber(from name: String) -> Int {
        if let range = name.range(of: "@") {
            let tail = name[range.upperBound...].trimmingCharacters(in: .whitespaces)
            return Int(tail) ?? 0
        }
        // 兜底：从 "Port-MagSafe N" 提取 N
        let parts = name.split(separator: " ").compactMap { Int($0) }
        return parts.last ?? 0
    }

    /// 向上遍历父链，handler 返回 false 时停止。
    /// 注意：parent 由 GetParentEntry 返回（引用计数 +1）。
    /// 必须把引用转移给 current（不再 release），否则下一轮取父时 current 悬垂失效，
    /// 导致多级 hub 链（扩展坞后挂设备）无法走到物理端口锚点。
    private func walkUp(from service: io_service_t, handler: (io_service_t) -> Bool) {
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
            // 引用转移：parent 的 +1 交给 current 持有；旧 current 若不是入口 service 则释放
            if current != service { IOObjectRelease(current) }
            current = parent
        }
    }

    static var shared: USBMonitor?
}
