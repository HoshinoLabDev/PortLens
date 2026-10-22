import WidgetKit
import SwiftUI
import AppKit

// MARK: - PortLens Widget（小 / 中 / 大 三尺寸）
// 数据来源：主 App 通过 AppGroup 容器（或用户 Application Support）写入 widgetSnapshot.json。

struct PortLensSnapshot: Codable {
    var connectedCount: Int = 0
    var batteryPercent: Int = 0
    var isCharging: Bool = false
    var chargingWatts: Double = 0
    var certificationText: String = ""
    var trustWarning: String = ""
    var lastUpdate: Date = Date()

    static let suiteName = "group.com.marvis.portlens"

    /// 共享快照路径：统一使用用户 Application Support（主 App 与 Widget 均可读写）
    static var sharedURL: URL {
        let fm = FileManager.default
        let support = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("PortLens/widgetSnapshot.json")
    }
}

// MARK: - Provider

struct PortLensProvider: TimelineProvider {
    func placeholder(in context: Context) -> PortLensEntry {
        PortLensEntry(date: Date(), snapshot: PortLensSnapshot(connectedCount: 2, batteryPercent: 80, isCharging: true, chargingWatts: 60, certificationText: "USB-IF 认证 · 厂商", lastUpdate: Date()))
    }

    func getSnapshot(in context: Context, completion: @escaping (PortLensEntry) -> Void) {
        completion(PortLensEntry(date: Date(), snapshot: Self.readSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<PortLensEntry>) -> Void) {
        let entry = PortLensEntry(date: Date(), snapshot: Self.readSnapshot())
        // 每 5 分钟刷新一次；用户打开 widget 时也会触发 getSnapshot
        let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: Date()) ?? Date().addingTimeInterval(300)
        completion(Timeline(entries: [entry], policy: .after(refresh)))
    }

    static func readSnapshot() -> PortLensSnapshot {
        let url = PortLensSnapshot.sharedURL
        guard let data = try? Data(contentsOf: url),
              let snap = try? JSONDecoder().decode(PortLensSnapshot.self, from: data) else {
            return PortLensSnapshot()
        }
        return snap
    }
}

struct PortLensEntry: TimelineEntry {
    let date: Date
    let snapshot: PortLensSnapshot
}

// MARK: - Views（小 / 中 / 大）

struct PortLensWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PortLensEntry

    private var snap: PortLensSnapshot { entry.snapshot }

    var body: some View {
        switch family {
        case .systemSmall:
            smallView
        case .systemMedium:
            mediumView
        default:
            largeView
        }
    }

    // 小：图标 + 连接数 + 充电状态
    private var smallView: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "cable.connector")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.blue)
                Spacer()
                if snap.isCharging {
                    Text("\(Int(snap.chargingWatts))W")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(.green)
                }
            }
            Text("\(snap.connectedCount)")
                .font(.system(size: 34, weight: .bold, design: .rounded))
            Text(snap.connectedCount > 0 ? "端口已连接" : "无连接")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            if !snap.certificationText.isEmpty {
                Text(snap.certificationText)
                    .font(.system(size: 8))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
        .padding(12)
    }

    // 中：连接 + 电池 + 认证/警告摘要
    private var mediumView: some View {
        HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Label("\(snap.connectedCount) 个端口已连接", systemImage: "cable.connector")
                    .font(.system(size: 14, weight: .semibold))
                HStack(spacing: 6) {
                    Image(systemName: snap.isCharging ? "battery.100percent.bolt" : "battery.75percent")
                        .foregroundStyle(snap.isCharging ? .green : .secondary)
                    Text("\(snap.batteryPercent)%")
                        .font(.system(size: 13, weight: .medium, design: .rounded))
                    if snap.isCharging {
                        Text("\(Int(snap.chargingWatts))W")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.green)
                    }
                }
                if !snap.trustWarning.isEmpty {
                    Label(snap.trustWarning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10))
                        .foregroundStyle(.orange)
                        .lineLimit(2)
                }
            }
            Spacer()
            if !snap.certificationText.isEmpty {
                VStack(alignment: .trailing, spacing: 4) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(.green)
                    Text(snap.certificationText)
                        .font(.system(size: 8))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.trailing)
                        .lineLimit(2)
                }
            }
        }
        .padding(14)
    }

    // 大：完整状态列表
    private var largeView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("PortLens", systemImage: "cable.connector")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.blue)
            Divider()
            row("已连接端口", value: "\(snap.connectedCount)")
            row("电池", value: "\(snap.batteryPercent)%")
            if snap.isCharging {
                row("充电功率", value: "\(Int(snap.chargingWatts))W", color: .green)
            } else {
                row("充电状态", value: "未充电", color: .secondary)
            }
            if !snap.certificationText.isEmpty {
                row("USB-IF 认证", value: snap.certificationText)
            }
            if !snap.trustWarning.isEmpty {
                Label(snap.trustWarning, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.orange)
            }
            Spacer()
            Text("更新于 " + snap.lastUpdate.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 8))
                .foregroundStyle(.tertiary)
        }
        .padding(14)
    }

    private func row(_ title: String, value: String, color: Color = .primary) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(color)
                .lineLimit(1)
        }
    }
}

// MARK: - Widget Bundle

@main
struct PortLensWidgetBundle: WidgetBundle {
    var body: some Widget {
        PortLensWidget()
    }
}

struct PortLensWidget: Widget {
    let kind = "PortLensWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: PortLensProvider()) { entry in
            PortLensWidgetView(entry: entry)
                .containerBackground(for: .widget) {
                    Color(nsColor: .windowBackgroundColor)
                }
        }
        .configurationDisplayName("PortLens 线缆状态")
        .description("实时显示已连接端口、充电功率与线缆认证状态")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
