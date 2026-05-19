import Foundation
import Combine
import AVFoundation
import SFBAudioEngine

/// Audova の再生エンジン外装。
///
/// 役割:
/// - `SFBAudioEngine.AudioPlayer` を所有し、 SwiftUI から監視できる `@Published` 状態を露出する
/// - 再生キュー (`PlaybackQueue`) を所有し、 next / prev / 曲跨ぎを制御する
/// - 1 秒ごとに再生位置を pull で更新する (= SFBAudioEngine は時間を delegate で push しない)
///
/// スレッドモデル: `@MainActor`。 SwiftUI 側からの操作は main で受け、 SFB delegate コールバックは
/// 任意 queue から来るので `MainActor.assumeIsolated` で main へ戻して state を触る。
@MainActor
public final class Player: NSObject, ObservableObject {
    // MARK: - Published state

    /// 再生状態。 `.stopped` / `.paused` / `.playing` の 3 状態 (= SFBAudioEngine の enum をそのまま expose)。
    @Published public private(set) var playbackState: AudioPlayer.PlaybackState = .stopped

    /// 現在曲のキュー上の表現 (= 表示用)。
    @Published public private(set) var currentItem: QueueItem?

    /// 再生位置 (秒)。 不明な間は 0。
    @Published public private(set) var currentTime: TimeInterval = 0

    /// 現在曲の総時間 (秒)。 不明な間は 0。
    @Published public private(set) var totalTime: TimeInterval = 0

    /// 0.0 - 1.0 の master volume。 SFBAudioEngine 経由で `kHALOutputParam_Volume` を叩く。
    @Published public private(set) var volume: Float = 1.0

    /// キュー本体。 SwiftUI 側で「Up Next」 を表示する時に参照する。
    @Published public private(set) var queue = PlaybackQueue()

    /// 最後に発生したエラーメッセージ (= toast / ステータスバー表示用)。
    @Published public private(set) var lastError: String?

    // MARK: - Internals

    private let audioPlayer = AudioPlayer()
    private var timerCancellable: AnyCancellable?

    public override init() {
        super.init()
        audioPlayer.delegate = self
        // 初期 volume を engine 起動前に問い合わせると NaN になり得るので、 デフォルトは 1.0 のまま据え置く。
        // engine 起動後に `syncVolumeFromEngine()` で実値に合わせる。
    }

    deinit {
        // `audioPlayer.stop()` は engine を止め、 decoder を破棄する。
        // `@MainActor` deinit から Sendable でない参照を触らないようにそのまま破棄に任せる。
    }

    // MARK: - 操作 (= SwiftUI からの入口)

    /// 1 件を即時再生。 既存キュー / 再生中の decoder を破棄して URL の新規再生を始める。
    public func playNow(_ item: QueueItem) {
        queue.playNow(item)
        currentItem = item
        startCurrent(immediate: true)
    }

    /// 1 件を即時再生 (URL のみ)。 メタは ad-hoc で空。
    public func playNow(url: URL) {
        playNow(QueueItem(url: url))
    }

    /// キュー末尾に追加 (= 現在再生中はそのまま)。
    public func enqueue(_ item: QueueItem) {
        queue.append(item)
        // SFB の queue にも乗せておくとギャップレス再生が効く。 再生中でなければ enqueue だけしておく。
        do {
            try audioPlayer.enqueue(item.url, immediate: false)
        } catch {
            recordError("enqueue 失敗: \(error.localizedDescription)")
        }
    }

    public func enqueue(url: URL) {
        enqueue(QueueItem(url: url))
    }

    /// 既存キューを置き換え、 指定 index から再生開始。
    public func replaceQueue(_ items: [QueueItem], startAt index: Int = 0) {
        queue.replaceAll(items, startAt: index)
        currentItem = queue.current
        startCurrent(immediate: true)
    }

    /// Play / Pause トグル。 stopped 状態でキューが残っていれば current を再生開始する。
    public func togglePlayPause() {
        switch playbackState {
        case .playing:
            _ = audioPlayer.pause()
        case .paused:
            _ = audioPlayer.resume()
        case .stopped:
            if currentItem != nil {
                startCurrent(immediate: true)
            } else if let first = queue.items.first {
                queue.jump(to: 0)
                currentItem = first
                startCurrent(immediate: true)
            }
        @unknown default:
            break
        }
    }

    public func stop() {
        audioPlayer.stop()
        currentTime = 0
    }

    /// 次のトラックへ。 キュー末端なら停止。
    public func next() {
        if let item = queue.advance() {
            currentItem = item
            startCurrent(immediate: true)
        } else {
            currentItem = nil
            audioPlayer.stop()
            currentTime = 0
        }
    }

    /// 前のトラックへ。 ただし再生位置が 3 秒以上進んでいる時は曲頭シーク (= 一般的な player の挙動)。
    public func previous() {
        if currentTime > 3.0, audioPlayer.supportsSeeking {
            _ = audioPlayer.seek(time: 0)
            currentTime = 0
            return
        }
        if let item = queue.retreat() {
            currentItem = item
            startCurrent(immediate: true)
        }
    }

    /// 相対シーク (秒)。 ±5 秒等。 supportsSeeking が false なら no-op。
    public func seek(byDelta seconds: TimeInterval) {
        guard audioPlayer.supportsSeeking else { return }
        let target = max(0, min(currentTime + seconds, totalTime > 0 ? totalTime : currentTime + seconds))
        _ = audioPlayer.seek(time: target)
        currentTime = target
    }

    /// 絶対シーク (秒)。
    public func seek(to seconds: TimeInterval) {
        guard audioPlayer.supportsSeeking else { return }
        let clamped = max(0, totalTime > 0 ? min(seconds, totalTime) : seconds)
        _ = audioPlayer.seek(time: clamped)
        currentTime = clamped
    }

    /// 0.0 - 1.0 の volume を設定。
    public func setVolume(_ value: Float) {
        let clamped = max(0, min(1.0, value))
        do {
            try audioPlayer.setVolume(clamped)
            volume = clamped
        } catch {
            // engine 未起動だと NaN/失敗するので、 値だけ覚えて次回起動時に sync する。
            volume = clamped
        }
    }

    /// 音量を相対調整 (= Cmd+↑/↓ 用)。
    public func adjustVolume(by delta: Float) {
        setVolume(volume + delta)
    }

    public func clearQueue() {
        audioPlayer.clearQueue()
        queue.clear()
        currentItem = nil
        audioPlayer.stop()
        currentTime = 0
        totalTime = 0
    }

    // MARK: - 進捗 polling

    /// 進捗 timer を開始する。 1 秒ごとに `currentTime` / `totalTime` を SFB から pull する。
    /// SwiftUI 側 view appear / disappear から呼ぶ。
    public func startProgressUpdates() {
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.refreshTimes()
            }
        // 即時 1 回引いておく。
        refreshTimes()
    }

    public func stopProgressUpdates() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func refreshTimes() {
        if let t = audioPlayer.time {
            currentTime = t.current ?? currentTime
            totalTime = t.total ?? totalTime
        }
    }

    private func syncVolumeFromEngine() {
        let v = audioPlayer.volume
        if v.isFinite, v >= 0, v <= 1 {
            volume = v
        }
    }

    // MARK: - 内部実装

    /// 現在 `queue.current` を SFB に流す。 失敗時はエラー文字列を `lastError` に記録。
    private func startCurrent(immediate: Bool) {
        guard let item = queue.current else { return }
        do {
            // immediate=true: 即時再生 (= 再生中ならキャンセル + 新規 play)
            // immediate=false: enqueue だけ (= ギャップレス継続用)
            if immediate {
                try audioPlayer.play(item.url)
            } else {
                try audioPlayer.enqueue(item.url, immediate: false)
            }
            // engine 起動直後に volume を実値へ sync。
            syncVolumeFromEngine()
        } catch {
            recordError("再生失敗: \(error.localizedDescription)")
        }
    }

    private func recordError(_ message: String) {
        lastError = message
    }
}

// MARK: - AudioPlayer.Delegate

extension Player: AudioPlayer.Delegate {
    public nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, playbackStateChanged playbackState: AudioPlayer.PlaybackState) {
        Task { @MainActor in
            self.playbackState = playbackState
        }
    }

    public nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, nowPlayingChanged nowPlaying: (any PCMDecoding)?) {
        // SFB の nowPlaying は decoder。 queue 側 advance は `audioPlayerEndOfAudio` で扱うので、 ここでは表示更新のみ。
        // 現状 currentItem は親側で advance 時に明示更新しているので、 ここでは特に何もしない。
    }

    public nonisolated func audioPlayerEndOfAudio(_ audioPlayer: AudioPlayer) {
        // 全 decoder 再生完了。 キュー上で次に進める。
        Task { @MainActor in
            self.next()
        }
    }

    public nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, encounteredError error: Error) {
        Task { @MainActor in
            self.recordError("再生エンジンエラー: \(error.localizedDescription)")
        }
    }

    public nonisolated func audioPlayer(_ audioPlayer: AudioPlayer, decodingAborted decoder: any PCMDecoding, error: Error, framesRendered: AVAudioFramePosition) {
        Task { @MainActor in
            self.recordError("デコード中断: \(error.localizedDescription)")
        }
    }
}
