import Foundation
import GRDB

extension LibraryStore {
    /// スキャン対象フォルダ配下の既存トラックの (mtime, fileSize) を path キーで返す（未変更判定用）。
    public func fileSignatures(under folder: URL) throws -> [String: FileSignature] {
        let prefix = folder.path + "/"
        return try database.dbPool.read { db in
            let rows = try TrackRow.fetchAll(db)
            var map: [String: FileSignature] = [:]
            for r in rows where r.path.hasPrefix(prefix) {
                map[r.path] = FileSignature(mtime: r.mtime, fileSize: r.fileSize)
            }
            return map
        }
    }

    /// 差分スキャン結果を 1 トランザクションで反映:
    /// 変更分 upsert → フォルダ配下で消えたトラック削除 → 孤立 album/artist 削除。
    public func applyScan(_ result: ScanResult, folder: URL, now: Date = Date()) throws -> ScanOutcome {
        let prefix = folder.path + "/"
        let deleted: Int = try database.dbPool.write { db in
            // 1. 変更/新規 upsert
            for track in result.tracks {
                try Self.upsertOne(track: track, now: now, db: db)
            }
            // 2. フォルダ配下で今回見つからなかった既存トラックを削除
            //    (FTS も同期、 playlist_tracks は FK cascade で消える)
            let underFolder = try TrackRow.fetchAll(db).filter { $0.path.hasPrefix(prefix) }
            let toDelete = underFolder.filter { !result.seenPaths.contains($0.path) }
            for row in toDelete {
                if let id = row.id {
                    try db.execute(sql: "DELETE FROM tracks_fts WHERE rowid = ?", arguments: [id])
                }
                try row.delete(db)
            }
            // 3. 孤立クリーンアップ (順序重要: album を先に、 その後 artist)
            try db.execute(sql: """
                DELETE FROM albums
                WHERE id NOT IN (
                    SELECT album_id FROM tracks WHERE album_id IS NOT NULL
                )
            """)
            try db.execute(sql: """
                DELETE FROM artists
                WHERE id NOT IN (
                    SELECT artist_id FROM tracks WHERE artist_id IS NOT NULL
                )
                  AND id NOT IN (
                    SELECT artist_id FROM albums WHERE artist_id IS NOT NULL
                )
            """)
            return toDelete.count
        }
        return ScanOutcome(
            updated: result.tracks.count,
            skipped: result.unchangedPaths.count,
            deleted: deleted,
            warnings: result.warnings.count
        )
    }
}
