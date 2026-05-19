import SwiftUI
import AudovaCore

/// アプリケーションメニュー「再生」 を提供する Commands。
///
/// 標準ショートカット:
/// - Space — 再生 / 一時停止
/// - Cmd+→ / Cmd+← — 次の曲 / 前の曲
/// - → / ← — 5 秒スキップ (= seek byDelta)
/// - Cmd+↑ / Cmd+↓ — 音量 ±5%
///
/// `Player` を `@ObservedObject` で監視し、 menu の label / disabled state を動的に更新する。
struct PlaybackCommands: Commands {
    @ObservedObject var player: Player

    var body: some Commands {
        CommandMenu("再生") {
            Button(player.playbackState == .playing ? "一時停止" : "再生") {
                player.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(player.currentItem == nil && player.queue.items.isEmpty)

            Divider()

            Button("次の曲") { player.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(!player.queue.hasNext)

            Button("前の曲") { player.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(player.currentItem == nil)

            Divider()

            Button("少し進める (+5秒)") { player.seek(byDelta: 5) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(player.currentItem == nil)

            Button("少し戻す (-5秒)") { player.seek(byDelta: -5) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(player.currentItem == nil)

            Divider()

            Button("音量を上げる") { player.adjustVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: [.command])

            Button("音量を下げる") { player.adjustVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: [.command])
        }
    }
}
