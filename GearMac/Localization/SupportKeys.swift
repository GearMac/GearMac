// 文件职责：支持窗口的本地化键与中英词表。
// 分层：Model（本地化）；自包含，不引用其他功能的键。
import Foundation

/// 支持窗口（标题、文案与提醒开关）的文案键。
enum SupportKey: String, LocalizableKey {
    case windowTitle = "support.windowTitle"
    case builtWithLove = "support.builtWithLove"
    case secureCheckout = "support.secureCheckout"
    case remindMe = "support.remindMe"
    case remindHelp = "support.remindHelp"

    static let table: [String: L10nEntry] = [
        SupportKey.windowTitle.rawValue: L10nEntry("Support %@", "支持 %@"),
        SupportKey.builtWithLove.rawValue: L10nEntry("Built with love.", "用爱打造。"),
        SupportKey.secureCheckout.rawValue: L10nEntry(
            "Secure checkout on Polar.", "在 Polar 上安全结账。"),
        SupportKey.remindMe.rawValue: L10nEntry("Remind me occasionally", "偶尔提醒我"),
        SupportKey.remindHelp.rawValue: L10nEntry(
            "About once a month. Turn this off and %@ won't ask again.",
            "大约每月一次。关闭后 %@ 将不再询问。"),
    ]
}
