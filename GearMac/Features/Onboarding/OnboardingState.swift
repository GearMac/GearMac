// 文件职责：用文件而非 UserDefaults 记录“是否已向导过”这一状态。
// 分层：Model；用文件标记避免 cfprefsd 复活已删除的默认值。
import Foundation

/// 首次运行标记用文件而非默认值：cfprefsd 会把已删除的默认值复活。
enum OnboardingState {
    private static let markerURL = AppPaths.applicationSupport()
        .appendingPathComponent("onboarded")

    static var hasOnboarded: Bool {
        FileManager.default.fileExists(atPath: markerURL.path)
    }

    /// 在展示时写入，因此即使中途退出，引导也只会出现一次。
    static func markShown() {
        try? Data().write(to: markerURL)
    }
}
