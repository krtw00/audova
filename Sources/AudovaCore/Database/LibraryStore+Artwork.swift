import Foundation
import GRDB

/// `LibraryStore` のアートワーク関連 DB 操作。
///
/// 既存の `LibraryStore.swift` / `LibraryStore+Queries.swift` / `LibraryStore+Playlists.swift`
/// と責務を分けるため別ファイルにした。 `dbPool.write` ラップで統一している。
extension LibraryStore {
    /// album の `cover_art_path` を更新する。 `nil` を渡すとカラムを NULL にリセットする。
    public func setCoverArtPath(_ path: String?, forAlbumId id: Int64) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE albums SET cover_art_path = ? WHERE id = ?",
                arguments: [path, id]
            )
        }
    }

    /// album の `cover_art_path` を取得する。 `id` が nil / 該当なし / 未設定なら `nil`。
    /// 再生キュー構築時に現在曲のアートを引くために使う (= UI 層から呼ぶ)。
    public func coverArtPath(forAlbumId id: Int64?) throws -> String? {
        guard let id else { return nil }
        return try database.dbPool.read { db in
            try Album.fetchOne(db, key: id)?.coverArtPath
        }
    }
}
