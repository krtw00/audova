import UniformTypeIdentifiers
import Foundation

/// アプリ内 D&D で trackId 配列を運ぶ独自 UTType。
/// ライブラリ曲行 → プレイリスト行への D&D 専用。 外部 app とのやり取りには使わない。
extension UTType {
    /// アプリ内 track ID リスト (= JSON 配列の文字列) を表す独自型。
    static let audovaTrackIds = UTType(exportedAs: "dev.codenica.audova.track-ids")
}

/// D&D payload のエンコード / デコードを集約するユーティリティ。
enum TrackDragPayload {
    /// `[Int64]` → JSON 文字列 (= NSItemProvider のバイト列として渡す)。
    static func encode(_ trackIds: [Int64]) -> Data? {
        try? JSONEncoder().encode(trackIds)
    }

    /// JSON 文字列 → `[Int64]`。
    static func decode(_ data: Data) -> [Int64]? {
        try? JSONDecoder().decode([Int64].self, from: data)
    }
}
