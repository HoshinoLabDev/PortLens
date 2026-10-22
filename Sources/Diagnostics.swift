import Foundation
import IOKit

/// 诊断引擎：将 IOKit 原始数据转换为用户友好的卡片内容。
/// 逻辑对齐 USB-C 诊断核心能力（充电诊断、速度诊断、PDO、e-marker）。
enum Diagnostics {

    // MARK: - 卡片组装

    static func buildCards(ports: [USBMonitor.RawPort], devices: [USBDeviceInfo], power: PowerState, fabric: ThunderboltFabric) -> [PortCardModel] {
        // 设备挂载到端口
        var byPort: [Int: [USBDeviceInfo]] = [:]
        var unanchored: [USBDeviceInfo] = []
        for device in devices {
            if let pn = device.portNumber {
                byPort[pn, default: []].append(device)
            } else {
                unanchored.append(device)
            }
        }

        // 显示器（EDID）与充电器（SOP 节点）识别，按端口编号索引
        let displays = DisplayEDIDReader.readDisplays()
        var chargers: [Int: ChargerIdentity] = [:]
        for port in ports where !port.isMagSafe {
            if let ci = ChargerIdentityReader.read(for: port.portNumber) {
                chargers[port.portNumber] = ci
            }
        }

        var cards: [PortCardModel] = []
        for (index, port) in ports.enumerated() {
            let portDevices = byPort[port.portNumber] ?? []
            let card = buildCard(for: port, index: index, devices: portDevices, power: power, fabric: fabric,
                                 displays: displays, chargers: chargers)
            cards.append(card)
        }

        // 无物理端口锚点的设备（Thunderbolt 隧道等）汇总为一张卡
        if !unanchored.isEmpty {
            cards.append(buildUnanchoredCard(devices: unanchored, power: power, index: cards.count, fabric: fabric))
        }

        // 纯充电器兜底：USB-C 端口有物理接入（usbCChargerAttached）且设备树为空时，把充电器归入实际的 USB-C 端口。
        // usbCChargerAttached 来自 AppleTCControllerType10.ConnectionActive（USB-C 专属控制器，MagSafe=AppleTCControllerType11 天然排除；
        // 不能用 PortControllerInfo.MaxPower——MagSafe 充电时其条目 MaxPower=99800 会被误判），
        // 保证仅连 MagSafe 时绝不显示 USB-C"充电器已连接"兜底卡；USB-C 充电器接入时（含与 MagSafe 并存）正常显示。
        // 实机映射：Type10 PortNumber=1 ↔ 近 MagSafe 口（PhyID=0 → TypeC 0），PortNumber=2 ↔ 远 MagSafe 口（PhyID=1 → TypeC 1），
        // 即 TypeC 编号 = Type10.PortNumber - 1；usbCChargerPortNumbers 记录了实际有连接的控制器，据此归入正确口。
        if power.externalConnected, devices.isEmpty {
            if power.usbCChargerAttached {
                // 优先把充电器归入实际有物理接入的 USB-C 口；找不到时兜底到首个空闲 USB-C 口。
                // 修复反向误报：Type10 端口若已由 buildCard 正常构建（isConnected=true，如已识别出
                // 充电器身份），必须视为已分配并 break，严禁 fallback 再把"未知充电器"覆盖到其他空口。
                var assigned = false
                for pn in power.usbCChargerPortNumbers {
                    let typeCIndex = pn - 1  // Type10 PortNumber → TypeC 编号
                    if let idx = cards.firstIndex(where: { !$0.isMagSafe && ($0.portNumber ?? -1) == typeCIndex }) {
                        if cards[idx].isConnected {
                            // 该口已正确呈现连接状态（充电器/设备），无需兜底覆盖
                            assigned = true
                            break
                        }
                        let pn2 = cards[idx].portNumber ?? idx
                        cards[idx] = buildChargerCard(power: power, index: idx, portNumber: pn2,
                                                      chargerIdentity: chargers[typeCIndex])
                        assigned = true
                        break
                    }
                }
                if !assigned, let idx = cards.firstIndex(where: { !$0.isMagSafe && !$0.isConnected }) {
                    let pn2 = cards[idx].portNumber ?? idx
                    cards[idx] = buildChargerCard(power: power, index: idx, portNumber: pn2,
                                                  chargerIdentity: chargers[pn2])
                }
            } else if !power.magSafeConnected {
                // 二级兜底：外部电源已接入（AppleSmartBattery.ExternalConnected=Yes，电源侧强信号）
                // 但 Type10/Type11 物理接入信号偶发枚举失败/遗漏（插拔瞬间固件更新延迟、迭代器异常）时，
                // 只要设备树为空且 MagSafe 未接入，仍把充电器归入首个空闲 USB-C 口，
                // 避免系统已在充电但 PortLens"识别不到充电器"。MagSafe 已接入场景由 MagSafe 卡负责，不受影响。
                // 修复反向误报：若已有 USB-C 口被 buildCard 正常呈现为连接状态（如已识别充电器），
                // 说明端口已正确呈现，不再往其他空口覆盖充电器卡。
                if !cards.contains(where: { !$0.isMagSafe && $0.isConnected }) {
                    if let idx = cards.firstIndex(where: { !$0.isMagSafe && !$0.isConnected }) {
                        let pn2 = cards[idx].portNumber ?? idx
                        cards[idx] = buildChargerCard(power: power, index: idx, portNumber: pn2,
                                                      chargerIdentity: chargers[pn2])
                    }
                }
            }
        }
        return cards
    }

    // MARK: - 单端口卡片

    private static func buildCard(for port: USBMonitor.RawPort, index: Int, devices: [USBDeviceInfo], power: PowerState, fabric: ThunderboltFabric,
                                  displays: [(portNumber: Int?, device: ConnectedDevice)], chargers: [Int: ChargerIdentity]) -> PortCardModel {
        let label = port.isMagSafe ? "MagSafe" : "TypeC \(port.portNumber)"
        let portBadge = port.isMagSafe ? "MS" : (port.portType == "SS" ? "SS" : "HS")

        // MagSafe 专用充电口：不依赖 USB 设备树
        if port.isMagSafe {
            return buildMagSafeCard(port: port, index: index, power: power)
        }

        // 空端口（USB4/仅供电线缆可能无 USB 设备，但仍需读取 e-marker 线缆信息）
        guard !devices.isEmpty else {
            // 纯供电口：该口识别到充电器（SOP）时仍显示"充电器已连接"，避免 TypeC 1 空设备但插着充电器被误报"无设备"
            if let ci = chargers[port.portNumber] {
                return buildChargerCard(power: power, index: index, portNumber: port.portNumber, chargerIdentity: ci)
            }
            var cableLine: String?
            var cableSpec: String?
            var trustWarning: String?
            var certification: String?
            var certificationManufacturer: String?
            var xidRaw: UInt16?
            var cableVDO: UInt32?
            if let cable = readCableInfo(for: port) {
                cableLine = cable.lineDescription
                cableSpec = cable.specLine
                trustWarning = cable.trustWarning
                certification = cable.certification
                certificationManufacturer = cable.certificationManufacturer
                xidRaw = cable.xid
                cableVDO = cable.rawVDOCable
            }
            var card = PortCardModel(
                id: index, portIndex: index, portNumber: port.portNumber, portType: portBadge,
                devices: devices,
                headline: "无设备连接", headlineIcon: "cable.connector.slash", tint: .gray,
                chargingBanner: nil, chargingSub: nil,
                dataLine: nil, cableLine: cableLine, cableSpec: cableSpec, deviceLine: nil,
                pdoList: nil, faultText: nil, isConnected: false, isMagSafe: false
            )
            card.connectedDevices = displaysFor(port: port.portNumber, displays)
            card.trustWarning = trustWarning
            card.certification = certification
            card.certificationManufacturer = certificationManufacturer
            card.xidRaw = xidRaw
            card.cableVDO = cableVDO
            card.fabric = fabric.detected ? fabric : nil
            return card
        }

        // 判断是否充电器（纯电源设备：没有数据能力的设备）
        let hasDisplay = detectDisplayTunnel(for: port)
        let hasDataDevice = devices.contains { !$0.isBillboard }
        let looksLikeCharger = power.externalConnected && !hasDisplay

        // 标题与图标
        var headline = "USB 设备"
        var icon = "cable.connector"
        var tint: PortTint = .blue

        if hasDisplay {
            headline = "显示器已连接"
            icon = "display"
            tint = .purple
        } else if devices.contains(where: { isThunderboltLike($0) }) {
            headline = "Thunderbolt / USB4"
            icon = "bolt.fill"
            tint = .purple
        } else if devices.contains(where: { $0.isSuperSpeed }) {
            let top = devices.map(\.speedGbps).compactMap { $0 }.max() ?? 5
            headline = "USB 设备 · \(Int(top)) Gbps"
            icon = "cable.connector.horizontal"
            tint = .blue
        } else if hasDataDevice {
            headline = "慢速 USB / 仅充电线缆"
            icon = "exclamationmark.triangle.fill"
            tint = .orange
        } else if looksLikeCharger {
            headline = "充电器已连接"
            icon = "power"
            tint = .green
        }

        // 充电诊断：仅当该端口识别到充电器身份时才显示电源横幅。
        // 全局 externalConnected 只说明系统接入外部电源（可能来自 TypeC 1 充电器），
        // 若无条件渲染，TypeC 0（仅扩展坞、无充电器）也会误显"已接入电源 · 未充电"。
        let charging: ChargingInfo
        if chargers[port.portNumber] != nil {
            charging = chargingInfo(power: power, portLabel: label)
        } else {
            charging = ChargingInfo(banner: nil, sub: nil)
        }

        // 数据速度行
        var dataLine: String?
        if hasDisplay {
            dataLine = "DisplayPort 备用模式"
        } else if let top = devices.compactMap(\.speedGbps).max() {
            dataLine = "协商速度 \(Int(top)) Gbps"
        } else if let fastest = devices.max(by: { $0.speedRaw < $1.speedRaw }) {
            dataLine = fastest.speedLabel
        }

        // 线缆信息行（e-marker）
        var cableLine: String?
        var cableSpec: String?
        var trustWarning: String?
        var certification: String?
        var certificationManufacturer: String?
        var xidRaw: UInt16?
        var cableVDO: UInt32?
        if let cable = readCableInfo(for: port) {
            cableLine = cable.lineDescription
            cableSpec = cable.specLine
            trustWarning = cable.trustWarning
            certification = cable.certification
            certificationManufacturer = cable.certificationManufacturer
            xidRaw = cable.xid
            cableVDO = cable.rawVDOCable
        }

        // 设备行
        var deviceLine: String?
        if !devices.isEmpty {
            let names = devices.prefix(3).map(\.displayName).joined(separator: "、")
            deviceLine = devices.count > 3 ? "\(names) 等 \(devices.count) 个设备" : names
        }

        // 结构化"已连接设备"：设备分类 + 显示器（EDID）+ 充电器（SOP，纯供电场景）
        var connected: [ConnectedDevice] = devices.compactMap { DeviceClassifier.makeConnectedDevice(from: $0) }
        connected.append(contentsOf: displaysFor(port: port.portNumber, displays))
        if looksLikeCharger, let ci = chargers[port.portNumber],
           !connected.contains(where: { $0.kind == .charger }) {
            connected.append(ci.makeConnectedDevice(watts: power.adapterWatts))
        }
        connected = sortedDeviceList(connected)

        // PDO 列表：仅充电器身份端口读取并展示（标题含"充电器功率档位"）。
        // TypeC 0 扩展坞内部 PD 芯片也有 PDO 档位，但该口未接电源，渲染会误导为供电相关。
        let pdoList: [PDOProfile]?
        if chargers[port.portNumber] != nil {
            pdoList = readPDOList(typeCIndex: port.portNumber)
        } else {
            pdoList = nil
        }

        // Active transports：明示 USB 2 / USB 3 / Thunderbolt / DisplayPort 活跃传输
        var transports: [String] = []
        if hasDisplay { transports.append("DisplayPort") }
        if devices.contains(where: { isThunderboltLike($0) }) { transports.append("Thunderbolt") }
        if devices.contains(where: { $0.isSuperSpeed }) { transports.append("USB 3") }
        if devices.contains(where: { $0.isSlowUSB }) { transports.append("USB 2") }
        if transports.isEmpty {
            // 仅有线缆无设备时按 e-marker 速度归类
            if let c = readCableInfo(for: port) {
                switch c.speedLabel {
                case "USB 2.0": transports.append("USB 2")
                case "5 Gbps", "20 Gbps", "40 Gbps", "80 Gbps": transports.append("USB 3")
                default: break
                }
            }
        }

        var card = PortCardModel(
            id: index, portIndex: index, portNumber: port.portNumber, portType: portBadge,
            devices: devices,
            headline: headline, headlineIcon: icon, tint: tint,
            chargingBanner: charging.banner, chargingSub: charging.sub,
            dataLine: dataLine, cableLine: cableLine, cableSpec: cableSpec, deviceLine: deviceLine,
            pdoList: pdoList, faultText: nil, isConnected: true, isMagSafe: false
        )
        card.connectedDevices = connected
        card.trustWarning = trustWarning
        card.certification = certification
        card.certificationManufacturer = certificationManufacturer
        card.xidRaw = xidRaw
        card.cableVDO = cableVDO
        card.fabric = fabric.detected ? fabric : nil
        card.activeTransports = transports
        card.techDetailLine = techDetailLine(port: port, cableVID: cableInfoVID(port: port), devices: devices)
        return card
    }

    /// 技术细节行：原始 VID / PID / XID / Cable VDO（设置"显示技术细节"时展示）
    private static func techDetailLine(port: USBMonitor.RawPort, cableVID: UInt16?, devices: [USBDeviceInfo]) -> String? {
        var parts: [String] = []
        if let d = devices.first {
            parts.append(String(format: "VID 0x%04X · PID 0x%04X", d.vendorID, d.productID))
        }
        if let vid = cableVID {
            parts.append(String(format: "e-marker VID 0x%04X", vid))
        }
        guard !parts.isEmpty else { return nil }
        return parts.joined(separator: " · ")
    }

    private static func cableInfoVID(port: USBMonitor.RawPort) -> UInt16? {
        readCableInfo(for: port)?.vendorVID
    }

    /// MagSafe 3 专用充电口卡片（无线充电，无 USB 数据树）
    private static func buildMagSafeCard(port: USBMonitor.RawPort, index: Int, power: PowerState) -> PortCardModel {
        let label = "MagSafe"

        // 未接入 MagSafe 充电器：AppleTCControllerType11.ConnectionActive == 0。
        // 注意不能用 externalConnected / isMagSafeAdapter 判定——AdapterDetails 只描述当前活动电源源，
        // 同时插入 MagSafe + USB-C 时 MagSafe 插着但 isMagSafeAdapter 可能为 false。
        guard power.magSafeConnected else {
            return PortCardModel(
                id: index, portIndex: index, portNumber: port.portNumber, portType: "MS",
                devices: [],
                headline: "MagSafe 未连接", headlineIcon: "magsafe.charger", tint: .gray,
                chargingBanner: nil, chargingSub: nil,
                dataLine: nil, cableLine: nil, deviceLine: nil,
                pdoList: nil, faultText: nil, isConnected: false, isMagSafe: true
            )
        }

        let charging = chargingInfo(power: power, portLabel: label)

        // MagSafe 是当前活动电源源：显示适配器额定与 MagSafe 实时输入
        if power.isMagSafeAdapter {
            let watts = power.adapterWatts > 1 ? String(format: "%.0fW", power.adapterWatts) : "USB 电源"
            let headline = "MagSafe · \(watts)"
            var dataLine: String?
            if power.adapterVoltageMV > 0, power.adapterCurrentMA > 0 {
                dataLine = String(format: "适配器 %.1fV / %.2fA", power.adapterVoltageMV / 1000.0, power.adapterCurrentMA / 1000.0)
            }
            if let desc = power.adapterDescription, !desc.isEmpty {
                dataLine = [dataLine, desc].compactMap { $0 }.joined(separator: " · ")
            }
            var deviceLine: String?
            if power.inputPowerMW > 0 {
                let w = power.inputPowerMW / 1000.0
                deviceLine = String(format: "MagSafe 输入 %.1fW（%.1fV / %.2fA）", w, power.inputVoltageMV / 1000.0, power.inputCurrentMA / 1000.0)
            }
            var card = PortCardModel(
                id: index, portIndex: index, portNumber: port.portNumber, portType: "MS",
                devices: [],
                headline: headline, headlineIcon: "magsafe.charger", tint: .green,
                chargingBanner: charging.banner, chargingSub: charging.sub,
                dataLine: dataLine, cableLine: nil, deviceLine: deviceLine,
                pdoList: readPDOList(typeCIndex: nil), faultText: nil, isConnected: true, isMagSafe: true
            )
            card.connectedDevices = [MagSafeDevice.make(power: power)]
            return card
        }

        // MagSafe 已接入但当前由 USB-C 充电器供电（同时插入场景）
        var card = PortCardModel(
            id: index, portIndex: index, portNumber: port.portNumber, portType: "MS",
            devices: [],
            headline: "MagSafe 已连接", headlineIcon: "magsafe.charger", tint: .green,
            chargingBanner: charging.banner, chargingSub: charging.sub,
            dataLine: "MagSafe 充电器已接入，当前由 USB-C 充电器供电",
            cableLine: nil, deviceLine: nil,
            pdoList: readPDOList(typeCIndex: nil), faultText: nil, isConnected: true, isMagSafe: true
        )
        card.connectedDevices = [MagSafeDevice.make(power: power)]
        return card
    }

    /// 纯 USB-C 充电器兜底卡片：外部电源来自 USB-C（非 MagSafe）且设备树为空时的充电器归属
    private static func buildChargerCard(power: PowerState, index: Int, portNumber: Int, chargerIdentity: ChargerIdentity?) -> PortCardModel {
        let watts = power.adapterWatts > 1 ? String(format: "%.0fW", power.adapterWatts) : "USB 电源"
        let charging = chargingInfo(power: power, portLabel: "TypeC")
        var dataLine: String?
        if power.adapterVoltageMV > 0, power.adapterCurrentMA > 0 {
            dataLine = String(format: "适配器 %.1fV / %.2fA", power.adapterVoltageMV / 1000.0, power.adapterCurrentMA / 1000.0)
        }
        var card = PortCardModel(
            id: index, portIndex: index, portNumber: portNumber, portType: "SS",
            devices: [],
            headline: "充电器已连接 · \(watts)", headlineIcon: "power", tint: .green,
            chargingBanner: charging.banner, chargingSub: charging.sub,
            dataLine: dataLine, cableLine: nil, deviceLine: nil,
            pdoList: readPDOList(typeCIndex: portNumber), faultText: nil, isConnected: true, isMagSafe: false
        )
        // 充电器品牌型号：优先 SOP 节点（PD Discover Identity），无法识别时兜底显示额定功率
        card.connectedDevices = [
            chargerIdentity?.makeConnectedDevice(watts: power.adapterWatts)
                ?? fallbackChargerDevice(watts: power.adapterWatts)
        ]
        return card
    }

    private static func buildUnanchoredCard(devices: [USBDeviceInfo], power: PowerState, index: Int, fabric: ThunderboltFabric) -> PortCardModel {
        let isTB = devices.contains(where: { isThunderboltLike($0) })
        var transports: [String] = []
        if devices.contains(where: { isThunderboltLike($0) }) { transports.append("Thunderbolt") }
        if devices.contains(where: { $0.isSuperSpeed }) { transports.append("USB 3") }
        if devices.contains(where: { $0.isSlowUSB }) { transports.append("USB 2") }
        var card = PortCardModel(
            id: index, portIndex: index, portNumber: nil, portType: nil,
            devices: devices,
            headline: isTB ? "Thunderbolt / USB4" : "USB 设备",
            headlineIcon: isTB ? "bolt.fill" : "cable.connector.horizontal",
            tint: isTB ? .purple : .blue,
            chargingBanner: nil, chargingSub: nil,
            dataLine: devices.compactMap(\.speedGbps).max().map { "协商速度 \(Int($0)) Gbps" },
            cableLine: nil,
            deviceLine: devices.prefix(3).map(\.displayName).joined(separator: "、"),
            pdoList: nil, faultText: nil, isConnected: true, isMagSafe: false
        )
        card.activeTransports = transports
        card.fabric = fabric.detected ? fabric : nil
        card.connectedDevices = sortedDeviceList(devices.compactMap { DeviceClassifier.makeConnectedDevice(from: $0) })
        if let d = devices.first {
            card.techDetailLine = String(format: "VID 0x%04X · PID 0x%04X", d.vendorID, d.productID)
        }
        return card
    }

    // MARK: - 已连接设备组装

    /// 按端口取显示器条目
    private static func displaysFor(port: Int?, _ displays: [(portNumber: Int?, device: ConnectedDevice)]) -> [ConnectedDevice] {
        guard let port else { return [] }
        return displays.compactMap { $0.portNumber == port ? $0.device : nil }
    }

    /// 展示排序：扩展坞/集线器 → 显示器 → 手机/平板 → 充电器 → 电脑 → 外设 → 未知
    private static func sortedDeviceList(_ items: [ConnectedDevice]) -> [ConnectedDevice] {
        let order: [DeviceKind] = [.dock, .hub, .display, .phone, .tablet, .charger, .computer, .peripheral, .unknown]
        return items.sorted { a, b in
            let ia = order.firstIndex(of: a.kind) ?? order.count
            let ib = order.firstIndex(of: b.kind) ?? order.count
            if ia != ib { return ia < ib }
            return a.hops < b.hops
        }
    }

    /// 无 SOP 节点时的充电器兜底条目（未知品牌，仅额定功率）
    private static func fallbackChargerDevice(watts: Double) -> ConnectedDevice {
        ChargerIdentity(vid: nil, pid: nil, bcdDevice: nil, productType: nil, vdos: []).makeConnectedDevice(watts: watts)
    }

    // MARK: - 充电诊断

    struct ChargingInfo { var banner: String?; var sub: String? }

    private static func chargingInfo(power: PowerState, portLabel: String) -> ChargingInfo {
        guard power.externalConnected else { return ChargingInfo(banner: nil, sub: nil) }
        let watts = power.wattsNow
        if power.isCharging {
            let w = watts > 1 ? String(format: "%.0f W", watts) : "涓流"
            return ChargingInfo(banner: "正在充电 · \(w)", sub: power.batteryLine)
        }
        if power.fullyCharged {
            var sub = "电源已接入，电池保护模式"
            if power.adapterWatts > 1 {
                sub += " · \(Int(power.adapterWatts))W 适配器"
            }
            return ChargingInfo(banner: "电量已满 · 未充电", sub: sub)
        }
        var sub = "可能启用了优化电池充电"
        if power.adapterWatts > 1 {
            sub += " · \(Int(power.adapterWatts))W 适配器"
        }
        return ChargingInfo(banner: "已接入电源 · 未充电", sub: sub)
    }

    // MARK: - 设备/端口判定

    private static func isThunderboltLike(_ d: USBDeviceInfo) -> Bool {
        let cls = d.ioClassName.lowercased()
        return cls.contains("thunderbolt") || cls.contains("usb4") || d.usbVersion?.hasPrefix("3.2") == true && d.speedRaw >= 5
    }

    private static func detectDisplayTunnel(for port: USBMonitor.RawPort) -> Bool {
        // 沿端口子树查找 DisplayPort 隧道服务
        var found = false
        var iter: io_iterator_t = 0
        if IORegistryEntryGetChildIterator(port.service, kIOServicePlane, &iter) == KERN_SUCCESS {
            while case let child = IOIteratorNext(iter), child != 0 {
                var buf = [CChar](repeating: 0, count: 128)
                if IOObjectGetClass(child, &buf) == KERN_SUCCESS {
                    let cls = String(cString: buf)
                    if cls.contains("DisplayPort") || cls.contains("Tunnel") {
                        found = true
                    }
                }
                IOObjectRelease(child)
            }
            IOObjectRelease(iter)
        }
        return found
    }

    // MARK: - e-marker 线缆信息（SOP'）

    /// 线缆 e-marker 规格（有 e-marker 的线缆才会解析出此信息）
    struct CableSpecInfo {
        let speedLabel: String
        let currentRating: Double
        let maxWatts: Int
        let isEPR: Bool
        let vendorVID: UInt16?
        let productType: String?
        let lineDescription: String

        // 第二批：USB-IF 认证 / 信任信号 / 原始 XID
        let xid: UInt16?
        let certification: String?
        let certificationManufacturer: String?
        let trustWarning: String?
        let rawVDOCable: UInt32?

        /// 规格明细行：线缆类型 · 功率 · EPR · 厂商 · 认证
        var specLine: String {
            var parts: [String] = []
            if let pt = productType { parts.append(pt) }
            parts.append("最大 \(maxWatts)W")
            if isEPR { parts.append("EPR") }
            if let vid = vendorVID { parts.append(CableVendorDB.displayName(for: vid)) }
            if let cert = certification { parts.append(certLabel(cert)) }
            return parts.joined(separator: " · ")
        }

        /// 认证标签本地化：certified / certified but unlisted 保持英文中性词
        private func certLabel(_ cert: String) -> String {
            switch cert {
            case "certified": return "USB-IF certified"
            case "certified but unlisted": return "certified but unlisted"
            default: return cert
            }
        }
    }

    private static func readCableInfo(for port: USBMonitor.RawPort) -> CableSpecInfo? {
        // e-marker 节点实际挂在 Port-USB-C@N/CC/SOP' 下，不在端口（AppleTypeCPhy）直接子树上，
        // 因此必须全树查找 IOPortTransportComponentCCUSBPDSOPp，再按 ParentPortNumber 归属端口。
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
            // 不能写 hpmPort == port.portNumber 的宽松分支——ParentPortNumber=1 会被 TypeC 1 误匹配，线缆信息错口。
            guard hpmPort - 1 == port.portNumber else { continue }
            if let info = parseEMarker(service: service) { return info }
        }
        return nil
    }

    private static func parseEMarker(service: io_service_t) -> CableSpecInfo? {
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
                // 实机实测：IORegistry 中 VDO 以本机字节序（Apple Silicon 小端）存储，勿按大端读
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
        // VID 优先取 Metadata 中的 Vendor ID（实机验证更可靠），回退 ID Header VDO（vdo0）bit 16-31
        var vid: UInt16?
        if let n = metadata["Vendor ID"] as? NSNumber { vid = UInt16(truncatingIfNeeded: n.uint64Value) }
        if vid == nil { vid = UInt16((vdos[0] >> 16) & 0xFFFF) }
        // 线缆类型描述：Passive/Active/Optically Isolated/Legacy
        let productTypeRaw = metadata["Product Type Description"] as? String
        let productType: String?
        switch productTypeRaw?.lowercased() {
        case "passive cable", "passive": productType = "被动线缆"
        case "active cable", "active": productType = "有源线缆"
        case "optically isolated cable", "optically isolated": productType = "光隔离线缆"
        case "legacy cable", "legacy": productType = "旧式线缆"
        default: productType = productTypeRaw
        }

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

        // USB-IF 认证 XID：优先 Metadata 的 "Product XID"/"XID"（Apple 驱动解析值），
        // 缺失时回退 ID Header VDO 的 Product ID 字段（bit 0-15）。
        var xid: UInt16?
        if let n = metadata["Product XID"] as? NSNumber { xid = UInt16(truncatingIfNeeded: n.uint64Value) }
        if xid == nil, let n = metadata["XID"] as? NSNumber { xid = UInt16(truncatingIfNeeded: n.uint64Value) }
        if xid == nil { xid = UInt16(vdos[0] & 0xFFFF) }

        // 信任评估：零 VID / 速度电流延迟保留位 / VID 不在公布列表
        let trust = CableTrust.assess(cableVDO: cableVDO, vendorVID: vid, speedBits: speedBits, currentBits: currentBits)

        // 认证状态：仅当 XID 有效（非 0 / 非全 F）才判定；无 XID 数据不臆断
        let cert: (status: String, manufacturer: String?)?
        if let xid, xid != 0, xid != 0xFFFF {
            cert = USBIFXIDDB.certificationLabel(xid: xid, hasEMarker: true)
        } else {
            cert = nil
        }

        var lineDescription = "线缆 e-marker · \(speedLabel) · \(Int(current))A · \(maxWatts)W" + (epr ? " · EPR" : "")
        if let vid { lineDescription += " · " + CableVendorDB.displayName(for: vid) }
        if let cert, let m = cert.manufacturer {
            lineDescription += " · \(m) 认证"
        } else if let cert {
            lineDescription += " · " + (cert.status == "certified but unlisted" ? "certified but unlisted" : "USB-IF certified")
        }

        return CableSpecInfo(
            speedLabel: speedLabel,
            currentRating: current,
            maxWatts: maxWatts,
            isEPR: epr,
            vendorVID: vid,
            productType: productType,
            lineDescription: lineDescription,
            xid: xid,
            certification: cert?.status,
            certificationManufacturer: cert?.manufacturer,
            trustWarning: trust.summary,
            rawVDOCable: cableVDO
        )
    }

    // MARK: - PDO 列表（PortControllerInfo）

    /// 解析 AppleSmartBattery.PortControllerInfo 中每个控制器（带索引）的 PDO 档位与活跃合约。
    /// 实机（Apple Silicon）索引顺序：0/1 = TypeC 0/1 控制器，末位 = MagSafe 控制器；
    /// 该数组无 PortNumber 字段，故按索引归属物理口。
    private static func readAllControllerPDOs() -> [(index: Int, profiles: [PDOProfile], activeRDO: UInt32?)] {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &iter) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iter) }
        guard case let service = IOIteratorNext(iter), service != 0 else { return [] }
        defer { IOObjectRelease(service) }

        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return [] }

        guard let items = dict["PortControllerInfo"] as? [Any] else { return [] }

        var result: [(index: Int, profiles: [PDOProfile], activeRDO: UInt32?)] = []
        for (itemIndex, item) in items.enumerated() {
            guard let d = item as? [String: Any] else { continue }
            let rawPDOs = (d["PortControllerPortPDO"] as? [Any]) ?? []
            let pdoValues: [UInt32] = rawPDOs.compactMap { v in
                if let n = v as? NSNumber { return UInt32(truncatingIfNeeded: n.uint64Value) }
                return nil
            }
            guard !pdoValues.isEmpty else { continue }

            let activeRDO = (d["PortControllerActiveContractRdo"] as? NSNumber).map { UInt32(truncatingIfNeeded: $0.uint64Value) }
            var activePos = 0
            if let rdo = activeRDO, rdo != 0 {
                // RDO Object Position 位于 bit28-31（1-based）；部分固件按 bit24-27 上报，双保险
                let pos28 = Int((rdo >> 28) & 0xF)
                let pos24 = Int((rdo >> 24) & 0x1F)
                activePos = (pos28 >= 1 && pos28 <= 7) ? pos28 : pos24
            }

            var profiles: [PDOProfile] = []
            for (idx, pdo) in pdoValues.enumerated() {
                guard (pdo >> 30) & 0x3 == 0 else { continue } // 仅 Fixed PDO
                let volts = Double((pdo >> 10) & 0x3FF) * 0.05
                let amps = Double(pdo & 0x3FF) * 0.01
                guard volts > 0, amps > 0 else { continue }
                profiles.append(PDOProfile(
                    volts: volts, amps: amps,
                    watts: volts * amps,
                    isActive: (idx + 1) == activePos
                ))
            }
            if !profiles.isEmpty {
                result.append((itemIndex, profiles, activeRDO))
            }
        }
        return result
    }

    /// 按物理口取 PDO 档位：
    /// - TypeC 端口：typeCIndex 传 TypeC 编号（实机 = PortControllerInfo 索引 0/1，与 TypeC PhyID 一致）；
    /// - MagSafe 端口：typeCIndex 传 nil，取末位控制器（MagSafe 为 PortControllerInfo 末条）。
    /// 每口显示自身控制器的 PortControllerPortPDO，并高亮各自活动档位；不再全局只取有活跃合约的控制器。
    private static func readPDOList(typeCIndex: Int?) -> [PDOProfile]? {
        let all = readAllControllerPDOs()
        guard !all.isEmpty else { return nil }
        if let idx = typeCIndex {
            return all.first(where: { $0.index == idx })?.profiles
        }
        // MagSafe：末位控制器
        return all.last?.profiles
    }
}
