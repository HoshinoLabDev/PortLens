import SwiftUI
import Combine

// MARK: - 设置窗口（第二批功能：菜单栏设置补全）

/// 设置项一览：Dock 应用模式、菜单栏图标、实时充电瓦数、字号、透明度、
/// 隐藏空端口、开机启动、跳过深度 USB 探测（KVM 兼容）、显示技术细节、通知。
struct SettingsView: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingL) {
            header
            Divider().opacity(0.5)

            GroupBox(label: Label("外观", systemImage: "paintbrush")) {
                VStack(alignment: .leading, spacing: 10) {
                    settingPicker(
                        title: "Dock 应用模式",
                        selection: $settings.dockMode,
                        options: SettingsStore.DockMode.allCases
                    )
                    settingPicker(
                        title: "菜单栏图标",
                        selection: $settings.iconMode,
                        options: SettingsStore.IconMode.allCases
                    )
                    settingPicker(
                        title: "菜单栏实时充电瓦数",
                        selection: $settings.iconChargeDisplay,
                        options: SettingsStore.IconChargeDisplay.allCases
                    )
                    HStack {
                        Text("字号缩放")
                        Slider(value: $settings.fontSizeScale, in: 0.8...1.4, step: 0.05)
                        Text(String(format: "%.0f%%", settings.fontSizeScale * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                    HStack {
                        Text("窗口透明度")
                        Slider(value: $settings.windowOpacity, in: 0.5...1.0, step: 0.05)
                        Text(String(format: "%.0f%%", settings.windowOpacity * 100))
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 44, alignment: .trailing)
                    }
                }
                .padding(6)
            }
            .glassGroup()

            GroupBox(label: Label("动画效果", systemImage: "sparkles")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("能量流粒子（端口内流动光点，功率越高越亮）", isOn: $settings.energyFlowEnabled)
                    Toggle("扫描透视（插拔时扫描光线扫过端口卡片）", isOn: $settings.scanEffectEnabled)
                    Toggle("呼吸图标（菜单栏图标光晕呼吸 + 实时功率）", isOn: $settings.breathingIconEnabled)
                }
                .toggleStyle(.checkbox)
                .padding(6)
            }
            .glassGroup()

            GroupBox(label: Label("行为", systemImage: "gearshape")) {
                VStack(alignment: .leading, spacing: 8) {
                    Toggle("隐藏空端口", isOn: $settings.hideEmptyPorts)
                    Toggle("开机启动", isOn: $settings.launchAtLogin)
                    Toggle("跳过深度 USB 探测（KVM 兼容）", isOn: $settings.skipDeepUSBProbe)
                    Toggle("显示技术细节（VID / PID / XID）", isOn: $settings.showTechDetails)
                    Toggle("连接/断开系统通知", isOn: $settings.notificationsEnabled)
                }
                .toggleStyle(.checkbox)
                .padding(6)
            }
            .glassGroup()

            Spacer()
            HStack(spacing: 6) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                Text("PortLens · 无第三方依赖 · 数据仅来自本机 IORegistry")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(Theme.spacingL)
        .frame(width: 440, height: 585)
        .background(VisualEffectBackground(material: .underWindowBackground, blendingMode: .behindWindow))
    }

    private var header: some View {
        HStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Theme.brandGradient)
                    .frame(width: 32, height: 32)
                    .shadow(color: Theme.accent.opacity(0.35), radius: 4, y: 0)
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text("设置")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                Text("外观与行为偏好")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private func settingPicker<Option: RawRepresentable & CaseIterable & Hashable>(
        title: String,
        selection: Binding<Option>,
        options: Option.AllCases
    ) -> some View where Option.RawValue == String {
        Picker(title, selection: selection) {
            ForEach(Array(options), id: \.self) { option in
                Text(displayName(of: option)).tag(option)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func displayName<Option: RawRepresentable & CaseIterable & Hashable>(of option: Option) -> String
        where Option.RawValue == String {
        // 通过反射读取 displayName 计算属性
        if let iconMode = option as? SettingsStore.IconMode { return iconMode.displayName }
        if let dockMode = option as? SettingsStore.DockMode { return dockMode.displayName }
        if let display = option as? SettingsStore.IconChargeDisplay { return display.displayName }
        return "\(option)"
    }
}
