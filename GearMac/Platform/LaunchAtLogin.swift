// 文件职责：封装登录时自启动开关的读取与设置（SMAppService）。
// 分层：Service；不依赖 AppKit/SwiftUI。
import ServiceManagement

/// 登录项（开机自启动）状态与开关。
enum LaunchAtLogin {
    /// 当前是否已启用登录时自启动。
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// 启用或关闭登录时自启动；失败时仅记录日志。
    static func set(_ enabled: Bool) {
        do {
            if enabled {
                if SMAppService.mainApp.status != .enabled { try SMAppService.mainApp.register() }
            } else {
                if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() }
            }
        } catch {
            NSLog("GearMac: launch-at-login change failed: \(error.localizedDescription)")
        }
    }
}
