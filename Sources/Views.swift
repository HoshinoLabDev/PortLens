import SwiftUI
import Combine
import UserNotifications
import CoreText

// MARK: - 全局主题

enum Theme {
    static func tint(_ t: PortTint) -> Color {
        switch t {
        case .green: return Color(red: 0.30, green: 0.78, blue: 0.47)
        case .blue: return Color(red: 0.20, green: 0.55, blue: 0.98)
        case .purple: return Color(red: 0.62, green: 0.44, blue: 0.98)
        case .orange: return Color(red: 0.95, green: 0.61, blue: 0.20)
        case .red: return Color(red: 0.95, green: 0.35, blue: 0.33)
        case .gray: return Color.secondary
        }
    }
}

// MARK: - Design System（第二批 UI 升级：深色玻璃拟态）

extension Theme {
    // 品牌色与渐变
    static let accent = Color(red: 0.32, green: 0.83, blue: 0.66)
    static let accentBlue = Color(red: 0.25, green: 0.62, blue: 0.98)
    static let brandGradient = LinearGradient(
        colors: [Color(red: 0.42, green: 0.88, blue: 0.72), Color(red: 0.24, green: 0.62, blue: 0.98)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )
    static let brandGradientSoft = LinearGradient(
        colors: [Color(red: 0.42, green: 0.88, blue: 0.72).opacity(0.22), Color(red: 0.24, green: 0.62, blue: 0.98).opacity(0.18)],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    // 玻璃拟态材质（深浅色自适应）
    static let glassCardFill = Color(nsColor: .controlBackgroundColor).opacity(0.58)
    static let glassCardFillHover = Color(nsColor: .controlBackgroundColor).opacity(0.80)
    static let glassBorder = Color.white.opacity(0.10)
    static let glassBorderStrong = Color.white.opacity(0.16)
    static let glassTopHighlight = LinearGradient(
        colors: [.white.opacity(0.10), .white.opacity(0.0)],
        startPoint: .top, endPoint: .bottom
    )
    static let glassShadow = Color.black.opacity(0.16)

    // 间距
    static let spacingXS: CGFloat = 4
    static let spacingS: CGFloat = 6
    static let spacingM: CGFloat = 10
    static let spacingL: CGFloat = 14
    static let spacingXL: CGFloat = 18

    // 圆角
    static let radiusCard: CGFloat = 14
    static let radiusInner: CGFloat = 9
    static let radiusChip: CGFloat = 6

    // 字阶
    static let fontHeadline = Font.system(size: 14, weight: .semibold)
    static let fontTitle = Font.system(size: 12.5, weight: .semibold)
    static let fontBody = Font.system(size: 11)
    static let fontCaption = Font.system(size: 9.5)
    static let fontCaptionMono = Font.system(size: 9.5, design: .monospaced)
    static let fontValue = Font.system(size: 22, weight: .bold, design: .rounded)
}

// MARK: - 毛玻璃背景（NSVisualEffectView 封装）

struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .popover
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var state: NSVisualEffectView.State = .active

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = state
        view.isEmphasized = true
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}

// MARK: - 玻璃卡片容器

struct GlassCard<Content: View>: View {
    var cornerRadius: CGFloat = Theme.radiusCard
    var fill: Color = Theme.glassCardFill
    var borderColor: Color = Theme.glassBorder
    var shadowRadius: CGFloat = 6

    @ViewBuilder var content: () -> Content

    var body: some View {
        content()
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(fill)
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(Theme.glassTopHighlight)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: 1)
            )
            .shadow(color: Theme.glassShadow, radius: shadowRadius, y: 1)
    }
}

// MARK: - 规格标签胶囊

struct SpecChip: View {
    let text: String
    var foreground: Color = Theme.accent
    var background: Color = Theme.accent.opacity(0.14)

    var body: some View {
        Text(text)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Capsule().fill(background))
    }
}

// MARK: - 三态横幅（充电诊断：成功 / 警告 / 限制）

struct MetricBanner: View {
    enum BannerState {
        case success, warning, limited
        var color: Color {
            switch self {
            case .success: return .green
            case .warning: return .orange
            case .limited: return .red
            }
        }
        var tintOpacity: Double {
            switch self {
            case .success: return 0.14
            case .warning: return 0.15
            case .limited: return 0.16
            }
        }
        var strokeOpacity: Double {
            switch self {
            case .success: return 0.40
            case .warning: return 0.42
            case .limited: return 0.45
            }
        }
    }

    let state: BannerState
    let icon: String
    let title: String
    var subtitle: String? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(state.color)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                .fill(state.color.opacity(state.tintOpacity))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                .strokeBorder(state.color.opacity(state.strokeOpacity), lineWidth: 1)
        )
    }
}

// MARK: - 图标按钮（hover 微交互）

struct IconButton: View {
    let systemName: String
    var size: CGFloat = 11
    var tint: Color = .secondary
    var help: String = ""
    var action: () -> Void

    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: size, weight: .medium))
                .foregroundStyle(hovering ? tint : tint.opacity(0.75))
                .frame(width: 26, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(hovering ? Color.white.opacity(0.12) : Color.clear)
                )
                .animation(.easeOut(duration: 0.15), value: hovering)
        }
        .buttonStyle(.plain)
        .help(help)
        .onHover { hovering = $0 }
    }
}

// MARK: - 玻璃化 GroupBox（设置分组容器）

extension View {
    func glassGroup() -> some View {
        self
            .background(
                ZStack {
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.glassCardFill)
                    RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                        .fill(Theme.glassTopHighlight)
                }
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .strokeBorder(Theme.glassBorder, lineWidth: 1)
            )
            .shadow(color: Theme.glassShadow, radius: 6, y: 1)
    }
}

// MARK: - 版本信息

/// 版本号集中定义：从 Info.plist 的 CFBundleShortVersionString 读取
/// （build.sh 顶部 APP_VERSION 为唯一来源，递增时只需修改 build.sh 一处）
enum AppInfo {
    static let version: String = {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }()
}

// MARK: - 主视图

struct ContentView: View {
    @ObservedObject var monitor: USBMonitor
    @ObservedObject var settings: SettingsStore
    @ObservedObject var cableStore: CableHistoryStore
    var healthCache: [PortHealthStats] = []
    var liquidState: LiquidDetectionState = .idle
    var resistance: CableResistanceEstimate?
    var resistanceReason: String?

    private var visiblePorts: [PortCardModel] {
        settings.hideEmptyPorts ? monitor.ports.filter { $0.isConnected } : monitor.ports
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().opacity(0.5)
            if visiblePorts.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: Theme.spacingM) {
                        ForEach(Array(visiblePorts.enumerated()), id: \.element.id) { index, card in
                            VStack(spacing: Theme.spacingS) {
                                PortCardView(
                                    card: card,
                                    savedCableName: ProIntegration.savedCableName(for: card, monitor: monitor, store: cableStore),
                                    liquidState: liquidState,
                                    health: ProIntegration.healthForCard(card, cache: healthCache, cardCount: visiblePorts.count),
                                    resistance: resistance,
                                    resistanceReason: resistanceReason,
                                    showTechDetails: settings.showTechDetails,
                                    energyFlowEnabled: settings.energyFlowEnabled,
                                    scanEffectEnabled: settings.scanEffectEnabled,
                                    powerWatts: monitor.power.wattsNow,
                                    plugEvent: monitor.lastPlugEvent
                                )
                                PortCardProRow(
                                    card: card,
                                    savedCableName: ProIntegration.savedCableName(for: card, monitor: monitor, store: cableStore),
                                    contract: monitor.readPDContract(
                                        portIndex: card.isMagSafe ? nil : (card.portNumber ?? card.portIndex),
                                        isMagSafe: card.isMagSafe
                                    ),
                                    monitor: monitor,
                                    cableStore: cableStore
                                )
                            }
                        }
                    }
                    .padding(Theme.spacingL)
                }
            }
            Divider().opacity(0.5)
            footer
        }
        .frame(width: 380)
        .background(VisualEffectBackground(material: .popover, blendingMode: .behindWindow))
        .scaleEffect(settings.fontSizeScale, anchor: .topLeading)
    }

    private var header: some View {
        HStack(spacing: 10) {
            // 品牌化 Logo：渐变玻璃块 + 状态摘要
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 30, height: 30)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                Image(systemName: "cable.connector")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text("PortLens")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .lineLimit(1)
                }
                Text(subtitleLine)
                    .font(.system(size: 9.5))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if settings.showBatterySummary {
                BatteryBadge(power: monitor.power)
            }
            proMenu
            HStack(spacing: 5) {
                Button {
                    // 手动刷新：立即重读 IORegistry 并更新 @Published 状态（端口/设备/电源/充电判定），
                    // UI 由 @ObservedObject 自动重绘；lastRefreshAt 更新用于反馈刷新生效。
                    monitor.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("刷新")
                if let t = monitor.lastRefreshAt {
                    Text(t, style: .time)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .help("最近刷新时间")
                }
            }
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
    }

    private var subtitleLine: String {
        let connected = visiblePorts.filter(\.isConnected).count
        if connected > 0 { return "\(connected) 个端口已连接" }
        return "所有端口空闲"
    }

    private var proMenu: some View {
        Menu {
            Button {
                ProIntegration.openPowerMonitor(monitor: monitor)
            } label: {
                Label("Power Monitor", systemImage: "waveform.path.ecg")
            }
            Button {
                ProIntegration.openNegotiationDiagnostics(monitor: monitor, store: cableStore)
            } label: {
                Label("协商诊断 (Negotiation Diagnostics)", systemImage: "arrow.left.arrow.right.circle")
            }
            Button {
                ProIntegration.openSavedCables(store: cableStore, monitor: monitor)
            } label: {
                Label("已保存线缆 (Saved Cables)", systemImage: "cable.connector")
            }
            Button {
                ProIntegration.openPinDiagrams()
            } label: {
                Label("引脚图 (Pin Diagrams)", systemImage: "point.3.connected.trianglepath.dotted")
            }
            Button {
                ProIntegration.openDisplayDiagnostics()
            } label: {
                Label("显示诊断 (Display Diagnostics)", systemImage: "display")
            }
        } label: {
            Image(systemName: "chart.xyaxis.line")
                .font(.system(size: 11, weight: .medium))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Pro 功能")
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.brandGradientSoft)
                    .frame(width: 64, height: 64)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.glassTopHighlight)
                    .frame(width: 64, height: 64)
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Theme.accent.opacity(0.30), lineWidth: 1)
                    .frame(width: 64, height: 64)
                Image(systemName: "cable.connector.slash")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Theme.brandGradient)
            }
            Text("当前端口均为空")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("插入线缆或设备后，这里将实时显示诊断信息")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var footer: some View {
        HStack(spacing: Theme.spacingL) {
            HStack(spacing: 6) {
                Toggle("隐藏空端口", isOn: $settings.hideEmptyPorts)
                    .toggleStyle(.checkbox)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("退出") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.gray.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Color.gray.opacity(0.22), lineWidth: 1)
            )
            Text("v\(AppInfo.version)")
                .font(.system(size: 8.5, weight: .regular, design: .rounded))
                .foregroundStyle(Color.gray.opacity(0.45))
                .padding(.leading, 2)
        }
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, 9)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(Theme.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, Theme.spacingL)
        .padding(.vertical, Theme.spacingM)
    }
}

// MARK: - 电池分级颜色（菜单栏与窗体共用：<20% 红、<30% 黄、≥30% 绿）

enum BatteryLevelColor {
    static func nsColor(for percent: Int) -> NSColor {
        if percent < 20 { return NSColor(calibratedRed: 0.95, green: 0.23, blue: 0.19, alpha: 1.0) }
        if percent < 30 { return NSColor(calibratedRed: 0.95, green: 0.78, blue: 0.20, alpha: 1.0) }
        return NSColor(calibratedRed: 0.25, green: 0.82, blue: 0.40, alpha: 1.0)
    }
    static func color(for percent: Int) -> Color {
        Color(nsColor: nsColor(for: percent))
    }
}

// MARK: - 电池徽章

struct BatteryBadge: View {
    let power: PowerState

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(iconTint)
                .fixedSize()
            Text("\(power.batteryPercent)%")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .lineLimit(1)
                .fixedSize()
            if power.isCharging {
                Text("\(Int(power.wattsNow.rounded()))W")
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .fixedSize()
            }
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(
            ZStack {
                Capsule().fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.08), .clear], startPoint: .top, endPoint: .bottom))
            }
        )
        .overlay(
            Capsule().strokeBorder(BatteryLevelColor.color(for: power.batteryPercent).opacity(0.45), lineWidth: 1)
        )
    }

    private var iconTint: Color {
        BatteryLevelColor.color(for: power.batteryPercent)
    }

    private var icon: String {
        if power.isCharging { return "battery.100.bolt" }
        if power.batteryPercent <= 20 { return "battery.25" }
        if power.batteryPercent <= 50 { return "battery.50" }
        if power.batteryPercent <= 80 { return "battery.75" }
        return "battery.100"
    }
}

// MARK: - 能量流粒子动画（端口卡片内流动光点，充电亮绿 / 数据浅绿）

struct EnergyFlowView: View {
    let isCharging: Bool
    let intensity: Double          // 0...1：密度与亮度（功率越高越密越亮）
    let burstStart: Date?          // 插拔瞬间：粒子从中心爆散

    /// 充电=亮绿（向右汇入电池）；数据=浅绿（向左流动）
    private var flowColor: Color {
        isCharging ? Color(red: 0.20, green: 0.85, blue: 0.45) : Color(red: 0.55, green: 0.92, blue: 0.65)
    }

    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            let burst = burstStart.map { context.date.timeIntervalSince($0) } ?? 999
            ZStack {
                Canvas { ctx, size in
                    let center = CGPoint(x: size.width / 2, y: size.height / 2)
                    if burst < 0.65 {
                        drawBurst(ctx: ctx, size: size, center: center, elapsed: burst)
                    }
                    drawFlow(ctx: ctx, size: size, t: t)
                }
                // 端部流向指示：充电=电池图标（粒子汇入）；数据=箭头（粒子流出）
                HStack {
                    if isCharging {
                        Spacer()
                        Image(systemName: "battery.100.bolt")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(flowColor.opacity(0.9))
                    } else {
                        Image(systemName: "arrow.right")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(flowColor.opacity(0.9))
                        Spacer()
                    }
                }
                .padding(.horizontal, 8)
            }
        }
        .frame(height: 33)
        .allowsHitTesting(false)
    }

    /// 常规流动粒子：3 条轨道正弦波动，方向由充电/数据决定
    private func drawFlow(ctx: GraphicsContext, size: CGSize, t: Double) {
        let baseCount = 3 + Int(intensity * 13)
        let mid = size.height * 0.5
        for i in 0..<baseCount {
            let seed = Double(i) * 12.9898
            let period = 3.2 + Double(i % 4) * 0.9
            let phase = ((t / period) + (seed.truncatingRemainder(dividingBy: 0.37))).truncatingRemainder(dividingBy: 1.0)
            let x: CGFloat = isCharging ? size.width * CGFloat(phase) : size.width * CGFloat(1 - phase)
            let lane = CGFloat(i % 3)
            let laneY = mid + (lane - 1) * size.height * 0.16
            let y = laneY + CGFloat(sin(t * 2.6 + seed)) * 2.5
            let radius = 1.1 + CGFloat(intensity) * 1.7
            let alpha = 0.5 + CGFloat(intensity) * 0.5
            // 外层光晕 + 亮核心（两层圆，性能优先）
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius * 2.2, y: y - radius * 2.2, width: radius * 4.4, height: radius * 4.4)),
                     with: .color(flowColor.opacity(alpha * 0.22)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(flowColor.opacity(alpha)))
        }
    }

    /// 插拔爆散：粒子自中心向四周飞散并衰减
    private func drawBurst(ctx: GraphicsContext, size: CGSize, center: CGPoint, elapsed: Double) {
        let progress = elapsed / 0.65
        let count = 26
        for i in 0..<count {
            let angle = Double(i) / Double(count) * 2 * .pi + Double(i) * 0.17
            let dist = CGFloat(progress) * max(size.width, size.height) * 0.65
            let x = center.x + CGFloat(cos(angle)) * dist
            let y = center.y + CGFloat(sin(angle)) * dist
            let alpha = max(0, 1 - progress)
            let radius: CGFloat = 2.0
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius * 3.0, y: y - radius * 3.0, width: radius * 6.0, height: radius * 6.0)),
                     with: .color(flowColor.opacity(alpha * 0.28)))
            ctx.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)),
                     with: .color(flowColor.opacity(alpha)))
        }
    }
}

// MARK: - 扫描透视动画（插拔时扫描光自上而下，扫过浮现信息带 + 发光描边）

struct ScanRevealView: View {
    let start: Date
    let tint: Color
    let onFinished: () -> Void
    @State private var didFinish = false
    private let duration: Double = 0.85

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = context.date.timeIntervalSince(start)
            let progress = min(1.0, elapsed / duration)
            Canvas { ctx, size in
                // 扫描完成回调（Canvas 渲染闭包内允许副作用，didFinish 防重入）
                if elapsed >= duration && !didFinish {
                    DispatchQueue.main.async {
                        didFinish = true
                        onFinished()
                    }
                }
                let y = progress * size.height
                // 已扫过区域：信息带渐现（轻反馈）
                var revealed = Path()
                revealed.addRect(CGRect(x: 0, y: 0, width: size.width, height: y))
                ctx.fill(revealed, with: .color(tint.opacity(0.04 + 0.10 * progress)))
                // 扫描光线：发光横带（自上而下）
                let lineH: CGFloat = 26
                let lineRect = CGRect(x: 0, y: max(0, y - lineH / 2), width: size.width, height: lineH)
                let gradient = Gradient(stops: [
                    .init(color: tint.opacity(0.0), location: 0),
                    .init(color: tint.opacity(0.30), location: 0.18),
                    .init(color: .white.opacity(0.55), location: 0.5),
                    .init(color: tint.opacity(0.30), location: 0.82),
                    .init(color: tint.opacity(0.0), location: 1)
                ])
                ctx.fill(Path(roundedRect: lineRect, cornerRadius: lineH / 2),
                         with: .linearGradient(gradient, startPoint: CGPoint(x: 0, y: 0), endPoint: CGPoint(x: size.width, y: 0)))
                // 发光描边（扫描期间卡片外缘呼吸发光）
                let strokeRect = CGRect(x: 1.5, y: 1.5, width: size.width - 3, height: size.height - 3)
                ctx.stroke(Path(roundedRect: strokeRect, cornerRadius: Theme.radiusCard),
                           with: .color(tint.opacity(0.55 * (1 - progress * 0.6))), lineWidth: 2)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - 端口卡片

struct PortCardView: View {
    let card: PortCardModel
    var savedCableName: String? = nil
    var liquidState: LiquidDetectionState = .idle
    var health: PortHealthStats? = nil
    var resistance: CableResistanceEstimate? = nil
    var resistanceReason: String? = nil
    var showTechDetails: Bool = false
    var energyFlowEnabled: Bool = true
    var scanEffectEnabled: Bool = true
    var powerWatts: Double = 0
    var plugEvent: USBMonitor.PlugEvent? = nil

    @State private var hovering = false
    @State private var scanStart: Date? = nil
    @State private var burstStart: Date? = nil

    /// 与 USBMonitor 插拔事件 key 一致的端口标识（"C1" / "MS"）
    private var portKey: String {
        card.isMagSafe ? "MS\(card.portNumber ?? card.portIndex)" : "C\(card.portNumber ?? card.portIndex)"
    }

    /// 能量流密度/亮度：充电时随实时功率 0...1；数据流时中等；仅连接端口可见
    private var flowIntensity: Double {
        if card.chargingBanner?.contains("充电") == true {
            return min(1.0, max(0.15, powerWatts / 100.0))
        }
        if !card.connectedDevices.isEmpty || card.dataLine != nil {
            return 0.55
        }
        return 0.2
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
            if card.isConnected {
                contentRows
                if energyFlowEnabled {
                    EnergyFlowView(
                        isCharging: card.chargingBanner?.contains("充电") == true,
                        intensity: flowIntensity,
                        burstStart: burstStart
                    )
                    .padding(.top, 6)
                }
            }
        }
        .padding(Theme.spacingL)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(hovering ? Theme.glassCardFillHover : Theme.glassCardFill)
                RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                    .fill(Theme.glassTopHighlight)
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusCard, style: .continuous)
                .strokeBorder(
                    card.isConnected
                        ? LinearGradient(colors: [Theme.tint(card.tint).opacity(0.55), Theme.tint(card.tint).opacity(0.12)], startPoint: .top, endPoint: .bottom)
                        : LinearGradient(colors: [.clear, .clear], startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        )
        .shadow(color: Theme.glassShadow, radius: 6, y: 1)
        .overlay {
            if scanEffectEnabled, let s = scanStart {
                ScanRevealView(start: s, tint: Theme.tint(card.tint)) {
                    scanStart = nil
                }
            }
        }
        .onChange(of: plugEvent) { newEvent in
            guard let ev = newEvent, ev.portKey == portKey else { return }
            // 插拔瞬间：扫描光线扫过（受扫描开关）+ 粒子爆开（受粒子开关），两开关独立
            if scanEffectEnabled { scanStart = Date() }
            if energyFlowEnabled { burstStart = Date() }
        }
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.18), value: hovering)
    }

    private var headerRow: some View {
        HStack(spacing: 9) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(LinearGradient(colors: [Theme.tint(card.tint).opacity(0.24), Theme.tint(card.tint).opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .frame(width: 34, height: 34)
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Theme.tint(card.tint).opacity(0.32), lineWidth: 1)
                    .frame(width: 34, height: 34)
                Image(systemName: card.headlineIcon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.tint(card.tint))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(card.headline)
                        .font(Theme.fontHeadline)
                        .lineLimit(1)
                    statusChip
                }
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Text(portLabel)
                .font(.system(size: 9.5, weight: .medium, design: .monospaced))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 2.5)
                .background(Capsule().fill(Theme.tint(card.tint).opacity(0.10)))
                .overlay(Capsule().strokeBorder(Theme.tint(card.tint).opacity(0.22), lineWidth: 1))
        }
    }

    private var statusChip: some View {
        Group {
            if card.isConnected {
                Text("已连接")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(Theme.tint(card.tint))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Capsule().fill(Theme.tint(card.tint).opacity(0.13)))
                    .overlay(Capsule().strokeBorder(Theme.tint(card.tint).opacity(0.28), lineWidth: 1))
            }
        }
    }

    private var portLabel: String {
        guard let n = card.portNumber else { return "TB" }
        if card.isMagSafe { return "MagSafe" }
        return "TypeC \(n)"
    }

    private var subtitle: String {
        if let banner = card.chargingBanner {
            return banner
        }
        if card.isConnected {
            let n = card.connectedDevices.isEmpty ? card.devices.count : card.connectedDevices.count
            return "已连接 \(n) 个设备"
        }
        return "插入设备后此处将实时显示诊断信息"
    }

    @ViewBuilder
    private var contentRows: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let banner = card.chargingBanner {
                chargingBannerView(banner, subtitle: card.chargingSub)
            }
            if let dataLine = card.dataLine {
                row(icon: "gauge.with.dots.needle.50percent", text: dataLine, color: Theme.tint(card.tint))
            }
            if let cableLine = card.cableLine {
                row(icon: "cable.coaxial", text: cableLine, color: .purple)
            }
            if let cableSpec = card.cableSpec {
                cableSpecChips(cableSpec)
            }
            // 线缆信任信号：异常值 → 橙色警告卡（中性措辞）
            if let trust = card.trustWarning {
                trustWarningCard(trust)
            }
            // USB-IF 认证：XID 制造商 / certified but unlisted
            if let cert = card.certification {
                certificationRow(cert, manufacturer: card.certificationManufacturer)
            }
            if let deviceLine = card.deviceLine {
                row(icon: "externaldrive.fill.badge.checkmark", text: deviceLine, color: .blue)
            }
            // 已连接设备区块（充电器 / 显示器 / iPhone 等）
            if !card.connectedDevices.isEmpty {
                connectedDevicesSection(card.connectedDevices)
            }
            // Active transports：明示 USB 2 / USB 3 / Thunderbolt / DisplayPort
            if !card.activeTransports.isEmpty {
                transportsRow(card.activeTransports)
            }
            // Thunderbolt fabric：每 lane 速度 / 代数 / 拓扑 / 活跃 tunnel
            if let fabric = card.fabric {
                fabricSection(fabric)
            }
            if let pdos = card.pdoList, !pdos.isEmpty {
                pdoSection(pdos)
            }
            if let fault = card.faultText {
                row(icon: "exclamationmark.triangle.fill", text: fault, color: .orange)
            }
            if let name = savedCableName {
                row(icon: "bookmark.fill", text: "已识别线缆：\(name)", color: .purple)
            }
            if liquidState != .idle, liquidState != .notSupported {
                row(icon: liquidIcon, text: liquidText, color: liquidColor)
            }
            if let health {
                row(icon: "heart.text.square.fill", text: health.summaryText, color: health.hasIssues ? .orange : .green)
            }
            if let resistance {
                row(icon: "point.bottomleft.forward.to.point.topright.scurvepath", text: "线缆电阻 ≈ \(resistance.formatted)（\(resistance.note)）", color: resistance.lowConfidence ? .orange : .blue)
            } else if let resistanceReason {
                row(icon: "point.bottomleft.forward.to.point.topright.scurvepath", text: resistanceReason, color: .secondary)
            }
            if showTechDetails, let td = card.techDetailLine {
                row(icon: "number.circle", text: td, color: .secondary)
            }
        }
        .padding(.top, 10)
    }

    /// 已连接设备区块（玻璃拟态小卡片，图标 + 品牌型号 + 类型标签 + 挂载层级）
    private func connectedDevicesSection(_ devices: [ConnectedDevice]) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("已连接设备")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 2)
            ForEach(devices) { device in
                deviceRow(device)
            }
        }
        .padding(9)
        .background(
            RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                .fill(Color.white.opacity(0.045))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusChip, style: .continuous)
                .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
        )
    }

    private func deviceRow(_ device: ConnectedDevice) -> some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Theme.tint(card.tint).opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: device.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tint(card.tint))
            }
            VStack(alignment: .leading, spacing: 1.5) {
                HStack(spacing: 5) {
                    Text(device.summary)
                        .font(.system(size: 11.5, weight: .medium))
                        .lineLimit(1)
                    Text(device.kind.rawValue)
                        .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(Theme.tint(card.tint).opacity(0.9))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(Capsule().fill(Theme.tint(card.tint).opacity(0.12)))
                }
                if let detail = device.detail {
                    Text(detail)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 2)
            if let via = device.viaText {
                Text(via)
                    .font(.system(size: 9))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 2)
    }

    private var liquidIcon: String {
        switch liquidState.mode {
        case .detected: return "drop.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .normal: return "drop"
        }
    }

    private var liquidText: String {
        switch liquidState.mode {
        case .detected: return "液体检测：检测到液体 / 腐蚀迹象（LDCM）"
        case .warning: return "液体检测：异常读数（LDCM）"
        case .normal: return "液体检测：正常（LDCM）"
        }
    }

    private var liquidColor: Color {
        switch liquidState.mode {
        case .detected: return .red
        case .warning: return .orange
        case .normal: return .green
        }
    }

    private var chargingIcon: String {
        card.chargingBanner?.contains("充电") == true ? "bolt.fill" : "powerplug.fill"
    }

    /// 充电诊断横幅：三态（成功 / 警告 / 限制）玻璃横幅
    private func chargingBannerView(_ text: String, subtitle: String?) -> some View {
        let state: MetricBanner.BannerState
        if text.contains("限制") || text.contains("受限") || text.contains("低于") || text.contains("无法满速") {
            state = .limited
        } else if text.contains("异常") || text.contains("警告") || text.contains("未识别") {
            state = .warning
        } else {
            state = .success
        }
        return MetricBanner(state: state, icon: chargingIcon, title: text, subtitle: subtitle)
    }

    /// e-Marker 规格：标签化 chips 展示
    private func cableSpecChips(_ spec: String) -> some View {
        let parts = spec
            .split { $0 == "·" || $0 == "," || $0 == "，" || $0 == "|" }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        if parts.isEmpty {
            return AnyView(
                Text(spec)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 22)
            )
        }
        return AnyView(
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(.purple.opacity(0.85))
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    SpecChip(text: part, foreground: .purple, background: Color.purple.opacity(0.13))
                }
            }
            .padding(.leading, 22)
        )
    }

    private func row(icon: String, text: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(color)
                .frame(width: 16)
            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func pdoSection(_ pdos: [PDOProfile]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("充电器功率档位 (PDO)")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(pdos) { pdo in
                    VStack(spacing: 2) {
                        if pdo.isActive {
                            Text("当前使用")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.green))
                        } else {
                            Text("当前使用")
                                .font(.system(size: 8, weight: .bold, design: .rounded))
                                .foregroundStyle(.clear)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 1.5)
                                .background(Capsule().fill(Color.clear))
                        }
                        Text(String(format: "%.0fV", pdo.volts))
                            .font(.system(size: 10, weight: .semibold, design: .rounded))
                        Text(String(format: "%.1fA", pdo.amps))
                            .font(.system(size: 9, design: .rounded))
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.0fW", pdo.watts))
                            .font(.system(size: 9, weight: .bold, design: .rounded))
                            .foregroundStyle(pdo.isActive ? .green : .secondary)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(pdo.isActive ? Color.green.opacity(0.13) : Color(nsColor: .quaternaryLabelColor).opacity(0.22))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(pdo.isActive ? Color.green.opacity(0.4) : Color.clear, lineWidth: 1)
                    )
                }
            }
        }
    }

    // MARK: - 第二批功能渲染（认证 / 信任 / 传输 / fabric）

    /// 线缆信任信号橙色警告卡（中性措辞）
    private func trustWarningCard(_ text: String) -> some View {
        HStack(spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.orange.opacity(0.18))
                    .frame(width: 24, height: 24)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.orange)
            }
            Text(text)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(8)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .fill(LinearGradient(colors: [Color.orange.opacity(0.16), Color.orange.opacity(0.06)], startPoint: .topLeading, endPoint: .bottomTrailing))
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .fill(LinearGradient(colors: [.white.opacity(0.06), .clear], startPoint: .top, endPoint: .bottom))
            }
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.38), lineWidth: 1)
        )
    }

    /// USB-IF 认证：徽章 + 制造商 chip
    private func certificationRow(_ cert: String, manufacturer: String?) -> some View {
        let isUnlisted = cert.contains("unlisted")
        let color: Color = isUnlisted ? .secondary : .green
        return HStack(spacing: 6) {
            Image(systemName: isUnlisted ? "checkmark.seal" : "checkmark.seal.fill")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 16)
            Text("USB-IF 认证")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.primary)
            Spacer()
            if let m = manufacturer, !m.isEmpty {
                SpecChip(text: m, foreground: color, background: color.opacity(0.13))
            } else {
                SpecChip(text: certificationSuffix(cert), foreground: color, background: color.opacity(0.13))
            }
        }
    }

    private func certificationSuffix(_ cert: String) -> String {
        if cert.contains("unlisted") { return "certified but unlisted" }
        return cert
    }

    /// Active transports：USB 2 / USB 3 / Thunderbolt / DisplayPort 结构化小部件
    private func transportsRow(_ transports: [String]) -> some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "arrow.left.arrow.right.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.blue)
            Text("活跃传输")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(.secondary)
            Spacer()
            ForEach(transports, id: \.self) { t in
                SpecChip(text: t, foreground: .blue, background: Color.blue.opacity(0.12))
            }
        }
        .padding(.vertical, 2)
    }

    /// Thunderbolt fabric：结构化小部件（hop 路径 + lane 速度徽章 + tunnel chips）
    @ViewBuilder
    private func fabricSection(_ fabric: ThunderboltFabric) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "bolt.horizontal.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.purple)
                Text("Thunderbolt fabric")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                SpecChip(text: fabric.generationSummary, foreground: .purple, background: Color.purple.opacity(0.13))
            }
            VStack(alignment: .leading, spacing: 4) {
                ForEach(fabric.hops) { hop in
                    HStack(spacing: 6) {
                        Text(String(repeating: "  ", count: hop.depth))
                            .font(.system(size: 8))
                        Image(systemName: "rectangle.stack.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.purple)
                        Text(hop.name)
                            .font(.system(size: 9.5, weight: .medium))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer(minLength: 4)
                        SpecChip(text: "\(hop.generation)", foreground: .purple.opacity(0.9), background: Color.purple.opacity(0.10))
                        SpecChip(text: "\(hop.laneSpeedGbps) Gbps/lane", foreground: .purple.opacity(0.9), background: Color.purple.opacity(0.10))
                    }
                }
            }
            .padding(8)
            .background(
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .fill(Color.purple.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.radiusInner, style: .continuous)
                    .strokeBorder(Color.purple.opacity(0.16), lineWidth: 1)
            )
            if !fabric.tunnels.isEmpty {
                HStack(spacing: 5) {
                    Image(systemName: "point.3.connected.trianglepath.dotted")
                        .font(.system(size: 9))
                        .foregroundStyle(.purple.opacity(0.8))
                    Text("活跃 tunnel")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(.secondary)
                    Text(fabric.activeTunnelSummary)
                        .font(.system(size: 9))
                        .foregroundStyle(.primary)
                }
            }
        }
        .padding(.top, 2)
    }
}

// MARK: - App 入口

@main
struct PortLensApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var monitor: USBMonitor?
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var settings = SettingsStore()

    // Pro 状态（第一批核心功能）
    private var powerStore: PowerMonitorStore?
    private var cableStore: CableHistoryStore?
    private var powerTimer: Timer?
    private var healthCache: [PortHealthStats] = []
    private var liquidState: LiquidDetectionState = .idle
    private var resistance: CableResistanceEstimate?
    private var resistanceReason: String?
    @Published private(set) var keepWindowOpen = false
    private var popoverTransientBackup: NSPopover.Behavior = .transient
    private var settingsWindow: NSWindow?

    // 呼吸图标动画（第三批视觉功能）
    private var breathingTimer: Timer?
    private var rainbowFlashUntil: Date?
    private var lastHighSpeed = false

    // 充电状态图标与跃迁动画（第四批视觉功能）
    private enum ChargeConnectionState {
        case charging          // 正在充电（IsCharging=Yes 且 ExternalConnected=Yes）
        case connectedIdle     // 已接入电源但未充电（ExternalConnected=Yes 且 IsCharging=No）
        case disconnected      // 未接入电源（ExternalConnected=No）
    }
    private var punchStart: Date?
    private var lastChargeState: ChargeConnectionState?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Dock 应用模式：按设置初始化（accessory 默认 / regular 显示 Dock 图标）
        switch settings.dockMode {
        case .accessory:
            NSApp.setActivationPolicy(.accessory)
        case .regular:
            NSApp.setActivationPolicy(.regular)
        }

        let monitor = USBMonitor()
        USBMonitor.shared = monitor
        self.monitor = monitor

        // 连接/断开系统通知（可开关）
        monitor.onConnectionChange = { [weak self] title, body in
            self?.postConnectionNotification(title: title, body: body)
        }

        monitor.start()

        // Pro：建立线缆历史与功率采样存储，启动 2 秒实时采样
        let store = CableHistoryStore()
        let powerStore = PowerMonitorStore()
        powerStore.monitor = monitor
        powerStore.isRunning = true
        monitor.powerStore = powerStore
        self.cableStore = store
        self.powerStore = powerStore
        startPowerSampling()
        refreshProDerived(monitor: monitor, cableStore: store)

        let popover = NSPopover()
        popover.contentSize = NSSize(width: 380 * settings.fontSizeScale, height: 680 * settings.fontSizeScale)
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(rootView: ContentView(
            monitor: monitor,
            settings: settings,
            cableStore: store,
            healthCache: healthCache,
            liquidState: liquidState,
            resistance: resistance,
            resistanceReason: resistanceReason
        ))
        self.popover = popover

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let button = item.button {
            button.target = self
            button.action = #selector(togglePopover(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        statusItem = item
        renderStatusIcon()

        // 端口/电源/图标模式任一变化时刷新菜单栏图标
        monitor.$ports
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderStatusIcon()
                self?.updateWidgetDefaults()
            }
            .store(in: &cancellables)
        monitor.$power
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderStatusIcon()
            }
            .store(in: &cancellables)
        settings.$iconMode
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderStatusIcon()
            }
            .store(in: &cancellables)
        subscribeSettings()
    }

    private var cancellables: Set<AnyCancellable> = []

    @objc private func togglePopover(_ sender: Any?) {
        // 右键：弹出 Pro 菜单
        if NSApp.currentEvent?.type == .rightMouseUp {
            showContextMenu(sender)
            return
        }
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showContextMenu(_ sender: Any?) {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        menu.addItem(withTitle: "Power Monitor", action: #selector(openPowerMonitor), keyEquivalent: "")
        menu.addItem(withTitle: "Negotiation Diagnostics（协商诊断）", action: #selector(openNegotiationDiagnostics), keyEquivalent: "")
        menu.addItem(withTitle: "Saved Cables（已保存线缆）", action: #selector(openSavedCables), keyEquivalent: "")
        menu.addItem(withTitle: "Pin Diagrams（引脚图）", action: #selector(openPinDiagrams), keyEquivalent: "")
        menu.addItem(withTitle: "Display Diagnostics（显示诊断）", action: #selector(openDisplayDiagnostics), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        let keep = NSMenuItem(title: "Keep window open（保持窗口打开）", action: #selector(toggleKeepWindowOpen), keyEquivalent: "")
        keep.state = keepWindowOpen ? .on : .off
        menu.addItem(keep)
        menu.addItem(NSMenuItem.separator())

        // 菜单栏图标模式
        let iconModeItem = NSMenuItem(title: "菜单栏图标模式", action: nil, keyEquivalent: "")
        let iconModeMenu = NSMenu()
        for mode in SettingsStore.IconMode.allCases {
            let item = NSMenuItem(title: mode.displayName, action: #selector(setIconMode(_:)), keyEquivalent: "")
            item.representedObject = mode.rawValue
            item.state = settings.iconMode == mode ? .on : .off
            iconModeMenu.addItem(item)
        }
        iconModeItem.submenu = iconModeMenu
        menu.addItem(iconModeItem)

        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Refresh（刷新）", action: #selector(refreshNow), keyEquivalent: "r")
        menu.addItem(withTitle: "Settings（设置）", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "Licence（许可）", action: #selector(showLicence), keyEquivalent: "")
        menu.addItem(withTitle: "Check for Updates（检查更新）", action: #selector(checkForUpdates), keyEquivalent: "")
        menu.addItem(withTitle: "About（关于）", action: #selector(showAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit（退出）", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        for item in menu.items {
            item.target = self
        }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
    }

    // MARK: - Pro 窗口入口

    @objc private func openPowerMonitor() {
        guard let monitor else { return }
        ProIntegration.openPowerMonitor(monitor: monitor)
    }

    @objc private func openNegotiationDiagnostics() {
        guard let monitor, let cableStore else { return }
        ProIntegration.openNegotiationDiagnostics(monitor: monitor, store: cableStore)
    }

    @objc private func openSavedCables() {
        guard let monitor, let cableStore else { return }
        ProIntegration.openSavedCables(store: cableStore, monitor: monitor)
    }

    @objc private func openPinDiagrams() {
        ProIntegration.openPinDiagrams()
    }

    @objc private func openDisplayDiagnostics() {
        ProIntegration.openDisplayDiagnostics()
    }

    @objc private func toggleKeepWindowOpen() {
        guard let popover else { return }
        keepWindowOpen.toggle()
        if keepWindowOpen {
            popoverTransientBackup = popover.behavior
            popover.behavior = .applicationDefined
        } else {
            popover.behavior = popoverTransientBackup
        }
    }

    @objc private func refreshNow() {
        monitor?.refresh()
    }

    /// 切换菜单栏图标显示模式（右键菜单）
    @objc private func setIconMode(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let mode = SettingsStore.IconMode(rawValue: raw) else { return }
        settings.iconMode = mode
    }

    /// 按当前模式渲染菜单栏图标；模式/端口/电源任一变化时调用，立即生效
    private func renderStatusIcon() {
        guard let button = statusItem?.button else { return }
        switch settings.iconMode {
        case .simple:
            let connected = monitor?.ports.contains { $0.isConnected } ?? false
            button.image = Self.statusImage(connected: connected)
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        case .dynamic, .wideBar:
            guard let monitor else { return }
            // 高速设备接入检测：新出现高速设备 → 菜单栏图标彩虹闪一次
            let hs = hasHighSpeedDevice(monitor)
            if hs && !lastHighSpeed { rainbowFlashUntil = Date().addingTimeInterval(1.4) }
            lastHighSpeed = hs
            if settings.breathingIconEnabled {
                // 呼吸图标：启动/维持 30fps 光晕动画并立即画一帧
                detectChargeTransition(monitor: monitor)
                syncBreathingIcon(monitor: monitor)
            } else {
                stopBreathingTimer()
                switch settings.iconMode {
                case .dynamic:
                    button.image = Self.dynamicStatusImage(power: monitor.power)
                case .wideBar:
                    button.image = Self.wideBarStatusImage(power: monitor.power)
                case .simple:
                    break
                }
                applyDynamicTitle(monitor: monitor)
            }
            button.imagePosition = .imageLeading
        }
    }

    // MARK: - 呼吸图标动画（充电金晕呼吸+实时功率 / 空闲蓝光脉动 / 高速设备彩虹闪一次）

    /// 启动/维持呼吸定时器并立即绘制一帧；开关关闭时不创建定时器（无残留）
    private func syncBreathingIcon(monitor: USBMonitor) {
        guard statusItem?.button != nil else { return }
        if breathingTimer == nil {
            let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
                self?.tickBreathingIcon()
            }
            breathingTimer = timer
            RunLoop.main.add(timer, forMode: .common)
        }
        tickBreathingIcon()
    }

    /// 关闭呼吸动画：销毁定时器（无残留）
    private func stopBreathingTimer() {
        breathingTimer?.invalidate()
        breathingTimer = nil
    }

    private func tickBreathingIcon() {
        guard let monitor, let button = statusItem?.button else { return }
        let phase = Date().timeIntervalSinceReferenceDate
        let rainbow = rainbowFlashUntil.map { Date() < $0 } ?? false
        switch settings.iconMode {
        case .wideBar:
            // 宽体色块模式：宽电池 + 内部色块比例 + 状态符号；沿用外圈分级光晕呼吸与跃迁放大
            button.image = Self.wideBarStatusImage(
                power: monitor.power,
                phase: phase,
                rainbow: rainbow,
                scale: punchScale()
            )
        default:
            button.image = Self.breathingDynamicStatusImage(
                power: monitor.power,
                phase: phase,
                rainbow: rainbow,
                charging: monitor.power.isCharging,
                scale: punchScale()
            )
        }
        applyDynamicTitle(monitor: monitor)
        button.imagePosition = .imageLeading
    }

    // MARK: - 充电状态跃迁：放大复位动画 + 中间符号分支

    /// 三态判定：正在充电 / 已接入未充电 / 未接入
    private func chargeState(of power: PowerState) -> ChargeConnectionState {
        if power.isCharging && power.externalConnected { return .charging }
        if power.externalConnected { return .connectedIdle }
        return .disconnected
    }

    /// 检测充电状态跃迁：开始充电 / 停止充电 / 接入 / 拔掉 → 触发一次放大动画
    /// 首次渲染只记录当前状态（启动时不视为跃迁）；状态真正变化时才设置 punchStart
    private func detectChargeTransition(monitor: USBMonitor) {
        let current = chargeState(of: monitor.power)
        guard let last = lastChargeState else {
            lastChargeState = current
            return
        }
        if current != last {
            punchStart = Date()
            lastChargeState = current
        }
    }

    /// 跃迁放大比例：1.0 → 1.28 起步，指数衰减 + 余弦回弹复位（约 0.65 秒）
    private func punchScale() -> CGFloat {
        guard let start = punchStart else { return 1.0 }
        let elapsed = Date().timeIntervalSince(start)
        let duration: TimeInterval = 0.65
        guard elapsed < duration else {
            punchStart = nil
            return 1.0
        }
        return 1.0 + 0.28 * exp(-5.0 * elapsed) * cos(10.0 * elapsed)
    }

    /// 动态模式标题统一应用（百分比 + 可选功率 / 填充条）
    /// 宽体色块模式内部已绘制百分比数字，禁用右侧重复文字
    private func applyDynamicTitle(monitor: USBMonitor) {
        guard let button = statusItem?.button else { return }
        if settings.iconMode == .wideBar {
            button.attributedTitle = NSAttributedString(string: "")
            return
        }
        switch settings.iconChargeDisplay {
        case .off:
            button.attributedTitle = Self.dynamicStatusTitle(power: monitor.power, includeWatts: false)
        case .number:
            button.attributedTitle = Self.dynamicStatusTitle(power: monitor.power, includeWatts: true)
        case .bar:
            button.attributedTitle = Self.dynamicStatusBarTitle(power: monitor.power)
        }
    }

    /// 高速设备判定（Thunderbolt / USB4 / 40Gbps 线缆）
    private func hasHighSpeedDevice(_ monitor: USBMonitor) -> Bool {
        monitor.ports.contains { card in
            card.activeTransports.contains { $0.localizedCaseInsensitiveContains("thunderbolt") }
                || (card.cableSpec?.localizedCaseInsensitiveContains("usb4") ?? false)
                || (card.cableSpec?.localizedCaseInsensitiveContains("40gbps") ?? false)
        }
    }

    // MARK: - 设置订阅：透明度 / 字号实时生效

    private func subscribeSettings() {
        settings.$windowOpacity
            .receive(on: DispatchQueue.main)
            .sink { [weak self] value in
                guard let self, let popover = self.popover else { return }
                popover.contentViewController?.view.window?.alphaValue = value
            }
            .store(in: &cancellables)
        settings.$fontSizeScale
            .receive(on: DispatchQueue.main)
            .sink { [weak self] scale in
                guard let self, let popover = self.popover else { return }
                popover.contentSize = NSSize(width: 380 * scale, height: 680 * scale)
            }
            .store(in: &cancellables)
        // 呼吸图标开关：开→启动动画，关→销毁定时器并回落到静态动态图标
        settings.$breathingIconEnabled
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.renderStatusIcon()
            }
            .store(in: &cancellables)
    }

    // MARK: - Pro 实时采样（每 2 秒）

    private func startPowerSampling() {
        guard let monitor, let powerStore else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, let monitor = self.monitor else { return }
                // 兜底全量刷新端口/设备/电源状态：IOKit/IOPS 事件通知偶有遗漏时，
                // 保证拔插 MagSafe / USB-C 后端口列表与物理状态最终一致（2 秒内收敛）
                monitor.refresh()
                // 实时功率采样（每 2 秒刷新 watts/amps/voltage，历史样本队列）
                powerStore.sampleNow()
                // 派生 Pro 指标
                self.refreshProDerived(monitor: monitor, cableStore: self.cableStore ?? CableHistoryStore())
                // Widget 快照
                self.updateWidgetDefaults()
                // 更新 popover 内容（若已显示）
                if let popover = self.popover, popover.isShown {
                    self.updatePopoverContent()
                }
            }
        }
        // 注册到 common mode：菜单栏 popover 打开/拖拽时主 runloop 处于
        // eventTracking mode，.default mode 的 Timer 会被暂停，导致充电器
        // 插拔后状态卡在旧值；common mode 保证采样兜底在交互期间持续生效。
        powerTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func refreshProDerived(monitor: USBMonitor, cableStore: CableHistoryStore) {
        // 端口健康计数器（从端口控制器读取）
        let controllers = monitor.readPortControllers()
        healthCache = monitor.healthStats(from: controllers)
        // 液体检测状态（LDCM）
        liquidState = monitor.readLiquidDetection()
        // 线缆电阻估算
        resistance = ProLogic.estimateCableResistance(power: monitor.power)
        // 电阻不可估算时的原因（数据源缺失 / 压差不足等，仅在接入电源时返回）
        resistanceReason = ProLogic.resistanceUnavailableReason(power: monitor.power)
    }

    private func updatePopoverContent() {
        guard let monitor, let cableStore, let popover,
              let hosting = popover.contentViewController as? NSHostingController<ContentView> else { return }
        // 只替换 rootView 触发 SwiftUI diff 更新，不重建 contentViewController：
        // 重建会丢失 ScrollView 滚动状态（用户下拉后 2 秒采样一刷新就跳回顶部）。
        hosting.rootView = ContentView(
            monitor: monitor,
            settings: settings,
            cableStore: cableStore,
            healthCache: healthCache,
            liquidState: liquidState,
            resistance: resistance,
            resistanceReason: resistanceReason
        )
    }

    private func updateWidgetDefaults() {
        guard let monitor else { return }
        let connected = monitor.ports.filter { $0.isConnected }
        let first = connected.first
        var snap = PortLensWidgetSnapshot()
        snap.connectedCount = connected.count
        snap.batteryPercent = monitor.power.batteryPercent
        snap.isCharging = monitor.power.isCharging
        snap.chargingWatts = monitor.power.wattsNow
        snap.certificationText = first?.certificationManufacturer ?? first?.certification ?? ""
        snap.trustWarning = first?.trustWarning ?? ""
        snap.lastUpdate = Date()
        snap.write()
    }

    func applicationWillTerminate(_ notification: Notification) {
        powerTimer?.invalidate()
        powerTimer = nil
        monitor?.stop()
    }

    static func statusImage(connected: Bool) -> NSImage {
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .medium)
        let name = connected ? "cable.connector" : "cable.connector.slash"
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else {
            return NSImage()
        }
        // 着色：连接=绿，断开=灰
        let image = NSImage(size: base.size)
        image.lockFocus()
        (connected ? NSColor.systemGreen : NSColor.tertiaryLabelColor).set()
        let rect = NSRect(origin: .zero, size: base.size)
        base.draw(in: rect)
        rect.fill(using: .sourceAtop)
        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    // MARK: - 动态功能模式图标（菜单栏）

    /// 按电量返回对应电池 SF Symbol
    static func batterySymbol(percent: Int) -> String {
        switch percent {
        case ..<15: return "battery.0percent"
        case ..<40: return "battery.25percent"
        case ..<65: return "battery.50percent"
        case ..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }

    /// 动态模式图标：电池/充电状态 SF Symbol，模板渲染自动适配深色/浅色菜单栏
    static func dynamicStatusImage(power: PowerState) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: 13, weight: .medium)
        let symbol: String
        if power.isCharging {
            // 充电中：满格电池 + 闪电（样式参考附图）
            symbol = "battery.100percent.bolt"
        } else {
            symbol = batterySymbol(percent: power.batteryPercent)
        }
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config)
        image?.isTemplate = true
        return image
    }

    /// 呼吸动态图标：中心电池 symbol（充电闪电/电量分档）+ 外圈光晕
    /// 外圈光晕按电量分级（<20% 红、<30% 黄、≥30% 绿），高速设备接入=彩虹渐变闪一次
    static func breathingDynamicStatusImage(power: PowerState, phase: Double, rainbow: Bool, charging: Bool, scale: CGFloat = 1.0) -> NSImage? {
        let size = NSSize(width: 26, height: 22)
        let image = NSImage(size: size)
        image.lockFocus()
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        // 状态跃迁放大：整体缩放居中（1.0 → 约 1.28 弹簧衰减复位）
        if scale != 1.0 {
            let t = NSAffineTransform()
            t.translateX(by: center.x, yBy: center.y)
            t.scale(by: scale)
            t.translateX(by: -center.x, yBy: -center.y)
            t.concat()
        }
        // 呼吸相位（2 秒周期，正弦 0...1）
        let breathe = 0.5 + 0.5 * sin((phase / 2.0).truncatingRemainder(dividingBy: 1.0) * 2.0 * .pi)
        let baseColor: NSColor
        if rainbow {
            let hue = (phase * 0.45).truncatingRemainder(dividingBy: 1.0)
            baseColor = NSColor(calibratedHue: hue, saturation: 0.85, brightness: 1.0, alpha: 1.0)
        } else {
            baseColor = BatteryLevelColor.nsColor(for: power.batteryPercent)
        }
        // 外圈光晕（两层圆环呼吸）
        for layer in 0..<2 {
            let r = 4.2 + breathe * 2.4 + Double(layer) * 3.2
            let alpha = (0.22 + breathe * 0.33) * (layer == 0 ? 1.0 : 0.55)
            let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
            baseColor.withAlphaComponent(alpha).setStroke()
            ring.lineWidth = 1.4
            ring.stroke()
        }
        // 中心电池 symbol（分级色，明暗菜单栏均清晰；17pt 在 15pt 基础上进一步放大，内部符号按比例微调仍留足空间）
        if let symbol = Self.tintedSymbol(batterySymbol(percent: power.batteryPercent), pointSize: 19, color: baseColor.withAlphaComponent(0.95)) {
            symbol.draw(in: NSRect(x: (size.width - symbol.size.width) / 2,
                                   y: (size.height - symbol.size.height) / 2,
                                   width: symbol.size.width,
                                   height: symbol.size.height))
        }
        // 中间状态符号：充电中→白色呼吸闪电；已接入未充电→白色静态插头；未接入→无
        let centerSymbol: (name: String, pointSize: CGFloat, alpha: CGFloat, scale: CGFloat)?
        if charging && power.externalConnected {
            // 白色闪电呼吸：透明度 + 尺寸周期脉动（约 1.6 秒一闪；10.5pt 随电池 19pt 比例缩小，内嵌电池轮廓内）
            let bolt = 0.5 + 0.5 * sin((phase / 1.6).truncatingRemainder(dividingBy: 1.0) * 2.0 * .pi)
            centerSymbol = ("bolt.fill", 10.5, 0.72 + 0.28 * bolt, 0.88 + 0.12 * bolt)
        } else if power.externalConnected {
            // 白色纤细线条插头：沿用原 powerplug 造型，改用非填充轮廓版 + 细字重（.light），保持造型不变仅减细线条
            if let plug = Self.tintedSymbol("powerplug", pointSize: 12, color: NSColor.white.withAlphaComponent(0.95), weight: .light) {
                let w = plug.size.width
                let h = plug.size.height
                plug.draw(in: NSRect(x: center.x - w / 2,
                                     y: center.y - h / 2,
                                     width: w,
                                     height: h))
            }
            centerSymbol = nil
        } else {
            centerSymbol = nil
        }
        if let cs = centerSymbol,
           let symbol = Self.tintedSymbol(cs.name, pointSize: cs.pointSize, color: NSColor.white.withAlphaComponent(cs.alpha)) {
            let w = symbol.size.width * cs.scale
            let h = symbol.size.height * cs.scale
            symbol.draw(in: NSRect(x: center.x - w / 2,
                                   y: center.y - h / 2,
                                   width: w,
                                   height: h))
        }
        image.unlockFocus()
        return image
    }

    /// 宽体色块模式图标：加宽电池壳（相比 19pt 标准 battery symbol 明显加宽），
    /// 内部以色块比例展示剩余电量（红黄绿分级、圆角、细腻纵向渐变 + 柔和高光、每 10% 淡分段格线），
    /// 百分比数字严格按内部填充色块区域水平居中（文字中心 == 色块中心）；
    /// 充电=白色呼吸闪电 / 已接入未充电=白色纤细插头 置于电池壳右端（端子）外侧紧贴位置（左端距端子右缘 1.5pt≈3px）。
    /// 画布 74pt 宽，保证状态跃迁放大（scale 1.28）与呼吸放大时壳外符号仍不溢出画布。
    /// phase 传 nil 时输出静态帧（无光晕、符号静止）；传 Double 时启用外圈分级光晕呼吸与闪电脉动，
    /// 并支持状态跃迁放大 scale 与高速设备彩虹闪（rainbow）。
    static func wideBarStatusImage(power: PowerState, phase: Double? = nil, rainbow: Bool = false, scale: CGFloat = 1.0) -> NSImage? {
        let size = NSSize(width: 74, height: 28)
        let image = NSImage(size: size)
        image.lockFocus()
        let center = NSPoint(x: size.width / 2, y: size.height / 2)
        // 状态跃迁放大：整体缩放居中（与动态模式一致的弹簧衰减复位）
        if scale != 1.0 {
            let t = NSAffineTransform()
            t.translateX(by: center.x, yBy: center.y)
            t.scale(by: scale)
            t.translateX(by: -center.x, yBy: -center.y)
            t.concat()
        }
        let breathing = phase != nil
        let p = phase ?? 0.0
        // 呼吸相位（2 秒周期，正弦 0...1）；静态帧固定 0.5 使光晕半亮
        let breathe = breathing ? 0.5 + 0.5 * sin((p / 2.0).truncatingRemainder(dividingBy: 1.0) * 2.0 * .pi) : 0.5
        let baseColor: NSColor
        if rainbow {
            let hue = (p * 0.45).truncatingRemainder(dividingBy: 1.0)
            baseColor = NSColor(calibratedHue: hue, saturation: 0.85, brightness: 1.0, alpha: 1.0)
        } else {
            baseColor = BatteryLevelColor.nsColor(for: power.batteryPercent)
        }
        // 外圈光晕（两层圆环呼吸，仅呼吸模式绘制）
        if breathing {
            for layer in 0..<2 {
                let r = 6.0 + breathe * 3.0 + Double(layer) * 4.0
                let alpha = (0.22 + breathe * 0.33) * (layer == 0 ? 1.0 : 0.55)
                let ring = NSBezierPath(ovalIn: NSRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2))
                baseColor.withAlphaComponent(alpha).setStroke()
                ring.lineWidth = 1.4
                ring.stroke()
            }
        }
        // 电池壳（宽体圆角矩形，玻璃感：深色半透明底 + 细描边 + 顶部柔和高光）
        let shellRect = NSRect(x: 3.5, y: 4.5, width: 47.0, height: 20.0)
        let shell = NSBezierPath(roundedRect: shellRect, xRadius: 4.0, yRadius: 4.0)
        NSColor(calibratedWhite: 0.12, alpha: 0.55).setFill()
        shell.fill()
        NSColor(calibratedWhite: 0.55, alpha: 0.5).setStroke()
        shell.lineWidth = 1.0
        shell.stroke()
        // 顶部柔和玻璃高光（壳内 1pt 细线）
        NSColor(calibratedWhite: 1.0, alpha: 0.15).setStroke()
        let shellHi = NSBezierPath()
        shellHi.move(to: NSPoint(x: shellRect.minX + 2.6, y: shellRect.maxY - 1.3))
        shellHi.line(to: NSPoint(x: shellRect.maxX - 2.6, y: shellRect.maxY - 1.3))
        shellHi.lineWidth = 0.8
        shellHi.stroke()
        // 正极端子（右侧凸头，同色系）
        let terminalRect = NSRect(x: 50.5, y: 10.0, width: 2.5, height: 9.0)
        let terminal = NSBezierPath(roundedRect: terminalRect, xRadius: 1.0, yRadius: 1.0)
        NSColor(calibratedWhite: 0.12, alpha: 0.55).setFill()
        terminal.fill()
        NSColor(calibratedWhite: 0.55, alpha: 0.5).setStroke()
        terminal.lineWidth = 1.0
        terminal.stroke()
        // 内部填充区（壳内缩 2.5pt）
        let innerRect = NSRect(x: shellRect.minX + 2.5, y: shellRect.minY + 2.5,
                               width: shellRect.width - 5.0, height: shellRect.height - 5.0)
        // 空槽底色：先在整个壳内铺一层柔和基底（电量等级色 22%），使色块右缘两侧均为"绿系"底色，
        // 色块与空槽亮度差大幅减小，消除非满电时"色块右缘硬边界"被误读为竖线的观感
        let slot = NSBezierPath(roundedRect: innerRect, xRadius: 1.6, yRadius: 1.6)
        baseColor.withAlphaComponent(0.22).setFill()
        slot.fill()
        // 每 10% 淡分段格线（在空槽与色块上方均可见，辅助比例读取）
        let segments = 10
        let segW = innerRect.width / CGFloat(segments)
        let grid = NSBezierPath()
        for i in 1..<segments {
            let x = innerRect.minX + segW * CGFloat(i)
            grid.move(to: NSPoint(x: x, y: innerRect.minY + 1.2))
            grid.line(to: NSPoint(x: x, y: innerRect.maxY - 1.2))
        }
        NSColor(calibratedWhite: 1.0, alpha: 0.10).setStroke()
        grid.lineWidth = 0.5
        grid.stroke()
        // 电量色块：按百分比连续填充（红黄绿分级），细腻纵向渐变 + 柔和高光
        let ratio = max(0.0, min(1.0, CGFloat(power.batteryPercent) / 100.0))
        let filledWidth = ratio > 0 ? max(innerRect.width * ratio, 1.6) : 0.0
        let filledRect = NSRect(x: innerRect.minX, y: innerRect.minY, width: filledWidth, height: innerRect.height)
        if filledRect.width > 0 {
            let path = NSBezierPath(roundedRect: filledRect, xRadius: 1.6, yRadius: 1.6)
            let top = baseColor.blended(withFraction: 0.38, of: NSColor.white) ?? baseColor
            let bottom = baseColor.withAlphaComponent(0.82)
            if let grad = NSGradient(colors: [top, bottom]) {
                grad.draw(in: path, angle: 90)
            } else {
                baseColor.setFill()
                path.fill()
            }
            // 色块右缘柔化：5pt 水平淡出（叠加在空槽底色上），过渡更宽更缓，彻底消除色块右缘硬边界竖线观感
            if filledRect.width > 5.0 {
                let fadeW: CGFloat = 5.0
                let fadeRect = NSRect(x: filledRect.maxX - fadeW, y: innerRect.minY, width: fadeW, height: innerRect.height)
                let fadeGrad = NSGradient(colors: [
                    baseColor.withAlphaComponent(0.85),
                    baseColor.withAlphaComponent(0.10)
                ])
                fadeGrad?.draw(in: fadeRect, angle: 0)
            }
            // 色块顶部柔和高光
            NSColor(calibratedWhite: 1.0, alpha: 0.26).setStroke()
            let fillHi = NSBezierPath()
            fillHi.move(to: NSPoint(x: filledRect.minX + 1.3, y: filledRect.maxY - 0.9))
            fillHi.line(to: NSPoint(x: filledRect.maxX - 1.3, y: filledRect.maxY - 0.9))
            fillHi.lineWidth = 0.7
            fillHi.stroke()
        }
        // 电池内部百分比数字（白色粗体 monospaced，半透明深色阴影，电池内部水平居中；不受色块长度影响）
        let pctText = "\(power.batteryPercent)%" as NSString
        let numFont = NSFont.monospacedSystemFont(ofSize: 11.0, weight: .bold)
        let numShadow = NSShadow()
        numShadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        numShadow.shadowBlurRadius = 1.2
        numShadow.shadowOffset = NSSize(width: 0, height: -0.5)
        let numAttrs: [NSAttributedString.Key: Any] = [
            .font: numFont,
            .foregroundColor: NSColor.white,
            .shadow: numShadow
        ]
        let numSize = pctText.size(withAttributes: numAttrs)
        // 数字水平居中于填充色块中心（文字中心 == 色块中心，随电量比例移动）。
        // size(withAttributes) 是 typographic 度量，含字面空白，直接用其半宽定位会使字形可见中心偏右；
        // 用 CoreText 行 ink 边界得到字形可见中心相对绘制起点的偏移，反推绘制起点，保证可见中心 == 色块中心。
        var numX = filledRect.midX
        if let ctx = NSGraphicsContext.current {
            let line = CTLineCreateWithAttributedString(NSAttributedString(string: pctText as String, attributes: numAttrs))
            let ink = CTLineGetImageBounds(line, ctx.cgContext)
            if ink.width > 0 {
                numX = filledRect.midX - ink.midX
            } else {
                numX = filledRect.midX - numSize.width / 2
            }
        }
        numX = max(numX, innerRect.minX + 0.5)
        let numY = shellRect.midY - numSize.height / 2
        pctText.draw(at: NSPoint(x: numX, y: numY), withAttributes: numAttrs)
        // 状态符号（电池壳右侧外部、紧贴端子右缘外侧垂直居中；拔掉充电器不显示）
        // 统一规则：端子描边/圆角使可见右缘相对 terminalRect.maxX 收缩约 1pt（≈52pt）；SF Symbol
        // 图像左缘到可见字形约 1pt 内边距。以可见端子右缘为基准外移 0.5pt，可见字形与端子约 3px，
        // 满足 2-4px 间距、紧贴不脱节、不重叠端子/色块。
        let terminalVisualRight = terminalRect.maxX - 1.0
        // 充电闪电：放大到 11pt 并外移 4pt，避免被误读为电池内部竖线（8pt 紧贴时主体窄小形似竖线）
        let symbolGap: CGFloat = 4.0
        if power.isCharging && power.externalConnected {
            // 白色呼吸闪电：透明度 + 尺寸周期脉动（约 1.6 秒一闪），壳右端端子外侧、间距 4pt 远离电池
            let bolt = breathing ? 0.5 + 0.5 * sin((p / 1.6).truncatingRemainder(dividingBy: 1.0) * 2.0 * .pi) : 1.0
            if let s = Self.tintedSymbol("bolt.fill", pointSize: 11.0, color: NSColor.white.withAlphaComponent(0.70 + 0.30 * bolt)) {
                let w = s.size.width * (0.92 + 0.08 * bolt)
                let h = s.size.height * (0.92 + 0.08 * bolt)
                s.draw(in: NSRect(x: terminalVisualRight + symbolGap, y: 14.5 - h / 2, width: w, height: h))
            }
        } else if power.externalConnected {
            // USB-C 公头插头（苹果式竖放）：竖放扁平圆角矩形主体 + 中央细横线舌片 + 底部中点平滑下垂电线；
            // 主体几何 7x9pt（圆角 1.5 扁平方正）、舌片 1.5pt 细线、电线 2pt 圆帽，
            // 深灰 0.35，总视觉高 15pt，与电池端子间距约 5.5pt、整体垂直居中
            let stroke: CGFloat = 2.0
            let plugGap: CGFloat = 6.0                       // 插头与电池可见右缘的间距（pt），目标约 4-6pt
            let bodyW: CGFloat = 7.0                          // 主体几何宽（pt）
            let bodyH: CGFloat = 9.0                          // 主体几何高（pt）
            let radius: CGFloat = 1.5                         // 圆角（1.2-1.8 范围，非胶囊全圆）
            let cx = terminalVisualRight + plugGap + bodyW / 2 + 0.5   // 主体中心 x
            let cyBody: CGFloat = 16.0                        // 主体几何中心 y（整体 bbox 居中于 14pt）
            NSColor(white: 0.35, alpha: 1.0).setStroke()      // 深灰描边，浅色菜单栏上清晰柔和不刺眼
            // 主体：竖放扁平圆角矩形（USB-C 公头轮廓），上下左右对称
            let body = NSBezierPath(roundedRect: NSRect(x: cx - bodyW / 2, y: cyBody - bodyH / 2, width: bodyW, height: bodyH),
                                    xRadius: radius, yRadius: radius)
            body.lineWidth = stroke
            body.lineJoinStyle = .round
            body.stroke()
            // 舌片：主体中央一条细横线（USB-C 端口识别特征），1.5pt 细线区分层次，精确水平居中、垂直位于主体正中
            let tongue = NSBezierPath()
            tongue.move(to: NSPoint(x: cx - 1.75, y: cyBody))
            tongue.line(to: NSPoint(x: cx + 1.75, y: cyBody))
            tongue.lineWidth = 1.5
            tongue.lineCapStyle = .round
            tongue.stroke()
            // 电线：主体底部中点垂直向下直线短线，长 4.5pt、线宽 2pt 圆帽，无弯曲无水平偏移
            let wire = NSBezierPath()
            wire.move(to: NSPoint(x: cx, y: cyBody - bodyH / 2))
            wire.line(to: NSPoint(x: cx, y: cyBody - bodyH / 2 - 4.5))
            wire.lineWidth = stroke
            wire.lineCapStyle = .round
            wire.stroke()
        }
        image.unlockFocus()
        return image
    }

    /// SF Symbol 染色（sourceAtop 保持 alpha 形状）
    private static func tintedSymbol(_ name: String, pointSize: CGFloat, color: NSColor, weight: NSFont.Weight = .medium) -> NSImage? {
        let config = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(config) else { return nil }
        let size = symbol.size
        let tinted = NSImage(size: size)
        tinted.lockFocus()
        symbol.draw(in: NSRect(origin: .zero, size: size))
        color.set()
        NSRect(origin: .zero, size: size).fill(using: .sourceAtop)
        tinted.unlockFocus()
        return tinted
    }

    /// 动态模式文字：电量百分比；充电中可附加实时输入功率（绿色）
    /// 功率取电池端电压×电流（Amperage×Voltage，与系统菜单栏充电功率口径一致），
    /// 不用 IPDInputPower（协商档恒定虚高）与 SystemPowerIn（含整机负载）。
    static func dynamicStatusTitle(power: PowerState, includeWatts: Bool = true) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let text = NSMutableAttributedString(
            string: "\(power.batteryPercent)%",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        if power.isCharging, includeWatts {
            let w = Int(power.wattsNow.rounded())
            text.append(NSAttributedString(
                string: " \(w)W",
                attributes: [.font: font, .foregroundColor: NSColor.systemGreen]
            ))
        }
        return text
    }

    /// 动态模式文字（填充条）：电量百分比 + 充电功率填充条（▮▮▮▯▯▯▯▯▯▯）
    static func dynamicStatusBarTitle(power: PowerState) -> NSAttributedString {
        let font = NSFont.monospacedDigitSystemFont(ofSize: 11.5, weight: .medium)
        let text = NSMutableAttributedString(
            string: "\(power.batteryPercent)%",
            attributes: [.font: font, .foregroundColor: NSColor.labelColor]
        )
        if power.isCharging {
            let ratio = max(0, min(1, power.wattsNow / 100.0))
            let filled = Int((ratio * 10).rounded())
            let bar = String(repeating: "▮", count: filled) + String(repeating: "▯", count: 10 - filled)
            text.append(NSAttributedString(
                string: " " + bar,
                attributes: [
                    .font: NSFont.systemFont(ofSize: 9, weight: .medium),
                    .foregroundColor: NSColor.systemGreen
                ]
            ))
        }
        return text
    }

    // MARK: - 右键菜单补全：Settings / Licence / Check for Updates / About

    @objc private func openSettings() {
        if let window = settingsWindow, window.isVisible {
            window.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 545),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "PortLens 设置"
        window.contentViewController = NSHostingController(rootView: SettingsView(settings: settings))
        window.center()
        window.makeKeyAndOrderFront(nil)
        settingsWindow = window
    }

    @objc private func showLicence() {
        let alert = NSAlert()
        alert.messageText = "PortLens License"
        alert.informativeText = "MIT License\n\nCopyright (c) 2026 PortLens\n\nPermission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the \"Software\"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func checkForUpdates() {
        let alert = NSAlert()
        alert.messageText = "Check for Updates"
        alert.informativeText = "当前为自签名本地构建（Bundle ID com.marvis.portlens），暂无在线更新通道。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func showAbout() {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        let alert = NSAlert()
        alert.messageText = "PortLens"
        alert.informativeText = "版本 \(version) (\(build))\nmacOS 菜单栏 USB-C / Thunderbolt / MagSafe 分析工具\nApple Silicon only · 无第三方依赖"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    // MARK: - 连接/断开系统通知

    private func postConnectionNotification(title: String, body: String) {
        guard settings.notificationsEnabled else { return }
        let center = UNUserNotificationCenter.current()
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async {
                let content = UNMutableNotificationContent()
                content.title = title
                content.body = body
                content.sound = .default
                let request = UNNotificationRequest(
                    identifier: UUID().uuidString,
                    content: content,
                    trigger: nil
                )
                center.add(request)
            }
        }
    }
}
