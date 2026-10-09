// 文件职责：SystemActionRunner 的麦克风静音扩展，通过 CoreAudio 读写默认输入设备的静音属性。
// 分层：Service；直接调用 CoreAudio，所有失败都抛 SystemActionFailure。
import CoreAudio
import Foundation

/// 麦克风静音相关实现；CoreAudio 属性写入是异步生效的，因此需要轮询确认。
extension SystemActionRunner {
    /// 切换默认输入设备的软件静音状态，返回切换后的状态。
    nonisolated static func toggleMicrophoneMute() async throws -> Bool {
        var deviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let deviceStatus = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &deviceAddress, 0, nil, &size, &device)
        guard deviceStatus == noErr, device != kAudioObjectUnknown else {
            throw SystemActionFailure(.failNoInputDevice)
        }

        var address = microphoneMuteAddress
        guard AudioObjectHasProperty(device, &address) else {
            throw SystemActionFailure(.failMicNoSoftwareMute)
        }
        var settable = DarwinBoolean(false)
        let controlStatus = AudioObjectIsPropertySettable(device, &address, &settable)
        guard controlStatus == noErr, settable.boolValue else {
            throw SystemActionFailure(.failMicControlledExternally)
        }

        let muted = try !microphoneMuted(on: device)
        var value: UInt32 = muted ? 1 : 0
        try Task.checkCancellation()
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            throw SystemActionFailure(.failMicMuteChange, argument: String(status))
        }

        // CoreAudio 的属性写入异步生效，因此这里要轮询等待设备确认。
        for _ in 0..<10 {
            if try microphoneMuted(on: device) == muted { return muted }
            try await Task.sleep(for: .milliseconds(50))
        }
        guard try microphoneMuted(on: device) == muted else {
            throw SystemActionFailure(.failMicNoConfirm)
        }
        return muted
    }

    /// 输入范围的静音属性地址。
    nonisolated private static var microphoneMuteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeInput,
            mElement: kAudioObjectPropertyElementMain)
    }

    /// 读取指定设备的当前静音状态。
    nonisolated private static func microphoneMuted(on device: AudioDeviceID) throws -> Bool {
        var address = microphoneMuteAddress
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        let status = AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value)
        guard status == noErr else {
            throw SystemActionFailure(.failMicRead, argument: String(status))
        }
        return value != 0
    }
}
