import SwiftUI
import SFBAudioEngine
import AudovaCore

/// ウィンドウ下部に固定する transport bar。
///
/// 構成 (横並び):
/// 1. 現在曲メタ (= タイトル / アーティスト・アルバム)
/// 2. transport ボタン群 (= 前 / 再生・一時停止 / 次)
/// 3. 進捗 (= 経過時間 + slider + 残り時間)
/// 4. 音量 slider
///
/// state はすべて `Player` (`@EnvironmentObject`) を経由するので、 view 自体は state を持たない。
public struct TransportBarView: View {
    @EnvironmentObject private var player: Player

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(path: player.currentItem?.artworkPath, size: 40)

            metadataBlock
                .frame(minWidth: 180, idealWidth: 240, maxWidth: 280, alignment: .leading)

            transportButtons

            ProgressScrubber(progress: player.progress) { player.seek(to: $0) }
                .frame(maxWidth: .infinity)

            volumeBlock
                .frame(width: 140)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        // 進捗 timer は Player.init で自動起動する (= view 描画依存を排除)。 ここでは購読のみ。
    }

    // MARK: - parts

    private var metadataBlock: some View {
        VStack(alignment: .leading, spacing: 2) {
            if let item = player.currentItem {
                Text(item.displayTitle)
                    .font(.callout).bold()
                    .lineLimit(1)
                Text(subline(for: item))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            } else {
                Text("再生していません")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Text(" ")
                    .font(.caption)
            }
        }
    }

    private func subline(for item: QueueItem) -> String {
        switch (item.artist, item.albumTitle) {
        case let (a?, b?): return "\(a) — \(b)"
        case let (a?, nil): return a
        case let (nil, b?): return b
        case (nil, nil): return item.url.deletingLastPathComponent().lastPathComponent
        }
    }

    private var transportButtons: some View {
        HStack(spacing: 4) {
            Button { player.toggleShuffle() } label: {
                Image(systemName: "shuffle")
            }
            .help(player.isShuffled ? "シャッフル: オン" : "シャッフル: オフ")
            .foregroundStyle(player.isShuffled ? Color.accentColor : Color.secondary)
            .disabled(player.queue.items.isEmpty)

            Button { player.previous() } label: {
                Image(systemName: "backward.fill")
            }
            .help("前の曲 (Cmd+←)")
            .disabled(player.currentItem == nil)

            Button { player.togglePlayPause() } label: {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .frame(width: 22, height: 22)
            }
            .help(isPlaying ? "一時停止 (Space)" : "再生 (Space)")
            .disabled(player.currentItem == nil && player.queue.items.isEmpty)

            Button { player.next() } label: {
                Image(systemName: "forward.fill")
            }
            .help("次の曲 (Cmd+→)")
            .disabled(!player.canGoNext)

            Button { player.cycleRepeatMode() } label: {
                Image(systemName: player.repeatMode == .one ? "repeat.1" : "repeat")
            }
            .help(repeatHelp)
            .foregroundStyle(player.repeatMode == .off ? Color.secondary : Color.accentColor)
            .disabled(player.queue.items.isEmpty)
        }
        .buttonStyle(.borderless)
        .font(.title3)
    }

    private var repeatHelp: String {
        switch player.repeatMode {
        case .off: return "リピート: オフ"
        case .all: return "リピート: 全曲"
        case .one: return "リピート: 1曲"
        }
    }

    private var volumeBlock: some View {
        HStack(spacing: 6) {
            Image(systemName: volumeIconName)
                .foregroundStyle(.secondary)
            Slider(
                value: Binding(
                    get: { Double(player.volume) },
                    set: { player.setVolume(Float($0)) }
                ),
                in: 0...1
            )
        }
    }

    private var isPlaying: Bool { player.playbackState == .playing }

    private var volumeIconName: String {
        switch player.volume {
        case ..<0.01: return "speaker.slash.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

/// 進捗 slider + 経過/残り時間。 0.25 秒ごとに更新される `PlaybackProgress` のみを購読する独立 view。
/// これにより transport bar 本体やメニュー (`PlaybackCommands`) を高頻度の再描画に巻き込まない
/// (= メニューバー点滅 / CPU 浪費の防止)。
private struct ProgressScrubber: View {
    @ObservedObject var progress: PlaybackProgress

    /// slider ドラッグ中の値を一時保持 (= 再生位置を引っ張られている間 polling と競合させない)。
    @State private var seekDraft: Double? = nil

    /// ドラッグ終了時のシーク依頼 (= 実体は `Player.seek(to:)`)。
    let onSeek: (TimeInterval) -> Void

    init(progress: PlaybackProgress, onSeek: @escaping (TimeInterval) -> Void) {
        self.progress = progress
        self.onSeek = onSeek
    }

    var body: some View {
        VStack(spacing: 2) {
            Slider(
                value: Binding(
                    get: { seekDraft ?? progress.currentTime },
                    set: { seekDraft = $0 }
                ),
                in: 0...max(progress.totalTime, 0.001),
                onEditingChanged: { editing in
                    if !editing, let value = seekDraft {
                        onSeek(value)
                        seekDraft = nil
                    }
                }
            )
            .disabled(progress.totalTime <= 0)

            HStack {
                Text(formatTime(seekDraft ?? progress.currentTime))
                Spacer()
                Text("-" + formatTime(max(progress.totalTime - (seekDraft ?? progress.currentTime), 0)))
            }
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let total = Int(seconds.rounded(.down))
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        }
        return String(format: "%d:%02d", m, s)
    }
}
