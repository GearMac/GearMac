// 文件职责：麦克风静音切换（SystemActionRunner.toggleMicrophoneMute）的测试 harness，用假的音频设备驱动被遮蔽的 CoreAudio 调用。
// 分层：测试 harness；以模块内同名函数遮蔽真实 CoreAudio 调用，绝不触碰真实音频硬件。
import CoreAudio
import Foundation
import Synchronization

/// 测试用的 SystemActionRunner 类型声明；测试只编译麦克风扩展，因此在此本地声明该命名空间类型。
@MainActor
enum SystemActionRunner {}

/// 可配置的假音频设备状态，用于驱动被遮蔽的 CoreAudio 函数。
private struct AudioFixture: Sendable {
    var device: AudioDeviceID = 78
    var muted: UInt32 = 0
    var hasMute = true
    var settable = true
    var lookupStatus: OSStatus = noErr
    var readStatus: OSStatus = noErr
    var writeStatus: OSStatus = noErr
    var appliesWrite = true
    var delayedReads = 0
    var pendingMute: UInt32?
    var nextDefaultDevice: AudioDeviceID?
    var defaultLookups = 0
    var controlDevices: [AudioDeviceID] = []
    var writes: [UInt32] = []
    var invalidAddress = false

    /// 记录被访问的设备，并校验属性地址只指向默认输入的静音属性。
    mutating func check(_ device: AudioDeviceID, _ address: AudioObjectPropertyAddress) {
        controlDevices.append(device)
        if address.mSelector != kAudioDevicePropertyMute
            || address.mScope != kAudioDevicePropertyScopeInput
            || address.mElement != kAudioObjectPropertyElementMain
        {
            invalidAddress = true
        }
    }
}

/// 全局假设备状态，受互斥锁保护。
private let audio = Mutex(AudioFixture())

// 这些模块内函数遮蔽真实的 CoreAudio 调用，使其远离真实硬件。
/// 遮蔽 CoreAudio 的读属性调用，返回默认输入设备或静音值（含延时读的模拟）。
func AudioObjectGetPropertyData(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
    _ size: UnsafeMutablePointer<UInt32>, _ data: UnsafeMutableRawPointer
) -> OSStatus {
    audio.withLock { fixture in
        if address.pointee.mSelector == kAudioHardwarePropertyDefaultInputDevice {
            fixture.defaultLookups += 1
            if device != kAudioObjectSystemObject
                || address.pointee.mScope != kAudioObjectPropertyScopeGlobal
                || address.pointee.mElement != kAudioObjectPropertyElementMain
            {
                fixture.invalidAddress = true
            }
            data.storeBytes(of: fixture.device, as: AudioDeviceID.self)
            return fixture.lookupStatus
        }
        fixture.check(device, address.pointee)
        if let pending = fixture.pendingMute, fixture.appliesWrite {
            if fixture.delayedReads == 0 {
                fixture.muted = pending
            } else {
                fixture.delayedReads -= 1
            }
        }
        data.storeBytes(of: fixture.muted, as: UInt32.self)
        return fixture.readStatus
    }
}

/// 遮蔽 CoreAudio 的属性存在性查询，返回夹具的 hasMute。
func AudioObjectHasProperty(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>
) -> Bool {
    audio.withLock { fixture in
        fixture.check(device, address.pointee)
        return fixture.hasMute
    }
}

/// 遮蔽 CoreAudio 的可写性查询，返回夹具的 settable。
func AudioObjectIsPropertySettable(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ settable: UnsafeMutablePointer<DarwinBoolean>
) -> OSStatus {
    audio.withLock { fixture in
        fixture.check(device, address.pointee)
        settable.pointee = DarwinBoolean(fixture.settable)
        return noErr
    }
}

/// 遮蔽 CoreAudio 的写属性调用，记录写入值并按夹具配置决定是否生效。
func AudioObjectSetPropertyData(
    _ device: AudioObjectID, _ address: UnsafePointer<AudioObjectPropertyAddress>,
    _ qualifierSize: UInt32, _ qualifier: UnsafeRawPointer?,
    _ size: UInt32, _ data: UnsafeRawPointer
) -> OSStatus {
    audio.withLock { fixture in
        fixture.check(device, address.pointee)
        let value = data.load(as: UInt32.self)
        fixture.writes.append(value)
        if fixture.writeStatus == noErr { fixture.pendingMute = value }
        if let next = fixture.nextDefaultDevice { fixture.device = next }
        return fixture.writeStatus
    }
}

/// 麦克风静音切换的测试集合。
@main
@MainActor
struct MicrophoneMuteTests {
    static var failures = 0
    static var passes = 0

    /// 断言辅助：失败时累加失败数并打印失败信息。
    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    /// 用给定夹具重置全局假设备状态。
    private static func reset(_ fixture: AudioFixture = AudioFixture()) {
        audio.withLock { $0 = fixture }
    }

    /// 断言一次切换成功，且反馈与确认后的静音状态一致、只写一次、只访问输入静音属性。
    static func expectToggle(_ muted: Bool) async {
        do {
            let result = try await SystemActionRunner.toggleMicrophoneMute()
            expect(result == muted, "feedback matches the confirmed microphone state")
            audio.withLock { fixture in
                expect(fixture.muted == (muted ? 1 : 0), "the native mute state changed")
                expect(fixture.writes == [muted ? 1 : 0], "mute is written exactly once")
                expect(!fixture.invalidAddress, "only input mute and the default input are accessed")
            }
        } catch {
            expect(false, "unexpected failure: \(error)")
        }
    }

    /// 断言一次切换失败，错误信息包含给定文案，且只发生预期的写入次数。
    static func expectFailure(_ message: String, writes: Int = 0) async {
        do {
            _ = try await SystemActionRunner.toggleMicrophoneMute()
            expect(false, "an unconfirmed change must not report success")
        } catch let failure as SystemActionFailure {
            expect(failure.localizedMessage(.english).contains(message), "the failure explains \(message)")
            audio.withLock { fixture in
                expect(fixture.writes.count == writes, "failure performs only expected writes")
                expect(!fixture.invalidAddress, "failure does not access output audio or gain")
            }
        } catch {
            expect(false, "unexpected error type: \(error)")
        }
    }

    /// 依次运行全部用例，并在有失败时以非零状态码退出。
    static func main() async {
        reset()
        await expectToggle(true)

        reset(AudioFixture(muted: 1))
        await expectToggle(false)

        reset(AudioFixture(delayedReads: 2))
        await expectToggle(true)

        reset(AudioFixture(nextDefaultDevice: 99))
        await expectToggle(true)
        audio.withLock { fixture in
            expect(fixture.defaultLookups == 1, "one activation resolves the default input once")
            expect(fixture.controlDevices.allSatisfy { $0 == 78 }, "readback stays on the written device")
        }
        reset(AudioFixture(device: 99, muted: 1))
        await expectToggle(false)
        expect(
            audio.withLock { $0.controlDevices.allSatisfy { $0 == 99 } },
            "the next toggle follows the new input")

        reset(AudioFixture(device: kAudioObjectUnknown))
        await expectFailure("No audio input device")
        reset(AudioFixture(lookupStatus: -1))
        await expectFailure("No audio input device")
        reset(AudioFixture(hasMute: false))
        await expectFailure("does not support software mute")
        reset(AudioFixture(settable: false))
        await expectFailure("controlled externally")
        reset(AudioFixture(readStatus: -2))
        await expectFailure("could not read microphone mute")
        reset(AudioFixture(writeStatus: -3))
        await expectFailure("could not change microphone mute", writes: 1)
        reset(AudioFixture(appliesWrite: false))
        await expectFailure("did not confirm", writes: 1)

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
