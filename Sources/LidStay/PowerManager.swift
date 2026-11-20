import Foundation
import IOKit
import IOKit.ps
import Observation

enum LidSleepState: Equatable {
    case awakeOnClose // disablesleep = 1
    case normalSleep  // disablesleep = 0
    case unknown
}

struct PowerStatus: Equatable {
    var sleepState: LidSleepState = .unknown
    var isOnACPower: Bool = true
    var batteryPercent: Int? = nil
    var hasBattery: Bool = false
    var passwordlessEnabled: Bool = false

    var isAwakeActive: Bool {
        sleepState == .awakeOnClose
    }
}

@Observable
@MainActor
final class PowerManager {
    var status = PowerStatus()
    var isUpdating = false
    var lastError: String? = nil

    var isPinnedOnTop: Bool = UserDefaults.standard.bool(forKey: "lidstay.pinnedOnTop") {
        didSet {
            UserDefaults.standard.set(isPinnedOnTop, forKey: "lidstay.pinnedOnTop")
        }
    }

    var autoRestoreOnLowBattery: Bool = UserDefaults.standard.bool(forKey: "lidstay.autoRestoreLowBattery") {
        didSet {
            UserDefaults.standard.set(autoRestoreOnLowBattery, forKey: "lidstay.autoRestoreLowBattery")
        }
    }

    var language: AppLanguage = {
        if let raw = UserDefaults.standard.string(forKey: "lidstay.language"),
           let parsed = AppLanguage(rawValue: raw) {
            return parsed
        }
        return .system
    }() {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: "lidstay.language")
        }
    }

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let sudoersPath = "/etc/sudoers.d/lidstay-pmset"
    @ObservationIgnored private var lastLowBatteryAttempt: Date? = nil

    init() {
        if UserDefaults.standard.object(forKey: "lidstay.autoRestoreLowBattery") == nil {
            autoRestoreOnLowBattery = true
        }
        refresh()
        startPolling()
    }

    deinit {
        pollTask?.cancel()
    }

    func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled else { break }
                self?.refresh()
            }
        }
    }

    func refresh() {
        let sleepState = Self.readSleepStateFromIOKit()
        let batteryInfo = Self.readPowerSourceInfo()
        let passwordless = FileManager.default.fileExists(atPath: sudoersPath)

        let next = PowerStatus(
            sleepState: sleepState,
            isOnACPower: batteryInfo.isAC,
            batteryPercent: batteryInfo.percent,
            hasBattery: batteryInfo.hasBattery,
            passwordlessEnabled: passwordless
        )
        if next != status {
            status = next
        }

        if sleepState != .awakeOnClose || batteryInfo.isAC {
            lastLowBatteryAttempt = nil
        } else if autoRestoreOnLowBattery,
                  passwordless,
                  let pct = batteryInfo.percent,
                  pct <= 15,
                  !isUpdating {
            let now = Date()
            if lastLowBatteryAttempt == nil || now.timeIntervalSince(lastLowBatteryAttempt!) >= 30 {
                lastLowBatteryAttempt = now
                setSleepDisabled(false, allowInteractivePrompt: false)
            }
        }
    }

    func toggle() {
        guard !isUpdating else { return }
        let targetDisable = (status.sleepState != .awakeOnClose)
        setSleepDisabled(targetDisable, allowInteractivePrompt: true)
    }

    func setSleepDisabled(
        _ disable: Bool,
        allowInteractivePrompt: Bool = true,
        completion: (@MainActor (Bool) -> Void)? = nil
    ) {
        guard !isUpdating else {
            completion?(false)
            return
        }
        isUpdating = true
        lastError = nil

        let valueArg = disable ? "1" : "0"
        let expectedState: LidSleepState = disable ? .awakeOnClose : .normalSleep
        let hasSudoers = FileManager.default.fileExists(atPath: sudoersPath)

        Task.detached { [weak self] in
            let result = Self.executePmset(
                value: valueArg,
                tryPasswordless: hasSudoers,
                allowInteractivePrompt: allowInteractivePrompt
            )
            let observed = Self.readSleepStateFromIOKit()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUpdating = false
                self.refresh()
                switch result {
                case .success:
                    if observed == expectedState {
                        self.lastError = nil
                        completion?(true)
                    } else {
                        self.lastError = "Không xác nhận được trạng thái pmset mới."
                        completion?(false)
                    }
                case .failure(let err):
                    if !err.isCancelled {
                        self.lastError = err.message
                    }
                    completion?(false)
                }
            }
        }
    }

    func configurePasswordlessSudo(enable: Bool) {
        guard !isUpdating else { return }
        isUpdating = true
        lastError = nil

        let user = NSUserName()
        let path = sudoersPath

        Task.detached { [weak self] in
            let result = Self.updateSudoers(enable: enable, username: user, path: path)
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.isUpdating = false
                switch result {
                case .success:
                    self.lastError = nil
                    self.refresh()
                case .failure(let err):
                    if !err.isCancelled {
                        self.lastError = err.message
                    }
                    self.refresh()
                }
            }
        }
    }

    // MARK: - Nonisolated Helpers

    private struct CommandFailure: Error {
        let message: String
        let isCancelled: Bool
    }

    nonisolated private static func readSleepStateFromIOKit() -> LidSleepState {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return .unknown }
        defer { IOObjectRelease(service) }

        guard let prop = IORegistryEntryCreateCFProperty(
            service,
            "SleepDisabled" as CFString,
            kCFAllocatorDefault,
            0
        )?.takeRetainedValue() else {
            return .unknown
        }

        if let boolVal = prop as? Bool {
            return boolVal ? .awakeOnClose : .normalSleep
        }
        if let numVal = prop as? NSNumber {
            return numVal.boolValue ? .awakeOnClose : .normalSleep
        }
        return .unknown
    }

    nonisolated private static func readPowerSourceInfo() -> (isAC: Bool, percent: Int?, hasBattery: Bool) {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let list = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef] else {
            return (true, nil, false)
        }

        var isAC = true
        var percent: Int? = nil
        var hasBattery = false

        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, ps)?.takeUnretainedValue() as? [String: Any] else {
                continue
            }
            let type = desc[kIOPSTypeKey] as? String
            if type == kIOPSInternalBatteryType {
                hasBattery = true
                if let current = desc[kIOPSCurrentCapacityKey] as? Int,
                   let max = desc[kIOPSMaxCapacityKey] as? Int,
                   max > 0 {
                    percent = Int((Double(current) / Double(max) * 100.0).rounded())
                }
                if let state = desc[kIOPSPowerSourceStateKey] as? String {
                    isAC = (state == kIOPSACPowerValue)
                }
            }
        }

        return (isAC, percent, hasBattery)
    }

    nonisolated private static func executePmset(
        value: String,
        tryPasswordless: Bool,
        allowInteractivePrompt: Bool
    ) -> Result<Void, CommandFailure> {
        guard value == "0" || value == "1" else {
            return .failure(CommandFailure(message: "Tham số pmset không hợp lệ.", isCancelled: false))
        }

        if tryPasswordless {
            let sudoAttempt = runProcess(
                executable: "/usr/bin/sudo",
                arguments: ["-n", "/usr/bin/pmset", "-a", "disablesleep", value]
            )
            if sudoAttempt.exitCode == 0 {
                return .success(())
            }
            if !allowInteractivePrompt {
                return .failure(CommandFailure(
                    message: sudoAttempt.stderr.isEmpty ? "Không có quyền sudo không mật khẩu." : sudoAttempt.stderr,
                    isCancelled: false
                ))
            }
        }

        guard allowInteractivePrompt else {
            return .failure(CommandFailure(message: "Chưa bật quyền 1-click không mật khẩu.", isCancelled: false))
        }

        let script = "do shell script \"/usr/bin/pmset -a disablesleep \(value)\" with administrator privileges"
        let adminAttempt = runProcess(executable: "/usr/bin/osascript", arguments: ["-e", script])
        if adminAttempt.exitCode == 0 {
            return .success(())
        }

        let cancelled = adminAttempt.stderr.localizedCaseInsensitiveContains("User canceled")
            || adminAttempt.stderr.contains("-128")
        let msg = cancelled ? "Đã huỷ xác thực." : (adminAttempt.stderr.isEmpty ? "Không thể chạy pmset." : adminAttempt.stderr)
        return .failure(CommandFailure(message: msg, isCancelled: cancelled))
    }

    nonisolated private static func updateSudoers(enable: Bool, username: String, path: String) -> Result<Void, CommandFailure> {
        let validUser = username.range(of: "^[a-zA-Z0-9._-]+$", options: .regularExpression) != nil
        guard validUser else {
            return .failure(CommandFailure(message: "Tên người dùng không hợp lệ.", isCancelled: false))
        }

        let shellCommand: String
        if enable {
            let rule = "\(username) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1"
            let escapedRule = rule.replacingOccurrences(of: "'", with: "'\\''")
            shellCommand = "TMP=$(/usr/bin/mktemp /tmp/lidstay-sudoers.XXXXXX) && printf '%s\\n' '\(escapedRule)' > \"$TMP\" && /usr/sbin/visudo -cf \"$TMP\" && /usr/bin/install -m 0440 -o root -g wheel \"$TMP\" '\(path)' && /bin/rm -f \"$TMP\" || (/bin/rm -f \"$TMP\" && exit 1)"
        } else {
            shellCommand = "/bin/rm -f '\(path)'"
        }

        let escapedForAppleScript = shellCommand
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        let script = "do shell script \"\(escapedForAppleScript)\" with administrator privileges"
        let attempt = runProcess(executable: "/usr/bin/osascript", arguments: ["-e", script])

        if attempt.exitCode == 0 {
            return .success(())
        }
        let cancelled = attempt.stderr.localizedCaseInsensitiveContains("User canceled")
            || attempt.stderr.contains("-128")
        let msg = cancelled ? "Đã huỷ xác thực." : (attempt.stderr.isEmpty ? "Không thể cập nhật quyền sudoers." : attempt.stderr)
        return .failure(CommandFailure(message: msg, isCancelled: cancelled))
    }

    nonisolated private static func runProcess(executable: String, arguments: [String]) -> (exitCode: Int32, stdout: String, stderr: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        do {
            try process.run()
        } catch {
            return (-1, "", error.localizedDescription)
        }

        let group = DispatchGroup()
        nonisolated(unsafe) var outData = Data()
        nonisolated(unsafe) var errData = Data()

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        group.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }

        process.waitUntilExit()
        group.wait()

        let stdout = String(data: outData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let stderr = String(data: errData, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return (process.terminationStatus, stdout, stderr)
    }
}
