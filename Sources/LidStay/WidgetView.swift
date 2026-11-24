import AppKit
import SwiftUI

extension EnvironmentValues {
    @Entry var useStaticBackdropForRender: Bool = false
}

enum WidgetLayout {
    static let width: CGFloat = 296
    static let height: CGFloat = 138
    static let cornerRadius: CGFloat = 22
}

struct VisualEffectBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .hudWindow
    var blendingMode: NSVisualEffectView.BlendingMode = .behindWindow
    var cornerRadius: CGFloat = WidgetLayout.cornerRadius

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = blendingMode
        view.state = .active
        view.isEmphasized = true
        view.wantsLayer = true
        view.layer?.cornerRadius = cornerRadius
        view.layer?.cornerCurve = .continuous
        view.layer?.masksToBounds = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = material
        nsView.blendingMode = blendingMode
        nsView.state = .active
        nsView.wantsLayer = true
        nsView.layer?.cornerRadius = cornerRadius
        nsView.layer?.cornerCurve = .continuous
        nsView.layer?.masksToBounds = true
    }
}

struct WidgetView: View {
    @Bindable var powerManager: PowerManager
    @Environment(\.useStaticBackdropForRender) private var useStaticBackdropForRender
    @State private var isHoveringCard = false
    @State private var showSettingsPopover = false
    @State private var showFullError = false

    let onTogglePin: () -> Void
    let onHideWidget: () -> Void

    init(
        powerManager: PowerManager,
        onTogglePin: @escaping () -> Void,
        onHideWidget: @escaping () -> Void
    ) {
        self.powerManager = powerManager
        self.onTogglePin = onTogglePin
        self.onHideWidget = onHideWidget
    }

    private var l10n: L10n {
        L10n(language: powerManager.language)
    }

    private var isAwakeActive: Bool {
        powerManager.status.isAwakeActive
    }

    private var isUnknownState: Bool {
        powerManager.status.sleepState == .unknown
    }

    private var isPinned: Bool {
        powerManager.isPinnedOnTop
    }

    var body: some View {
        ZStack {
            cardBackground

            VStack(spacing: 10) {
                headerRow
                mainToggleRow
                footerRow
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
        }
        .frame(width: WidgetLayout.width, height: WidgetLayout.height)
        .clipShape(RoundedRectangle(cornerRadius: WidgetLayout.cornerRadius, style: .continuous))
        .overlay(cardBorder)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.18)) {
                isHoveringCard = hovering
            }
        }
        .animation(.spring(response: 0.34, dampingFraction: 0.82), value: isAwakeActive)
        .animation(.easeInOut(duration: 0.2), value: powerManager.isUpdating)
    }

    private var cardBackground: some View {
        ZStack {
            if useStaticBackdropForRender {
                RoundedRectangle(cornerRadius: WidgetLayout.cornerRadius, style: .continuous)
                    .fill(Color(red: 0.14, green: 0.15, blue: 0.20).opacity(0.84))
            } else {
                VisualEffectBackdrop(
                    material: .popover,
                    blendingMode: .behindWindow,
                    cornerRadius: WidgetLayout.cornerRadius
                )
            }

            if isAwakeActive {
                RadialGradient(
                    colors: [
                        Color(red: 1.0, green: 0.58, blue: 0.12).opacity(0.18),
                        Color.clear
                    ],
                    center: .topTrailing,
                    startRadius: 12,
                    endRadius: 220
                )
            }
        }
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: WidgetLayout.cornerRadius, style: .continuous)
            .strokeBorder(
                isAwakeActive
                    ? Color.orange.opacity(0.42)
                    : Color(nsColor: .separatorColor).opacity(0.55),
                lineWidth: 1
            )
    }

    private var headerRow: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Circle()
                    .fill(statusDotColor)
                    .frame(width: 7, height: 7)
                    .shadow(color: isAwakeActive ? Color.orange.opacity(0.8) : .clear, radius: 4)

                Text("LidStay")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)

                powerBadge
            }

            Spacer(minLength: 4)

            HStack(spacing: 4) {
                HeaderIconButton(
                    systemName: isPinned ? "pin.fill" : "pin",
                    isActive: isPinned,
                    accessibilityLabel: isPinned ? l10n.pinAccessOn : l10n.pinAccessOff,
                    helpText: isPinned ? l10n.pinHelpOn : l10n.pinHelpOff
                ) {
                    onTogglePin()
                }

                HeaderIconButton(
                    systemName: "slider.horizontal.3",
                    isActive: showSettingsPopover,
                    accessibilityLabel: l10n.optionsAccess,
                    helpText: l10n.optionsHelp
                ) {
                    showSettingsPopover.toggle()
                }
                .popover(isPresented: $showSettingsPopover, arrowEdge: .bottom) {
                    QuickSettingsPopover(
                        powerManager: powerManager,
                        onHideWidget: {
                            showSettingsPopover = false
                            onHideWidget()
                        }
                    )
                }
            }
            .opacity(isHoveringCard || showSettingsPopover || isPinned ? 1.0 : 0.78)
        }
    }

    private var statusDotColor: Color {
        if isUnknownState {
            return Color.yellow
        }
        return isAwakeActive ? Color(red: 1.0, green: 0.65, blue: 0.16) : Color.secondary.opacity(0.5)
    }

    private var powerBadge: some View {
        HStack(spacing: 3) {
            Image(systemName: batterySymbolName)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(powerManager.status.isOnACPower ? Color.green : Color.orange)

            Text(powerBadgeText)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(.primary.opacity(0.08), in: .capsule)
    }

    private var batterySymbolName: String {
        if powerManager.status.isOnACPower {
            return "bolt.fill"
        }
        guard let pct = powerManager.status.batteryPercent else {
            return "battery.50percent"
        }
        switch pct {
        case 88...: return "battery.100percent"
        case 63..<88: return "battery.75percent"
        case 38..<63: return "battery.50percent"
        case 13..<38: return "battery.25percent"
        default: return "battery.0percent"
        }
    }

    private var powerBadgeText: String {
        if let pct = powerManager.status.batteryPercent {
            return "\(pct)%"
        }
        return powerManager.status.isOnACPower ? "AC" : l10n.batteryFallback
    }

    private var mainToggleRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        isAwakeActive
                            ? LinearGradient(
                                colors: [Color(red: 1.0, green: 0.65, blue: 0.16), Color(red: 0.92, green: 0.44, blue: 0.12)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                            : LinearGradient(
                                colors: [Color.primary.opacity(0.11), Color.primary.opacity(0.06)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                    )
                    .frame(width: 40, height: 40)

                Image(systemName: isAwakeActive ? "laptopcomputer" : "moon.zzz.fill")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(isAwakeActive ? Color.white : Color.secondary)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(primaryTitleText)
                    .font(.system(size: 13.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(subtitleText)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)

            TogglePillButton(
                isOn: isAwakeActive,
                isLoading: powerManager.isUpdating,
                accessibilityLabel: isAwakeActive ? l10n.toggleOnAccess : l10n.toggleOffAccess
            ) {
                powerManager.toggle()
            }
        }
    }

    private var primaryTitleText: String {
        if isUnknownState {
            return l10n.titleUnknown
        }
        return isAwakeActive ? l10n.titleAwake : l10n.titleNormal
    }

    private var subtitleText: String {
        if powerManager.isUpdating {
            return l10n.subUpdating
        }
        if isUnknownState {
            return l10n.subUnknown
        }
        return isAwakeActive ? l10n.subAwake : l10n.subNormal
    }

    @ViewBuilder
    private var footerRow: some View {
        if let err = powerManager.lastError {
            HStack(spacing: 5) {
                Button {
                    showFullError.toggle()
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9.5))
                        Text(err)
                            .font(.system(size: 10, weight: .medium))
                            .lineLimit(1)
                    }
                    .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
                .popover(isPresented: $showFullError, arrowEdge: .bottom) {
                    Text(err)
                        .font(.system(size: 11))
                        .padding(10)
                        .frame(maxWidth: 260, alignment: .leading)
                }

                Spacer(minLength: 4)

                Button {
                    powerManager.lastError = nil
                    showFullError = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(l10n.dismissErrorAccess)
            }
        } else {
            HStack(spacing: 6) {
                if isAwakeActive && !powerManager.status.isOnACPower {
                    HStack(spacing: 4) {
                        Image(systemName: "flame.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.orange)
                        Text(l10n.batteryWarning)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else if powerManager.status.passwordlessEnabled {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 9.5))
                            .foregroundStyle(.green)
                        Text(l10n.passwordlessActive)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Button {
                        powerManager.configurePasswordlessSudo(enable: true)
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "key.fill")
                                .font(.system(size: 9.5))
                            Text(l10n.enablePasswordlessShort)
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }

                Spacer(minLength: 4)

                Text(isPinned ? "Float" : "Desktop")
                    .font(.system(size: 9.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

private struct HeaderIconButton: View {
    let systemName: String
    let isActive: Bool
    let accessibilityLabel: String
    let helpText: String
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(isActive ? Color.orange : Color.secondary)
                .frame(width: 24, height: 24)
                .background(
                    Circle()
                        .fill(.primary.opacity(isHovering || isActive ? 0.12 : 0.0))
                )
        }
        .buttonStyle(.plain)
        .help(helpText)
        .accessibilityLabel(accessibilityLabel)
        .onHover { isHovering = $0 }
    }
}

private struct TogglePillButton: View {
    let isOn: Bool
    let isLoading: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule()
                    .fill(
                        isOn
                            ? LinearGradient(
                                colors: [Color(red: 1.0, green: 0.65, blue: 0.16), Color(red: 0.94, green: 0.45, blue: 0.12)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                            : LinearGradient(
                                colors: [Color.primary.opacity(0.18), Color.primary.opacity(0.14)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                    )
                    .frame(width: 50, height: 28)

                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                    .overlay {
                        if isLoading {
                            ProgressView()
                                .controlSize(.mini)
                                .scaleEffect(0.7)
                        }
                    }
                    .padding(3)
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct QuickSettingsPopover: View {
    @Bindable var powerManager: PowerManager
    let onHideWidget: () -> Void

    private var l10n: L10n {
        L10n(language: powerManager.language)
    }

    private var appVersionLabel: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "v\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(l10n.settingsTitle)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                Spacer()
                Text(appVersionLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.tertiary)
            }

            Text("\(l10n.commandPrefix): sudo pmset -a disablesleep \(powerManager.status.isAwakeActive ? "1" : "0")")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            Divider()

            Toggle(isOn: Binding(
                get: { powerManager.status.launchAtLoginEnabled },
                set: { powerManager.setLaunchAtLogin($0) }
            )) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.launchAtLoginTitle)
                        .font(.system(size: 11.5, weight: .medium))
                    Text(l10n.launchAtLoginHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            Toggle(isOn: $powerManager.autoRestoreOnLowBattery) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(l10n.autoRestoreTitle)
                        .font(.system(size: 11.5, weight: .medium))
                    Text(l10n.autoRestoreHint)
                        .font(.system(size: 9.5))
                        .foregroundStyle(.secondary)
                }
            }
            .toggleStyle(.switch)
            .controlSize(.small)

            HStack {
                Text(l10n.languageLabel)
                    .font(.system(size: 11.5, weight: .medium))
                Spacer()
                Picker("", selection: $powerManager.language) {
                    ForEach(AppLanguage.allCases, id: \.self) { lang in
                        Text(lang.pickerLabel).tag(lang)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
                .controlSize(.small)
                .frame(width: 132)
            }

            Divider()

            if powerManager.status.passwordlessEnabled {
                Button(role: .destructive) {
                    powerManager.configurePasswordlessSudo(enable: false)
                } label: {
                    Label(l10n.removePasswordless, systemImage: "key.slash")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .disabled(powerManager.isUpdating)
            } else {
                Button {
                    powerManager.configurePasswordlessSudo(enable: true)
                } label: {
                    Label(l10n.installPasswordless, systemImage: "key.fill")
                        .font(.system(size: 11.5))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
                .disabled(powerManager.isUpdating)
            }

            Button {
                onHideWidget()
            } label: {
                Label(l10n.hideWidget, systemImage: "eye.slash")
                    .font(.system(size: 11.5))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(width: 262)
    }
}
