import Foundation
import Combine
import MediaPlayer
import AppKit
import SFBAudioEngine
import AudovaCore

/// メディアキー (⏯⏭⏮) / イヤホンのボタン / コントロールセンターの「再生中」 と `Player` を繋ぐ。
///
/// - `MPRemoteCommandCenter`: システムから来る再生コマンドを `Player` のメソッドへ転送する。
/// - `MPNowPlayingInfoCenter`: 現在曲のメタ + ジャケット + 経過時間を OS に publish し、
///   コントロールセンター / ロック画面に表示させる。
///
/// macOS では特別な entitlement / 権限ダイアログは不要 (= 音を鳴らしているアプリが Now Playing になる)。
@MainActor
final class NowPlayingController {
    private let player: Player
    private var cancellables: Set<AnyCancellable> = []
    /// シーク (= 大きな時間ジャンプ) 検出用に直前の再生位置を覚えておく。
    private var lastTime: TimeInterval = 0

    init(player: Player) {
        self.player = player
        configureRemoteCommands()
        observePlayer()
    }

    // MARK: - リモートコマンド (= メディアキー / イヤホン / コントロールセンター)

    private func configureRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()

        center.playCommand.addTarget { [weak player] _ in
            guard let player else { return .commandFailed }
            if player.playbackState != .playing { player.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak player] _ in
            guard let player else { return .commandFailed }
            if player.playbackState == .playing { player.togglePlayPause() }
            return .success
        }
        center.togglePlayPauseCommand.addTarget { [weak player] _ in
            guard let player else { return .commandFailed }
            player.togglePlayPause()
            return .success
        }
        center.nextTrackCommand.addTarget { [weak player] _ in
            guard let player, player.canGoNext else { return .commandFailed }
            player.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak player] _ in
            guard let player else { return .commandFailed }
            player.previous()
            return .success
        }
        center.changePlaybackPositionCommand.addTarget { [weak player] event in
            guard let player, let event = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            player.seek(to: event.positionTime)
            return .success
        }
    }

    // MARK: - Player 監視 → Now Playing 更新

    private func observePlayer() {
        // @Published の projected publisher (`$`) は willSet 時点で発火するため、 sink 内で
        // `player.xxx` を読むと commit 前の「1 つ前の値」になる (= Combine の既知の挙動)。
        // `.receive(on:)` で次の runloop へずらし、 commit 後の最新値を読むようにする
        // (= 状態が 1 操作分遅れてコントロールセンターが誤った再生/一時停止を表示し、
        //   一時停止から再開できなくなる問題の防止)。
        // 曲が変わったら全情報を更新。
        player.$currentItem
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshNowPlaying() }
            .store(in: &cancellables)
        // 再生 / 一時停止で rate + 経過時間を更新。
        player.$playbackState
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.refreshNowPlaying() }
            .store(in: &cancellables)
        // 通常進行 (0.25 秒刻み) では更新せず、 シーク等の大きなジャンプ時だけ経過時間を同期。
        player.progress.$currentTime
            .receive(on: DispatchQueue.main)
            .sink { [weak self] time in
                guard let self else { return }
                if abs(time - self.lastTime) > 1.5 { self.refreshNowPlaying() }
                self.lastTime = time
            }
            .store(in: &cancellables)
    }

    private func refreshNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        guard let item = player.currentItem else {
            center.nowPlayingInfo = nil
            center.playbackState = .stopped
            return
        }

        var info: [String: Any] = [:]
        info[MPMediaItemPropertyTitle] = item.displayTitle
        if let artist = item.artist { info[MPMediaItemPropertyArtist] = artist }
        if let album = item.albumTitle { info[MPMediaItemPropertyAlbumTitle] = album }
        if player.totalTime > 0 { info[MPMediaItemPropertyPlaybackDuration] = player.totalTime }
        info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = player.currentTime
        info[MPNowPlayingInfoPropertyPlaybackRate] = player.playbackState == .playing ? 1.0 : 0.0
        if let artwork = artwork(for: item) { info[MPMediaItemPropertyArtwork] = artwork }

        center.nowPlayingInfo = info
        center.playbackState = mpState(for: player.playbackState)
    }

    private func artwork(for item: QueueItem) -> MPMediaItemArtwork? {
        guard let path = item.artworkPath, let image = NSImage(contentsOfFile: path) else { return nil }
        return MPMediaItemArtwork(boundsSize: image.size) { _ in image }
    }

    private func mpState(for state: AudioPlayer.PlaybackState) -> MPNowPlayingPlaybackState {
        switch state {
        case .playing: return .playing
        case .paused: return .paused
        case .stopped: return .stopped
        @unknown default: return .unknown
        }
    }
}
