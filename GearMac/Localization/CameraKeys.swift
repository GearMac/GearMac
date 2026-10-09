// 文件职责：摄像头功能的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 摄像头面板、预览占位与提示文案的键。
enum CameraKey: String, LocalizableKey {
    case mirror = "camera.action.mirror"
    case switchCamera = "camera.action.switchCamera"
    case close = "camera.action.close"
    case takePhoto = "camera.action.takePhoto"
    case join = "camera.action.join"
    case cancel = "camera.action.cancel"
    case noAccess = "camera.stage.noAccess"
    case noCamera = "camera.stage.noCamera"
    case photoFailed = "camera.hud.photoFailed"
    case photoCopied = "camera.hud.photoCopied"

    static let table: [String: L10nEntry] = [
        CameraKey.mirror.rawValue: L10nEntry("Mirror", "镜像"),
        CameraKey.switchCamera.rawValue: L10nEntry("Switch Camera", "切换摄像头"),
        CameraKey.close.rawValue: L10nEntry("Close", "关闭"),
        CameraKey.takePhoto.rawValue: L10nEntry("Take Photo", "拍照"),
        CameraKey.join.rawValue: L10nEntry("Join", "加入"),
        CameraKey.cancel.rawValue: L10nEntry("Cancel", "取消"),
        CameraKey.noAccess.rawValue: L10nEntry(
            "GearMac has no access to the camera.", "GearMac 没有摄像头访问权限。"),
        CameraKey.noCamera.rawValue: L10nEntry("No camera on this Mac.", "本机没有摄像头。"),
        CameraKey.photoFailed.rawValue: L10nEntry("Couldn't take the photo", "无法拍照"),
        CameraKey.photoCopied.rawValue: L10nEntry("Photo copied", "已复制照片"),
    ]
}
