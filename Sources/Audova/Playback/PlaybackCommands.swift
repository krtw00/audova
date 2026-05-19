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
/// `@FocusedObject` で scene focus 経由の `Player` を受け取る。 旧実装の `@ObservedObject` 直渡しは
/// macOS SwiftUI Commands で keyboard shortcut event が view tree に伝播しない既知挙動があるため、
/// `.focusedSceneObject(player)` 経由の bind に切り替えている。
struct PlaybackCommands: Commands {
    @FocusedObject private var player: Player?

    var body: some Commands {
        CommandMenu("再生") {
            Button(isPlaying ? "一時停止" : "再生") {
                player?.togglePlayPause()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(player == nil || !hasAnything)

            Divider()

            Button("次の曲") { player?.next() }
                .keyboardShortcut(.rightArrow, modifiers: [.command])
                .disabled(player?.queue.hasNext != true)

            Button("前の曲") { player?.previous() }
                .keyboardShortcut(.leftArrow, modifiers: [.command])
                .disabled(player?.currentItem == nil)

            Divider()

            Button("少し進める (+5秒)") { player?.seek(byDelta: 5) }
                .keyboardShortcut(.rightArrow, modifiers: [])
                .disabled(player?.currentItem == nil)

            Button("少し戻す (-5秒)") { player?.seek(byDelta: -5) }
                .keyboardShortcut(.leftArrow, modifiers: [])
                .disabled(player?.currentItem == nil)

            Divider()

            Button("音量を上げる") { player?.adjustVolume(by: 0.05) }
                .keyboardShortcut(.upArrow, modifiers: [.command])
                .disabled(player == nil)

            Button("音量を下げる") { player?.adjustVolume(by: -0.05) }
                .keyboardShortcut(.downArrow, modifiers: [.command])
                .disabled(player == nil)
        }
    }

    private var isPlaying: Bool {
        player?.playbackState == .playing
    }

    private var hasAnything: Bool {
        guard let player else { return false }
        return player.currentItem != nil || !player.queue.items.isEmpty
    }
}
