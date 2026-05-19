import Foundation

/// ライブラリ画面 (= AUD-5) と再生エンジン (= AUD-6) を疎結合に繋ぐ hook 集。
///
/// AUD-5 単体ビルド時点では `noop` でビルドが通り、 AUD-6 完走後に実 Player を bind した実装で
/// 上書きする。 closure ベースにしているのは「再生キューに追加」 程度の薄い連携しか
/// 必要ないため (= 完全な protocol-conformance を強制すると AUD-6 側が縛られる)。
public struct LibraryTrackActions: Sendable {
    /// 即時再生 (= ダブルクリック / Enter / context menu「今すぐ再生」)。
    public var playNow: @MainActor @Sendable (TrackRow) -> Void
    /// 再生キュー末尾に追加 (= context menu「再生キューに追加」)。
    public var enqueue: @MainActor @Sendable (TrackRow) -> Void

    public init(
        playNow: @escaping @MainActor @Sendable (TrackRow) -> Void,
        enqueue: @escaping @MainActor @Sendable (TrackRow) -> Void
    ) {
        self.playNow = playNow
        self.enqueue = enqueue
    }

    /// 何もしない default。 AUD-6 未統合時のフォールバック。
    public static let noop = LibraryTrackActions(
        playNow: { _ in },
        enqueue: { _ in }
    )
}
