import Foundation
import GRDB

/// `LibraryStore` の静的プレイリスト用 query / mutation API (= AUD-8 第 2 段)。
///
/// 既存の `LibraryStore.swift` (= upsert / FTS) や `LibraryStore+Queries.swift` (= ライブラリ画面)
/// と責務を分けるため別ファイルにした。 すべて同期 API で `dbPool.read` / `dbPool.write` ラップする。
extension LibraryStore {
    // MARK: - playlist CRUD

    /// 全プレイリストを並び順 (= sort_order → id) で返す。
    public func allPlaylists() throws -> [Playlist] {
        try database.dbPool.read { db in
            try Playlist.order(Column("sort_order").asc, Column("id").asc).fetchAll(db)
        }
    }

    /// 新規プレイリストを作る。 `sort_order` は既存の最大値 + 1 (= 末尾追加)。
    @discardableResult
    public func createPlaylist(name: String, now: Date = Date()) throws -> Playlist {
        try database.dbPool.write { db in
            let maxOrder = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(sort_order), -1) FROM playlists"
            ) ?? -1
            var playlist = Playlist(
                name: name,
                createdAt: now.timeIntervalSince1970,
                sortOrder: maxOrder + 1
            )
            try playlist.insert(db)
            return playlist
        }
    }

    /// プレイリスト名を変更する。
    public func renamePlaylist(id: Int64, to name: String) throws {
        try database.dbPool.write { db in
            try db.execute(
                sql: "UPDATE playlists SET name = ? WHERE id = ?",
                arguments: [name, id]
            )
        }
    }

    /// プレイリストを削除する。 `playlist_tracks` は ON DELETE CASCADE で同時に消える。
    public func deletePlaylist(id: Int64) throws {
        try database.dbPool.write { db in
            _ = try Playlist.deleteOne(db, key: id)
        }
    }

    /// 渡された順でプレイリストの `sort_order` を 0..n に再採番する。
    public func reorderPlaylists(orderedIds: [Int64]) throws {
        try database.dbPool.write { db in
            for (index, id) in orderedIds.enumerated() {
                try db.execute(
                    sql: "UPDATE playlists SET sort_order = ? WHERE id = ?",
                    arguments: [index, id]
                )
            }
        }
    }

    // MARK: - playlist contents queries

    /// 指定プレイリストのトラックを `position` 昇順で返す。
    public func tracks(inPlaylistId id: Int64) throws -> [TrackRow] {
        try database.dbPool.read { db in
            let sql = """
                SELECT tracks.*
                FROM playlist_tracks
                JOIN tracks ON tracks.id = playlist_tracks.track_id
                WHERE playlist_tracks.playlist_id = ?
                ORDER BY playlist_tracks.position
            """
            return try TrackRow.fetchAll(db, sql: sql, arguments: [id])
        }
    }

    /// 指定プレイリストのトラック件数。
    public func trackCount(inPlaylistId id: Int64) throws -> Int {
        try database.dbPool.read { db in
            try PlaylistTrack.filter(Column("playlist_id") == id).fetchCount(db)
        }
    }

    // MARK: - playlist contents mutations

    /// トラックをプレイリスト末尾に追加する。 現在の `MAX(position) + 1` から連番を振る。
    /// 複合主キー重複 (= 既にメンバ) は `INSERT OR IGNORE` で黙って弾き、 position も消費しない。
    public func addTracks(_ trackIds: [Int64], toPlaylistId id: Int64) throws {
        guard !trackIds.isEmpty else { return }
        try database.dbPool.write { db in
            var nextPosition = try Int.fetchOne(
                db,
                sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM playlist_tracks WHERE playlist_id = ?",
                arguments: [id]
            ) ?? 0
            for trackId in trackIds {
                var entry = PlaylistTrack(playlistId: id, trackId: trackId, position: nextPosition)
                try entry.insert(db, onConflict: .ignore)
                // 実際に行が増えたときだけ position を消費する (= 重複 ignore 時は据え置き)。
                if db.changesCount > 0 {
                    nextPosition += 1
                }
            }
        }
    }

    /// トラックをプレイリストから取り除き、 残りの `position` を 0..n に詰め直す (= 1 トランザクション内)。
    public func removeTracks(_ trackIds: [Int64], fromPlaylistId id: Int64) throws {
        guard !trackIds.isEmpty else { return }
        try database.dbPool.write { db in
            try PlaylistTrack
                .filter(Column("playlist_id") == id && trackIds.contains(Column("track_id")))
                .deleteAll(db)
            try Self.repackPositions(playlistId: id, db: db)
        }
    }

    /// 渡された順でプレイリスト内の `position` を 0..n に再採番する (= 1 トランザクション内)。
    public func reorderTracks(inPlaylistId id: Int64, orderedTrackIds: [Int64]) throws {
        try database.dbPool.write { db in
            for (index, trackId) in orderedTrackIds.enumerated() {
                try db.execute(
                    sql: "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?",
                    arguments: [index, id, trackId]
                )
            }
        }
    }

    // MARK: - helpers

    /// 既存の `position` 順を保ったまま 0..n に詰め直す。
    private static func repackPositions(playlistId: Int64, db: Database) throws {
        let trackIds = try Int64.fetchAll(
            db,
            sql: "SELECT track_id FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
            arguments: [playlistId]
        )
        for (index, trackId) in trackIds.enumerated() {
            try db.execute(
                sql: "UPDATE playlist_tracks SET position = ? WHERE playlist_id = ? AND track_id = ?",
                arguments: [index, playlistId, trackId]
            )
        }
    }
}
