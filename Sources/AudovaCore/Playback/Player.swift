import Foundation
import Combine
import AVFoundation
import CoreAudio
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
/// リピートモード。 off (リピートなし) / all (キュー全体を繰り返す) / one (現在曲を繰り返す)。
public enum RepeatMode: String, CaseIterable, Sendable {
    case off, all, one
}

/// 再生位置 (秒) / 総時間を保持する軽量 observable。
///
/// `Player` の進捗 timer が 0.25 秒ごとに更新するため、 これを `Player` 本体の `@Published` から
/// 切り離すことで、 位置を必要としない購読者 (= メニュー `PlaybackCommands` 等) を高頻度の再評価から守る
/// (= 以前はメニューが秒 4 回リビルドされ、 メニューバーが点滅 + CPU を浪費していた)。
@MainActor
public final class PlaybackProgress: ObservableObject {
    /// 再生位置 (秒)。 不明な間は 0。
    @Published public internal(set) var currentTime: TimeInterval = 0

    /// 現在曲の総時間 (秒)。 不明な間は 0。
    @Published public internal(set) var totalTime: TimeInterval = 0
}

@MainActor
public final class Player: NSObject, ObservableObject {
    // MARK: - Published state

    /// 再生状態。 `.stopped` / `.paused` / `.playing` の 3 状態 (= SFBAudioEngine の enum をそのまま expose)。
    @Published public private(set) var playbackState: AudioPlayer.PlaybackState = .stopped

    /// 現在曲のキュー上の表現 (= 表示用)。
    @Published public private(set) var currentItem: QueueItem?

    /// 再生位置 / 総時間。 0.25 秒ごとに更新されるため、 位置を必要としない購読者 (= メニュー等) を
    /// 高頻度の再評価から守る目的で `Player` 本体の `@Published` とは別 observable に分離している
    /// (= メニューバー点滅 / CPU 浪費の防止)。
    public let progress = PlaybackProgress()

    /// 再生位置 (秒)。 不明な間は 0。 実体は `progress` (= 既存呼び出し互換のため計算プロパティで残す)。
    public var currentTime: TimeInterval { progress.currentTime }

    /// 現在曲の総時間 (秒)。 不明な間は 0。
    public var totalTime: TimeInterval { progress.totalTime }

    /// 0.0 - 1.0 の master volume。 SFBAudioEngine 経由で `kHALOutputParam_Volume` を叩く。
    @Published public private(set) var volume: Float = 1.0

    /// 選択可能な出力デバイス一覧 (= デバイス増減で自動更新)。
    @Published public private(set) var availableOutputDevices: [AudioOutputDevice] = []

    /// 選択中の出力デバイス UID。 nil = システム既定に追従。
    @Published public private(set) var selectedOutputDeviceUID: String?

    /// キュー本体。 SwiftUI 側で「Up Next」 を表示する時に参照する。
    @Published public private(set) var queue = PlaybackQueue()

    /// リピートモード (= off / all / one)。
    @Published public private(set) var repeatMode: RepeatMode = .off

    /// 最後に発生したエラーメッセージ (= toast / ステータスバー表示用)。
    @Published public private(set) var lastError: String?

    // MARK: - Internals

    private let audioPlayer = AudioPlayer()
    private var timerCancellable: AnyCancellable?

    /// 出力デバイス選択の永続化キー。
    private static let outputDeviceUIDKey = "selectedOutputDeviceUID"
    /// 出力デバイスの増減監視 (= 接続 / 切断に追従)。
    private var deviceWatcher: AudioOutputDeviceWatcher?

    public override init() {
        super.init()
        audioPlayer.delegate = self
        // 初期 volume を engine 起動前に問い合わせると NaN になり得るので、 デフォルトは 1.0 のまま据え置く。
        // engine 起動後に `syncVolumeFromEngine()` で実値に合わせる。
        // 進捗 timer は init で起動する (= view 描画依存を避ける。 transport bar の onAppear/onDisappear 経由だと
        // view が一瞬でも tree から外れると stop されて時間表示が止まるため)。
        startProgressUpdates()

        // 出力デバイス: 永続化された選択を復元し、 一覧を列挙、 増減を監視する。
        selectedOutputDeviceUID = UserDefaults.standard.string(forKey: Self.outputDeviceUIDKey)
        refreshOutputDevices()
        deviceWatcher = AudioOutputDeviceWatcher { [weak self] in
            Task { @MainActor in self?.handleOutputDevicesChanged() }
        }
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
        progress.currentTime = 0
    }

    /// シャッフル on/off を切り替える。
    public func toggleShuffle() {
        queue.setShuffled(!queue.isShuffled)
    }

    /// リピートモードを off → all → one → off で循環させる。
    public func cycleRepeatMode() {
        switch repeatMode {
        case .off: repeatMode = .all
        case .all: repeatMode = .one
        case .one: repeatMode = .off
        }
    }

    /// シャッフル中か (= UI バインド用)。
    public var isShuffled: Bool { queue.isShuffled }

    /// 「次へ」 が可能か。 リピート時はキューに曲があれば末端でも可。
    public var canGoNext: Bool {
        queue.hasNext || (repeatMode != .off && !queue.items.isEmpty)
    }

    /// 次のトラックへ。 リピート off ではキュー末端で停止、 それ以外は先頭へ回り込む。
    public func next() {
        if let item = queue.advance(wrap: repeatMode != .off) {
            currentItem = item
            startCurrent(immediate: true)
        } else {
            currentItem = nil
            audioPlayer.stop()
            progress.currentTime = 0
        }
    }

    /// 前のトラックへ。 ただし再生位置が 3 秒以上進んでいる時は曲頭シーク (= 一般的な player の挙動)。
    public func previous() {
        if currentTime > 3.0, audioPlayer.supportsSeeking {
            _ = audioPlayer.seek(time: 0)
            progress.currentTime = 0
            return
        }
        if let item = queue.retreat(wrap: repeatMode != .off) {
            currentItem = item
            startCurrent(immediate: true)
        }
    }

    /// 相対シーク (秒)。 ±5 秒等。 supportsSeeking が false なら no-op。
    public func seek(byDelta seconds: TimeInterval) {
        guard audioPlayer.supportsSeeking else { return }
        let target = max(0, min(currentTime + seconds, totalTime > 0 ? totalTime : currentTime + seconds))
        _ = audioPlayer.seek(time: target)
        progress.currentTime = target
    }

    /// 絶対シーク (秒)。
    public func seek(to seconds: TimeInterval) {
        guard audioPlayer.supportsSeeking else { return }
        let clamped = max(0, totalTime > 0 ? min(seconds, totalTime) : seconds)
        _ = audioPlayer.seek(time: clamped)
        progress.currentTime = clamped
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
        progress.currentTime = 0
        progress.totalTime = 0
    }

    // MARK: - 出力デバイス

    /// 出力デバイス一覧を再列挙する。
    public func refreshOutputDevices() {
        availableOutputDevices = AudioOutputDevices.available()
    }

    /// 出力デバイスを選択する。 `uid` が nil ならシステム既定に追従。 選択は永続化する。
    public func selectOutputDevice(uid: String?) {
        selectedOutputDeviceUID = uid
        if let uid {
            UserDefaults.standard.set(uid, forKey: Self.outputDeviceUIDKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.outputDeviceUIDKey)
        }
        applyOutputDevice()
    }

    /// デバイス増減時: 一覧を更新し、 選択中デバイスを再解決して適用し直す (= DAC 再接続に追従)。
    private func handleOutputDevicesChanged() {
        refreshOutputDevices()
        applyOutputDevice()
    }

    /// 選択中 (= UID) のデバイスを現在の AudioObjectID へ解決して engine に適用する。
    /// 選択デバイスが見つからない / 未選択ならシステム既定にフォールバック。
    /// engine 未起動時は失敗し得るが、 次の再生開始時 (`startCurrent`) に再適用される。
    private func applyOutputDevice() {
        let targetID: AudioObjectID?
        if let uid = selectedOutputDeviceUID {
            targetID = AudioOutputDevices.deviceID(forUID: uid) ?? AudioOutputDevices.defaultOutputDeviceID()
        } else {
            targetID = AudioOutputDevices.defaultOutputDeviceID()
        }
        guard let targetID else { return }
        try? audioPlayer.setOutputDeviceID(targetID)
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
            progress.currentTime = t.current ?? progress.currentTime
            progress.totalTime = t.total ?? progress.totalTime
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
                applyOutputDevice()
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

    /// 自然終了 (= 曲が最後まで再生された) 時の遷移。 repeat one は同曲を再生し直し、
    /// それ以外は次へ進む (repeat all なら末端で先頭へ回り込む)。
    private func handleTrackEnded() {
        if repeatMode == .one {
            startCurrent(immediate: true)
            return
        }
        if let item = queue.advance(wrap: repeatMode == .all) {
            currentItem = item
            startCurrent(immediate: true)
        } else {
            currentItem = nil
            audioPlayer.stop()
            progress.currentTime = 0
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
        // 全 decoder 再生完了。 リピートモードに応じて次の挙動を決める。
        Task { @MainActor in
            self.handleTrackEnded()
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
