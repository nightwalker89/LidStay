import AppKit
import Darwin
import Foundation

private let activateExistingNotification = Notification.Name("com.nightwalker89.LidStay.activateExisting")

private func acquireSingleInstanceLock() -> Int32? {
    let supportDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/LidStay", isDirectory: true)
    try? FileManager.default.createDirectory(at: supportDir, withIntermediateDirectories: true)

    let lockPath = supportDir.appendingPathComponent("instance.lock").path
    let fd = open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
    guard fd >= 0 else { return nil }

    if flock(fd, LOCK_EX | LOCK_NB) != 0 {
        close(fd)
        return nil
    }
    return fd
}

private func hasOtherRunningInstance() -> Bool {
    guard let bundleID = Bundle.main.bundleIdentifier else { return false }
    let currentPID = ProcessInfo.processInfo.processIdentifier
    return NSRunningApplication
        .runningApplications(withBundleIdentifier: bundleID)
        .contains { $0.processIdentifier != currentPID && !$0.isTerminated }
}

guard let instanceLockFD = acquireSingleInstanceLock(), !hasOtherRunningInstance() else {
    DistributedNotificationCenter.default().postNotificationName(
        activateExistingNotification,
        object: nil,
        userInfo: nil,
        deliverImmediately: true
    )
    exit(0)
}

_ = instanceLockFD

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
