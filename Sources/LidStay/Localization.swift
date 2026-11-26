import Foundation

enum AppLanguage: String, CaseIterable, Equatable, Sendable {
    case system
    case en
    case vi

    var resolvedIsVietnamese: Bool {
        switch self {
        case .vi:
            return true
        case .en:
            return false
        case .system:
            return Locale.preferredLanguages.first?.hasPrefix("vi") == true
        }
    }

    var pickerLabel: String {
        switch self {
        case .system: return "Auto"
        case .en: return "EN"
        case .vi: return "VI"
        }
    }
}

struct L10n: Equatable, Sendable {
    let isVi: Bool

    init(language: AppLanguage) {
        self.isVi = language.resolvedIsVietnamese
    }

    var pinHelpOn: String { isVi ? "Đang ghim nổi trên cửa sổ" : "Pinned above windows" }
    var pinHelpOff: String { isVi ? "Đang đặt trên Desktop" : "Placed on Desktop layer" }
    var pinAccessOn: String { isVi ? "Bỏ ghim nổi trên cửa sổ" : "Unpin from top" }
    var pinAccessOff: String { isVi ? "Ghim nổi trên cửa sổ" : "Pin above windows" }
    var optionsHelp: String { isVi ? "Tuỳ chọn nhanh" : "Quick options" }
    var optionsAccess: String { isVi ? "Tuỳ chọn LidStay" : "LidStay options" }
    var batteryFallback: String { isVi ? "Pin" : "Bat" }

    var titleUnknown: String { isVi ? "Không rõ trạng thái" : "Unknown state" }
    var titleAwake: String { isVi ? "Gập nắp vẫn chạy" : "Awake on close" }
    var titleNormal: String { isVi ? "Ngủ bình thường" : "Normal sleep" }

    var subUpdating: String { isVi ? "Đang cập nhật..." : "Updating..." }
    var subUnknown: String { isVi ? "Chưa đọc được trạng thái" : "Unable to read state" }
    var subAwake: String { isVi ? "Đang chặn sleep (pmset)" : "Sleep disabled (pmset)" }
    var subNormal: String { isVi ? "Mặc định khi gập nắp" : "Default lid-close sleep" }

    var dismissErrorAccess: String { isVi ? "Đóng thông báo lỗi" : "Dismiss error" }
    var batteryWarning: String { isVi ? "Đang dùng pin - tránh bọc kín" : "On battery - keep ventilated" }
    var passwordlessActive: String { isVi ? "1-click không mật khẩu" : "1-click passwordless" }
    var enablePasswordlessShort: String { isVi ? "Bật 1-click không mật khẩu" : "Enable 1-click passwordless" }

    var toggleOnAccess: String { isVi ? "Tắt chế độ gập nắp vẫn chạy" : "Disable stay-awake mode" }
    var toggleOffAccess: String { isVi ? "Bật chế độ gập nắp vẫn chạy" : "Enable stay-awake mode" }

    var settingsTitle: String { isVi ? "Tuỳ chọn LidStay" : "LidStay Options" }
    var commandPrefix: String { isVi ? "Lệnh" : "Command" }
    var autoRestoreTitle: String { isVi ? "Tự tắt khi pin <= 15%" : "Auto-restore at <= 15% battery" }
    var autoRestoreHint: String { isVi ? "Chỉ chạy tự động khi đã bật 1-click" : "Requires 1-click mode enabled" }
    var launchAtLoginTitle: String { isVi ? "Khởi động cùng macOS" : "Launch at login" }
    var launchAtLoginHint: String { isVi ? "Tự mở widget khi đăng nhập" : "Auto-start when you log in" }
    var languageLabel: String { isVi ? "Ngôn ngữ" : "Language" }
    var removePasswordless: String { isVi ? "Gỡ quyền 1-click không mật khẩu" : "Remove 1-click permission" }
    var installPasswordless: String { isVi ? "Cài 1-click không mật khẩu" : "Enable 1-click permission" }
    var hideWidget: String { isVi ? "Ẩn widget khỏi Desktop" : "Hide desktop widget" }

    // MARK: - Menu Bar
    var menuStatusAwake: String {
        isVi ? "Trạng thái: Đang chặn sleep (disablesleep = 1)" : "Status: Sleep disabled (disablesleep = 1)"
    }
    var menuStatusNormal: String {
        isVi ? "Trạng thái: Ngủ bình thường (disablesleep = 0)" : "Status: Normal sleep (disablesleep = 0)"
    }
    var menuStatusUnknown: String {
        isVi ? "Trạng thái: Không rõ (IOPMrootDomain)" : "Status: Unknown (IOPMrootDomain)"
    }
    func menuError(_ message: String) -> String {
        isVi ? "Lỗi: \(message) (Bấm để xoá)" : "Error: \(message) (Click to dismiss)"
    }
    var menuToggleDisable: String {
        isVi ? "Tắt chặn sleep (Về mặc định)" : "Disable stay-awake (Restore default)"
    }
    var menuToggleEnable: String {
        isVi ? "Bật gập nắp vẫn chạy" : "Enable awake on close"
    }
    var menuShowWidget: String {
        isVi ? "Hiện Widget trên Desktop" : "Show Desktop Widget"
    }
    var menuPinTop: String {
        isVi ? "Ghim nổi trên cửa sổ" : "Pin Above Windows"
    }
    func menuLanguageOption(_ lang: AppLanguage) -> String {
        switch lang {
        case .system:
            return isVi ? "Tự động (Hệ thống)" : "Auto (System)"
        case .en:
            return "English"
        case .vi:
            return "Tiếng Việt"
        }
    }
    var menuRestoreAndQuit: String {
        isVi ? "Tắt chặn sleep & Thoát" : "Restore Sleep & Quit"
    }
    var menuQuitKeepState: String {
        isVi ? "Thoát (Giữ nguyên trạng thái)" : "Quit (Keep current state)"
    }

    // MARK: - Errors
    var errVerifyPmset: String {
        isVi ? "Không xác nhận được trạng thái pmset mới." : "Could not verify updated pmset state."
    }
    var errInvalidPmsetArg: String {
        isVi ? "Tham số pmset không hợp lệ." : "Invalid pmset argument."
    }
    var errNoPasswordlessSudo: String {
        isVi ? "Không có quyền sudo không mật khẩu." : "Passwordless sudo permission is not available."
    }
    var errPasswordlessNotEnabled: String {
        isVi ? "Chưa bật quyền 1-click không mật khẩu." : "1-click passwordless mode is not enabled."
    }
    var errAuthCancelled: String {
        isVi ? "Đã huỷ xác thực." : "Authentication cancelled."
    }
    var errPmsetFailed: String {
        isVi ? "Không thể chạy pmset." : "Unable to run pmset."
    }
    var errInvalidUsername: String {
        isVi ? "Tên người dùng không hợp lệ." : "Invalid username."
    }
    var errSudoersUpdateFailed: String {
        isVi ? "Không thể cập nhật quyền sudoers." : "Unable to update sudoers permission."
    }
    func errLaunchAtLogin(_ detail: String) -> String {
        isVi ? "Khởi động cùng macOS: \(detail)" : "Launch at login: \(detail)"
    }
}
