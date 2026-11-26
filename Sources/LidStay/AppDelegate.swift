import AppKit
import ServiceManagement
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    private(set) var languageMenuItem: NSMenuItem?
    private var languageOptionItems: [AppLanguage: NSMenuItem] = [:]
    private var restoreAndQuitMenuItem: NSMenuItem?
    private var quitMenuItem: NSMenuItem?

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
        let widgetSize = NSSize(width: WidgetLayout.width, height: WidgetLayout.height)
        let panel = FloatingWidgetPanel(
            contentRect: NSRect(origin: .zero, size: widgetSize),
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
        hosting.frame = NSRect(origin: .zero, size: widgetSize)
        hosting.wantsLayer = true
        hosting.layer?.backgroundColor = NSColor.clear.cgColor
        hosting.layer?.cornerRadius = WidgetLayout.cornerRadius
        hosting.layer?.cornerCurve = .continuous
        hosting.layer?.masksToBounds = true
        panel.contentView = hosting
        panel.invalidateShadow()

        let shouldShow = UserDefaults.standard.object(forKey: "lidstay.widgetVisible") as? Bool ?? true
        if shouldShow {
            panel.orderFrontRegardless()
            Task { @MainActor in
                panel.invalidateShadow()
            }
        }
        self.widgetPanel = panel
    }

    private func setupStatusBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let l10n = L10n(language: powerManager.language)

        let header = NSMenuItem(title: l10n.menuStatusNormal, action: nil, keyEquivalent: "")
        header.isEnabled = false
        menu.addItem(header)
        statusHeaderMenuItem = header

        let errorItem = NSMenuItem(title: "", action: #selector(handleDismissError), keyEquivalent: "")
        errorItem.target = self
        errorItem.isHidden = true
        menu.addItem(errorItem)
        errorMenuItem = errorItem

        let toggleItem = NSMenuItem(title: l10n.menuToggleEnable, action: #selector(handleToggleSleep), keyEquivalent: "t")
        toggleItem.target = self
        menu.addItem(toggleItem)
        toggleMenuItem = toggleItem

        menu.addItem(.separator())

        let showItem = NSMenuItem(title: l10n.menuShowWidget, action: #selector(handleToggleWidgetVisibility), keyEquivalent: "w")
        showItem.target = self
        menu.addItem(showItem)
        showWidgetMenuItem = showItem

        let pinItem = NSMenuItem(title: l10n.menuPinTop, action: #selector(handleTogglePin), keyEquivalent: "p")
        pinItem.target = self
        menu.addItem(pinItem)
        pinTopMenuItem = pinItem

        menu.addItem(.separator())

        let passItem = NSMenuItem(title: l10n.installPasswordless, action: #selector(handleTogglePasswordless), keyEquivalent: "")
        passItem.target = self
        menu.addItem(passItem)
        passwordlessMenuItem = passItem

        let loginItem = NSMenuItem(title: l10n.launchAtLoginTitle, action: #selector(handleToggleLaunchAtLogin), keyEquivalent: "")
        loginItem.target = self
        menu.addItem(loginItem)
        loginItemMenuItem = loginItem

        let langItem = NSMenuItem(title: l10n.languageLabel, action: nil, keyEquivalent: "")
        let langSubmenu = NSMenu()
        langSubmenu.autoenablesItems = false
        languageOptionItems.removeAll()
        for lang in AppLanguage.allCases {
            let optItem = NSMenuItem(
                title: l10n.menuLanguageOption(lang),
                action: #selector(handleSelectLanguage(_:)),
                keyEquivalent: ""
            )
            optItem.target = self
            optItem.representedObject = lang.rawValue
            langSubmenu.addItem(optItem)
            languageOptionItems[lang] = optItem
        }
        langItem.submenu = langSubmenu
        menu.addItem(langItem)
        languageMenuItem = langItem

        menu.addItem(.separator())

        let restoreQuit = NSMenuItem(title: l10n.menuRestoreAndQuit, action: #selector(handleRestoreAndQuit), keyEquivalent: "")
        restoreQuit.target = self
        menu.addItem(restoreQuit)
        restoreAndQuitMenuItem = restoreQuit

        let quitItem = NSMenuItem(title: l10n.menuQuitKeepState, action: #selector(handleQuit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)
        quitMenuItem = quitItem

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

    func menuWillOpen(_ menu: NSMenu) {
        syncMenuBarState()
    }

    func syncMenuBarState() {
        let state = powerManager.status.sleepState
        let active = (state == .awakeOnClose)
        let busy = powerManager.isUpdating
        let l10n = L10n(language: powerManager.language)

        let symbolName = active ? "laptopcomputer" : "moon.zzz"
        if let button = statusItem?.button {
            let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "LidStay")
            image?.isTemplate = true
            button.image = image
            button.contentTintColor = nil
        }

        switch state {
        case .awakeOnClose:
            statusHeaderMenuItem?.title = l10n.menuStatusAwake
            toggleMenuItem?.title = l10n.menuToggleDisable
        case .normalSleep:
            statusHeaderMenuItem?.title = l10n.menuStatusNormal
            toggleMenuItem?.title = l10n.menuToggleEnable
        case .unknown:
            statusHeaderMenuItem?.title = l10n.menuStatusUnknown
            toggleMenuItem?.title = l10n.menuToggleEnable
        }

        if let err = powerManager.lastError, !err.isEmpty {
            errorMenuItem?.title = l10n.menuError(err)
            errorMenuItem?.isHidden = false
        } else {
            errorMenuItem?.isHidden = true
        }

        toggleMenuItem?.isEnabled = !busy
        passwordlessMenuItem?.isEnabled = !busy
        restoreAndQuitMenuItem?.isEnabled = !busy

        let isVisible = widgetPanel?.isVisible ?? false
        showWidgetMenuItem?.title = l10n.menuShowWidget
        showWidgetMenuItem?.state = isVisible ? .on : .off
        pinTopMenuItem?.title = l10n.menuPinTop
        pinTopMenuItem?.state = powerManager.isPinnedOnTop ? .on : .off

        passwordlessMenuItem?.title = powerManager.status.passwordlessEnabled
            ? l10n.removePasswordless
            : l10n.installPasswordless

        loginItemMenuItem?.title = l10n.launchAtLoginTitle
        loginItemMenuItem?.state = powerManager.status.launchAtLoginEnabled ? .on : .off

        languageMenuItem?.title = l10n.languageLabel
        for lang in AppLanguage.allCases {
            guard let optItem = languageOptionItems[lang] else { continue }
            optItem.title = l10n.menuLanguageOption(lang)
            optItem.state = (powerManager.language == lang) ? .on : .off
        }

        restoreAndQuitMenuItem?.title = l10n.menuRestoreAndQuit
        quitMenuItem?.title = l10n.menuQuitKeepState
    }

    func setWidgetVisible(_ visible: Bool) {
        UserDefaults.standard.set(visible, forKey: "lidstay.widgetVisible")
        if visible {
            widgetPanel?.clampToVisibleScreen()
            widgetPanel?.orderFrontRegardless()
            widgetPanel?.invalidateShadow()
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

    @objc private func handleSelectLanguage(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let lang = AppLanguage(rawValue: raw) else { return }
        selectLanguage(lang)
    }

    func selectLanguage(_ language: AppLanguage) {
        powerManager.language = language
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
