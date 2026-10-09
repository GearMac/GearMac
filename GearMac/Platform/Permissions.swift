// 文件职责：集中查询与申请系统权限（辅助功能、日历、相机、麦克风）并打开对应系统设置页。
// 分层：Service；只读系统授权状态，不依赖 SwiftUI。
import AVFoundation
import AppKit
import EventKit
// `@preconcurrency` 下调 AX 相关诊断：选项键是常量 C 全局变量。
@preconcurrency import ApplicationServices

/// 系统权限的统一入口。
enum Permissions {
    /// 当前进程是否已获得辅助功能（AX）信任。
    static func isAccessibilityTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    /// 返回当前信任状态，并在需要时弹窗引导用户授权。
    @discardableResult
    static func ensureAccessibility() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    /// 打开系统设置的“隐私与安全性 → 辅助功能”页面。
    @MainActor
    static func openAccessibilitySettings() {
        guard
            let url = URL(
                string:
                    "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 返回日历读取权限的当前状态。
    static func calendarAccess() -> CalendarAccess {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: return .granted
        case .notDetermined: return .notDetermined
        // 仅写入在这里等同于什么都没有：GearMac 只会读取。
        default: return .denied
        }
    }

    /// event store 在此构造又丢弃：授权是进程级的，无需传递任何东西。
    nonisolated static func requestCalendarAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    /// 返回相机权限的当前状态。
    static func cameraAccess() -> CameraAccess {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return .granted
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// 唯一一次相机弹窗，由发起请求的手势触发。
    nonisolated static func requestCameraAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .video)
    }

    /// 返回麦克风权限的当前状态。
    static func microphoneAccess() -> AVAuthorizationStatus {
        AVCaptureDevice.authorizationStatus(for: .audio)
    }

    /// 申请麦克风权限。
    nonisolated static func requestMicrophoneAccess() async -> Bool {
        await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// 打开系统设置的“隐私与安全性 → 麦克风”页面。
    @MainActor
    static func openMicrophoneSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        else { return }
        NSWorkspace.shared.open(url)
    }

    /// 打开系统设置的“隐私与安全性 → 日历”页面。
    @MainActor
    static func openCalendarSettings() {
        guard
            let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
        else { return }
        NSWorkspace.shared.open(url)
    }
}
