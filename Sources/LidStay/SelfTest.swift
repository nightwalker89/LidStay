import AppKit
import CoreGraphics
import Foundation
import SwiftUI

@MainActor
enum SelfTest {
    struct SavedDefaults {
        let values: [String: Any?]
    }

    private struct SelfTestFailure: Error {
        let message: String
    }

    private static let managedDefaultKeys = [
        "lidstay.widgetVisible",
        "lidstay.pinnedOnTop",
        "lidstay.autoRestoreLowBattery",
        "lidstay.language",
        "lidstay.widgetOrigin"
    ]

    private static let requiredSymbols = [
        "laptopcomputer",
        "moon.zzz",
        "moon.zzz.fill",
        "bolt.fill",
        "battery.100percent",
        "battery.75percent",
        "battery.50percent",
        "battery.25percent",
        "battery.0percent",
        "pin",
        "pin.fill",
        "slider.horizontal.3",
        "exclamationmark.triangle.fill",
        "xmark.circle.fill",
        "flame.fill",
        "checkmark.seal.fill",
        "key.fill",
        "key.slash",
        "eye.slash"
    ]

    static var currentArch: String {
        #if arch(x86_64)
        return "x86_64"
        #elseif arch(arm64)
        return "arm64"
        #else
        return "unknown"
        #endif
    }

    static func captureUserDefaults() -> SavedDefaults {
        var snapshot: [String: Any?] = [:]
        for key in managedDefaultKeys {
            snapshot[key] = UserDefaults.standard.object(forKey: key)
        }
        return SavedDefaults(values: snapshot)
    }

    static func restoreUserDefaults(_ saved: SavedDefaults?) {
        guard let saved else { return }
        for (key, value) in saved.values {
            if let value {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        UserDefaults.standard.synchronize()
    }

    static func run(delegate: AppDelegate, savedDefaults: SavedDefaults?) async {
        defer {
            restoreUserDefaults(savedDefaults)
        }

        do {
            try await executeChecks(delegate: delegate)
            let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
            let sleepState = String(describing: delegate.powerManager.status.sleepState)
            let screens = NSScreen.screens.count
            print("[SELF-TEST] PASS arch=\(currentArch) os=\"\(osVersion)\" sleepState=\(sleepState) screens=\(screens)")
            fflush(stdout)
            restoreUserDefaults(savedDefaults)
            NSApp.terminate(nil)
        } catch let failure as SelfTestFailure {
            fputs("[SELF-TEST] FAIL: \(failure.message)\n", stderr)
            fflush(stderr)
            restoreUserDefaults(savedDefaults)
            exit(1)
        } catch {
            fputs("[SELF-TEST] FAIL: \(error.localizedDescription)\n", stderr)
            fflush(stderr)
            restoreUserDefaults(savedDefaults)
            exit(1)
        }
    }

    private static func assertCondition(_ condition: Bool, _ message: String) throws {
        if !condition {
            throw SelfTestFailure(message: message)
        }
    }

    private static func executeChecks(delegate: AppDelegate) async throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let bundleID = Bundle.main.bundleIdentifier ?? "(none)"
        let shortVersion = info["CFBundleShortVersionString"] as? String ?? "(none)"
        let buildVersion = info["CFBundleVersion"] as? String ?? "(none)"
        print("[SELF-TEST] Runtime arch=\(currentArch) bundleID=\(bundleID) version=\(shortVersion) (\(buildVersion))")
        fflush(stdout)

        if Bundle.main.bundlePath.hasSuffix(".app") {
            try assertCondition(
                bundleID == "com.nightwalker89.LidStay",
                "Unexpected bundle identifier: \(bundleID)"
            )
        }

        // 1. PowerManager & IOKit check
        let powerManager = delegate.powerManager
        powerManager.refresh()
        let status = powerManager.status
        print("[SELF-TEST] PowerStatus sleepState=\(status.sleepState) isOnAC=\(status.isOnACPower) hasBattery=\(status.hasBattery) batteryPercent=\(status.batteryPercent.map(String.init) ?? "nil") passwordless=\(status.passwordlessEnabled) launchAtLogin=\(status.launchAtLoginEnabled)")
        fflush(stdout)
        try assertCondition(powerManager.lastError == nil, "Unexpected PowerManager error: \(powerManager.lastError ?? "")")

        // 2. FloatingWidgetPanel & window level check
        guard let panel = delegate.widgetPanel else {
            throw SelfTestFailure(message: "widgetPanel was not initialized")
        }
        try assertCondition(panel.hasShadow, "Expected native window shadow to be enabled")
        try assertCondition(
            panel.frame.size == NSSize(width: WidgetLayout.width, height: WidgetLayout.height),
            "Unexpected widget panel size: \(panel.frame.size)"
        )
        panel.clampToVisibleScreen()
        let originalPinned = powerManager.isPinnedOnTop
        let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))

        panel.isPinnedOnTop = false
        try assertCondition(
            panel.level.rawValue == desktopIconLevel + 1,
            "Desktop layer level mismatch: got \(panel.level.rawValue), expected \(desktopIconLevel + 1)"
        )

        panel.isPinnedOnTop = true
        try assertCondition(
            panel.level == .floating,
            "Floating layer level mismatch: got \(panel.level.rawValue), expected \(NSWindow.Level.floating.rawValue)"
        )
        panel.isPinnedOnTop = originalPinned

        delegate.setWidgetVisible(false)
        delegate.setWidgetVisible(true)

        // 3. Status bar & menu check
        guard let statusItem = delegate.statusItem else {
            throw SelfTestFailure(message: "NSStatusItem was not initialized")
        }
        guard let menu = statusItem.menu else {
            throw SelfTestFailure(message: "NSStatusItem menu was not attached")
        }
        try assertCondition(
            menu.items.count >= 10,
            "Unexpected status menu item count: \(menu.items.count)"
        )
        delegate.syncMenuBarState()
        try assertCondition(
            statusItem.button?.image != nil,
            "Status bar button image failed to resolve"
        )
        try assertCondition(
            statusItem.button?.image?.isTemplate == true,
            "Status bar button image should be a template image to match menu bar appearance"
        )

        // 4. SF Symbols check
        for symbol in requiredSymbols {
            let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
            try assertCondition(image != nil, "Missing SF Symbol on host: \(symbol)")
        }

        // 5. Localization & menu language submenu check
        let en = L10n(language: .en)
        let vi = L10n(language: .vi)
        try assertCondition(!en.titleAwake.isEmpty && !vi.titleAwake.isEmpty, "Empty localized strings")
        try assertCondition(en.titleAwake != vi.titleAwake, "EN and VI localization strings should differ")
        try assertCondition(en.titleNormal != vi.titleNormal, "EN and VI normal sleep titles should differ")

        guard let langItem = delegate.languageMenuItem, let langSubmenu = langItem.submenu else {
            throw SelfTestFailure(message: "Language submenu missing from status bar menu")
        }
        try assertCondition(
            langSubmenu.items.count == AppLanguage.allCases.count,
            "Unexpected language submenu count: \(langSubmenu.items.count)"
        )
        let originalLang = powerManager.language
        defer { delegate.selectLanguage(originalLang) }

        delegate.selectLanguage(.en)
        try assertCondition(langItem.title == en.languageLabel, "Expected EN language menu title, got: \(langItem.title)")
        try assertCondition(
            langSubmenu.items.first(where: { ($0.representedObject as? String) == AppLanguage.en.rawValue })?.state == .on,
            "Expected EN submenu item to be checked"
        )
        try assertCondition(
            langSubmenu.items.first(where: { ($0.representedObject as? String) == AppLanguage.vi.rawValue })?.state == .off,
            "Expected VI submenu item to be unchecked when EN is active"
        )

        delegate.selectLanguage(.vi)
        try assertCondition(langItem.title == vi.languageLabel, "Expected VI language menu title, got: \(langItem.title)")
        try assertCondition(
            langSubmenu.items.first(where: { ($0.representedObject as? String) == AppLanguage.vi.rawValue })?.state == .on,
            "Expected VI submenu item to be checked"
        )
        delegate.selectLanguage(originalLang)

        // 6. SwiftUI WidgetView layout & bitmap rendering across states and locales
        try renderWidgetScenario(
            label: "en-normal-ac-static",
            language: .en,
            status: PowerStatus(sleepState: .normalSleep, isOnACPower: true, batteryPercent: 100, hasBattery: true, passwordlessEnabled: true, launchAtLoginEnabled: false),
            lastError: nil,
            useStaticBackdrop: true
        )
        try renderWidgetScenario(
            label: "en-awake-battery-visualeffect",
            language: .en,
            status: PowerStatus(sleepState: .awakeOnClose, isOnACPower: false, batteryPercent: 45, hasBattery: true, passwordlessEnabled: false, launchAtLoginEnabled: true),
            lastError: nil,
            useStaticBackdrop: false
        )
        try renderWidgetScenario(
            label: "vi-awake-error-static",
            language: .vi,
            status: PowerStatus(sleepState: .awakeOnClose, isOnACPower: false, batteryPercent: 20, hasBattery: true, passwordlessEnabled: true, launchAtLoginEnabled: false),
            lastError: "Sample error for rendering verification",
            useStaticBackdrop: true
        )
        try renderWidgetScenario(
            label: "vi-unknown-nobattery-static",
            language: .vi,
            status: PowerStatus(sleepState: .unknown, isOnACPower: true, batteryPercent: nil, hasBattery: false, passwordlessEnabled: false, launchAtLoginEnabled: false),
            lastError: nil,
            useStaticBackdrop: true
        )

        // 7. Verify RunLoop & background async timers (menuSyncTask 1.5s + pollTask 2.0s) survive
        try await Task.sleep(for: .milliseconds(2300))
        delegate.syncMenuBarState()
        try assertCondition(powerManager.lastError == nil, "PowerManager error after polling cycle: \(powerManager.lastError ?? "")")
    }

    private static func renderWidgetScenario(
        label: String,
        language: AppLanguage,
        status: PowerStatus,
        lastError: String?,
        useStaticBackdrop: Bool
    ) throws {
        let pm = PowerManager(startPollingOnInit: false)
        pm.language = language
        pm.status = status
        pm.lastError = lastError

        let view = WidgetView(
            powerManager: pm,
            onTogglePin: {},
            onHideWidget: {}
        )
        .environment(\.useStaticBackdropForRender, useStaticBackdrop)

        let hosting = NSHostingView(rootView: view)
        hosting.frame = NSRect(x: 0, y: 0, width: WidgetLayout.width, height: WidgetLayout.height)
        hosting.layoutSubtreeIfNeeded()

        guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
            throw SelfTestFailure(message: "Could not create bitmapImageRep for scenario '\(label)'")
        }
        hosting.cacheDisplay(in: hosting.bounds, to: rep)
        try assertCondition(
            rep.pixelsWide > 0 && rep.pixelsHigh > 0,
            "Rendered empty bitmap (\(rep.pixelsWide)x\(rep.pixelsHigh)) for scenario '\(label)'"
        )
    }
}

