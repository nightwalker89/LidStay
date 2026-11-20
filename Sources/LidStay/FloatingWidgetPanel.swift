import AppKit
import CoreGraphics

final class FloatingWidgetPanel: NSPanel {
    private static let frameDefaultsKey = "lidstay.widgetOrigin"

    var isPinnedOnTop: Bool = false {
        didSet {
            applyWindowBehavior()
        }
    }

    init(contentRect: NSRect, initialPinned: Bool) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        self.isPinnedOnTop = initialPinned
        self.becomesKeyOnlyIfNeeded = true
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = false
        self.isMovableByWindowBackground = true
        self.hidesOnDeactivate = false
        self.animationBehavior = .utilityWindow

        applyWindowBehavior()
        restorePositionOrDefault(size: contentRect.size)

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowDidMoveNotification),
            name: NSWindow.didMoveNotification,
            object: self
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screensDidChangeNotification),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func applyWindowBehavior() {
        if isPinnedOnTop {
            self.level = .floating
            self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        } else {
            let desktopIconLevel = Int(CGWindowLevelForKey(.desktopIconWindow))
            self.level = NSWindow.Level(rawValue: desktopIconLevel + 1)
            self.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        }
    }

    func clampToVisibleScreen() {
        let screens = NSScreen.screens
        guard !screens.isEmpty else { return }

        let currentFrame = frame
        let targetScreen = screens.max(by: { a, b in
            let ia = a.visibleFrame.intersection(currentFrame)
            let ib = b.visibleFrame.intersection(currentFrame)
            return (ia.width * ia.height) < (ib.width * ib.height)
        }) ?? NSScreen.main ?? screens[0]

        let visible = targetScreen.visibleFrame
        let clampedX = min(max(currentFrame.origin.x, visible.minX), max(visible.minX, visible.maxX - currentFrame.width))
        let clampedY = min(max(currentFrame.origin.y, visible.minY), max(visible.minY, visible.maxY - currentFrame.height))
        let clampedOrigin = NSPoint(x: clampedX, y: clampedY)
        if clampedOrigin != currentFrame.origin {
            setFrameOrigin(clampedOrigin)
        }
    }

    private func restorePositionOrDefault(size: NSSize) {
        if let saved = UserDefaults.standard.string(forKey: Self.frameDefaultsKey) {
            let point = NSPointFromString(saved)
            let candidate = NSRect(origin: point, size: size)
            if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(candidate) }) {
                setFrameOrigin(point)
                clampToVisibleScreen()
                return
            }
        }

        if let screen = NSScreen.main ?? NSScreen.screens.first {
            let visible = screen.visibleFrame
            let margin: CGFloat = 20
            let origin = NSPoint(
                x: visible.maxX - size.width - margin,
                y: visible.maxY - size.height - margin
            )
            setFrameOrigin(origin)
        }
    }

    @objc private func windowDidMoveNotification(_ notification: Notification) {
        let originString = NSStringFromPoint(frame.origin)
        UserDefaults.standard.set(originString, forKey: Self.frameDefaultsKey)
    }

    @objc private func screensDidChangeNotification(_ notification: Notification) {
        clampToVisibleScreen()
    }
}
