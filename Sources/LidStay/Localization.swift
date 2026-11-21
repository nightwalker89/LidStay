import Foundation

enum AppLanguage: String, CaseIterable, Equatable {
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

struct L10n: Equatable {
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
}
