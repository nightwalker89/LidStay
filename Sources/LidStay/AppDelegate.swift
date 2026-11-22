import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let selfTestMode: Bool
    let powerManager = PowerManager()
    private(set) var widgetPanel: FloatingWidgetPanel?
    private(set) var statusItem: NSStatusItem?
    private var menuSyncTask: Task<Void, Never>?
    private var selfTestTask: Task<Void, Never>?

    private var toggleMenuItem: NSMenuItem?
    private var statusHeaderMenuItem: NSMenuItem?
    private var errorMenuItem: NSMenuItem?
    private var showWidgetMenuItem: NSMenuItem?
    private var pinTopMenuItem: NSMenuItem?
    private var passwordlessMenuItem: NSMenuItem?
    private var loginItemMenuItem: NSMenuItem?
    private var restoreAndQuitMenuItem: NSMenuItem?

    init(selfTestMode: Bool = false) {
        self.selfTestMode = selfTestMode
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let savedDefaults = selfTestMode ? SelfTest.captureUserDefaults() : nil

        setupWidgetPanel()
        setupStatusBar()
        syncMenuBarState()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleActivateExisting),
            name: Notification.Name("com.nightwalker89.LidStay.activateExisting"),
            object: nil
        )

        menuSyncTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(1.5))
                guard !Task.isCancelled else { break }
                self?.syncMenuBarState()
            }
        }

        if selfTestMode {
            selfTestTask = Task { [weak self] in
                guard let self else { return }
                await SelfTest.run(delegate: self, savedDefaults: savedDefaults)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        selfTestTask?.cancel()
        menuSyncTask?.cancel()
        DistributedNotificationCenter.default().removeObserver(self)
    }

    @objc private func handleActivateExisting() {
        setWidgetVisible(true)
    }

    private func setupWidgetPanel() {
        let panel = FloatingWidgetPanel(
            contentRect: NSRect(x: 0, y: 0, width: 324, height: 166),
            initialPinned: powerManager.isPinnedOnTop
        )

        let rootView = WidgetView(
            powerManager: powerManager,
            onTogglePin: { [weak self] in
                self?.handleTogglePin()
            },
            onHideWidget: { [weak self] in
                self?.setWidgetVisible(false)
            }
        )

        let hosting = NSHostingView(rootView: rootView)
        hosting.frame = NSRect(x: 0, y: 0, width: 324, height: 166)
        panel.contentView = hosting

        let shouldShow = UserDefaults.standard.object(forKey: "lidstay.widgetVisible") as? Bool ?? true
        if shouldShow {
            panel.orderFrontRegardless()
        }
        self.widgetPanel = panel
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false

        let header = NSMenuItem(title: "Trạng thái: Ngủ bình thường", action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        statusHeaderMenuItem = header

        let errorItem = NSMenuItem(title: "", action: #selector(handleDismissError), keyEquivalent: "")
        errorItem.target = self
        errorItem.isHidden = true
        menu.addItem(errorItem)
        errorMenuItem = errorItem

        let toggleItem = NSMenuItem(title: "Bật gập nắp vẫn chạy", action: #selector(handleToggleSleep), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: "Hiện Widget trên Desktop", action: #selector(handleToggleWidgetVisibility), keyEquivalent: "w")
        showItem.target = self
        menu.addItem(showItem)
        showWidgetMenuItem = showItem

        let pinItem = NSMenuItem(title: "Ghim nổi trên cửa sổ", action: #selector(handleTogglePin), keyEquivalent: "p")
        pinItem.target = self
        menu.addItem(pinItem)
        pinTopMenuItem = pinItem

        menu.addItem(.separator())

        let passItem = NSMenuItem(title: "Cài 1-click không mật khẩu", action: #selector(handleTogglePasswordless), keyEquivalent: "")
        passItem.target = self
        menu.addItem(passItem)
        passwordlessMenuItem = passItem

        let loginItem = NSMenuItem(title: "Mở cùng macOS", action: #selector(handleToggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        loginItemMenuItem = loginItem

        menu.addItem(.separator())

        let restoreQuit = NSMenuItem(title: "Tắt chặn sleep & Thoát", action: #selector(handleRestoreAndQuit), keyEquivalent: "")
        restoreQuit.target = self
        menu.addItem(restoreQuit)
        restoreAndQuitMenuItem = restoreQuit

        let quitItem = NSMenuItem(title: "Thoát (Giữ nguyên trạng thái)", action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        menu.addItem(.separator())

        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        let versionItem = NSMenuItem(title: "LidStay v\(short) (\(build))", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        item.menu = menu
        self.statusItem = item
    }

    func syncMenuBarState() {
        let state = powerManager.status.sleepState
        let active = (state == .awakeOnClose)
        let busy = powerManager.isUpdating

        let symbolName = active ? "laptopcomputer" : "moon.zzz"
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LidStay")
            image?.isTemplate = !active
            button.image = image
            button.contentTintColor = active ? .systemOrange : nil
        }

        switch state {
        case .awakeOnClose:
            statusHeaderMenuItem?.title = "Trạng thái: Đang chặn sleep (disablesleep = 1)"
            toggleMenuItem?.title = "Tắt chặn sleep (Về mặc định)"
        case .normalSleep:
            statusHeaderMenuItem?.title = "Trạng thái: Ngủ bình thường (disablesleep = 0)"
            toggleMenuItem?.title = "Bật gập nắp vẫn chạy"
        case .unknown:
            statusHeaderMenuItem?.title = "Trạng thái: Không rõ (IOPMrootDomain)"
            toggleMenuItem?.title = "Bật gập nắp vẫn chạy"
        }

        if let err = powerManager.lastError, !err.isEmpty {
            errorMenuItem?.title = "Lỗi: \(err) (Bấm để xoá)"
            errorMenuItem?.isHidden = false
        } else {
            errorMenuItem?.isHidden = true
        }

        toggleMenuItem?.isEnabled = !busy
        passwordlessMenuItem?.isEnabled = !busy
        restoreAndQuitMenuItem?.isEnabled = !busy

        let isVisible = widgetPanel?.isVisible ?? false
        showWidgetMenuItem?.state = isVisible ? .on : .off
        pinTopMenuItem?.state = powerManager.isPinnedOnTop ? .on : .off

        passwordlessMenuItem?.title = powerManager.status.passwordlessEnabled
            ? "Gỡ quyền 1-click không mật khẩu"
            : "Cài 1-click không mật khẩu"

        loginItemMenuItem?.title = "Khởi động cùng macOS"
        loginItemMenuItem?.state = powerManager.status.launchAtLoginEnabled ? .on : .off
    }

    func setWidgetVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: "lidstay.widgetVisible")
        if visible {
            widgetPanel?.clampToVisibleScreen()
            widgetPanel?.orderFrontRegardless()
        } else {
            widgetPanel?.orderOut(nil)
        }
        syncMenuBarState()
    }

    @objc private func handleDismissError() {
        powerManager.lastError = nil
        syncMenuBarState()
    }

    @objc private func handleToggleSleep() {
        powerManager.toggle()
        syncMenuBarState()
    }

    @objc private func handleToggleWidgetVisibility() {
        let currentlyVisible = widgetPanel?.isVisible ?? false
        setWidgetVisible(!currentlyVisible)
    }

    @objc private func handleTogglePin() {
        powerManager.isPinnedOnTop.toggle()
        widgetPanel?.isPinnedOnTop = powerManager.isPinnedOnTop
        syncMenuBarState()
    }

    @objc private func handleTogglePasswordless() {
        powerManager.configurePasswordlessSudo(enable: !powerManager.status.passwordlessEnabled)
    }

    @objc private func handleToggleLaunchAtLogin() {
        powerManager.setLaunchAtLogin(!powerManager.status.launchAtLoginEnabled)
        syncMenuBarState()
    }

    @objc private func handleRestoreAndQuit() {
        guard !powerManager.isUpdating else { return }
        if powerManager.status.sleepState != .normalSleep {
            powerManager.setSleepDisabled(false, allowInteractivePrompt: true) { [weak self] success in
                if success {
                    NSApp.terminate(nil)
                } else {
                    self?.syncMenuBarState()
                }
            }
        } else {
            NSApp.terminate(nil)
        }
    }

    @objc private func handleQuit() {
        NSApp.terminate(nil)
    }
}
