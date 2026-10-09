// 文件职责：用 AVKit 在预览区播放影片或录音，并在不可见或消失时释放播放器与其解码资源。
// 分层：UI；SwiftUI 与 AppKit 混合（NSViewRepresentable 包装 AVPlayerView）。
import AVKit
import SwiftUI

/// 由 AVKit 播放的影片或录音。
struct FileSearchMediaPlayer: View {

    @Environment(PaletteState.self) private var palette
    let url: URL
    let autoplays: Bool
    @State private var player: AVPlayer?

    /// 两种销毁触发条件共用一把键，避免额外的 `onChange` 与任务竞争。
    private struct PlaybackKey: Equatable {
        let url: URL
        let isVisible: Bool
    }

    var body: some View {
        PlayerSurface(player: player)
            .task(id: PlaybackKey(url: url, isVisible: palette.isVisible)) {
                stop()
                guard palette.isVisible else { return }
                let player = AVPlayer(url: url)
                if autoplays { player.play() }
                self.player = player
            }
            .onDisappear(perform: stop)
    }

    /// 同时清空播放项：即使暂停，播放器仍会持有资源读取器与解码器。
    private func stop() {
        player?.pause()
        player?.replaceCurrentItem(with: nil)
        player = nil
    }
}

/// 使用 `AVPlayerView`，因为 SwiftUI 的 `VideoPlayer` 在实例化其泛型元数据时会崩溃。
private struct PlayerSurface: NSViewRepresentable {
    let player: AVPlayer?

    func makeNSView(context: Context) -> AVPlayerView {
        let view = PreviewPlayerView()
        view.controlsStyle = .inline
        view.showsFullScreenToggleButton = false
        view.videoGravity = .resizeAspect
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        guard view.player !== player else { return }
        view.player = player
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause()
        view.player = nil
    }
}

/// 点击播放不能把键盘焦点从搜索框移开，而播放控制按钮会。
private final class PreviewPlayerView: AVPlayerView, KeyboardFocusRefusing {}
