import AudovaCore

/// SwiftUI `Table` / `List` で行を一意識別するために `Identifiable` を後付けする。
///
/// 拡張は executable target 側に置き、 `AudovaCore` API は SwiftUI 依存を持たない状態を維持する。
///
/// - `TrackRow.id` は DB rowid 由来で `Int64?` (= optional)。 永続化後は必ず non-nil なので、
///   SwiftUI 用の自動合成に任せて `Optional<Int64>` を `ID` とする。 値が `nil` のままの行は selection
///   できないが、 ライブラリビューに出るのは upsert 済み (= id 確定) の行だけなので問題ない。
/// - `TrackSearchHit` は `Identifiable` を未持ちなので、 内包 `track.path` を id にして衝突回避。
extension TrackRow: Identifiable {}

extension TrackSearchHit: Identifiable {
    public var id: String { track.path }
}
