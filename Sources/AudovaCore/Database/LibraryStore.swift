import Foundation
import GRDB

/// `LibraryDatabase` の上に乗る upsert + query API。
///
/// 役割分担:
/// - スキーマ / migration は `LibraryDatabase`
/// - record 型は `Records.swift` (= `Artist` / `Album` / `TrackRow`)
/// - 本ファイルは「`Track` (= スキャナ出力) を DB に書く / 検索する」 だけに専念する
public struct LibraryStore: Sendable {
    public let database: LibraryDatabase

    public init(database: LibraryDatabase) {
        self.database = database
    }

    // MARK: - upsert

    /// スキャナ出力の `Track` 配列を 1 トランザクションで upsert する。
    /// path をキーに、 既存行は update、 新規行は insert。 関連 artist / album も同時に確保する。
    /// `addedAt` は既存行の値を尊重し、 新規行のみ `now` を入れる。
    @discardableResult
    public func upsert(tracks: [Track], now: Date = Date()) throws -> Int {
        try database.dbPool.write { db in
            var written = 0
            for track in tracks {
                try Self.upsertOne(track: track, now: now, db: db)
                written += 1
            }
            return written
        }
    }

    static func upsertOne(track: Track, now: Date, db: Database) throws {
        let artistId = try ensureArtistId(name: track.artist, db: db)
        let albumArtistId = try ensureArtistId(name: track.albumArtist ?? track.artist, db: db)
        let albumId = try ensureAlbumId(
            title: track.albumTitle,
            artistId: albumArtistId,
            year: track.year,
            db: db
        )

        let path = track.url.path
        let existing = try TrackRow.filter(Column("path") == path).fetchOne(db)

        var row = TrackRow(
            id: existing?.id,
            path: path,
            title: track.title,
            artistId: artistId,
            albumId: albumId,
            trackNo: track.trackNumber,
            discNo: track.discNumber,
            year: track.year,
            genre: track.genre,
            durationMs: track.duration.map { Int(($0 * 1000.0).rounded()) },
            sampleRate: track.sampleRate,
            bitDepth: track.bitDepth,
            codec: track.codec.rawValue,
            fileSize: track.fileSize,
            mtime: track.modificationDate.timeIntervalSince1970,
            addedAt: existing?.addedAt ?? now.timeIntervalSince1970
        )
        try row.save(db)

        // FTS index 更新: existing なら一旦消してから入れ直し (= rowid を tracks.id と同期させる)。
        guard let rowId = row.id else { return }
        if existing != nil {
            try db.execute(sql: "DELETE FROM tracks_fts WHERE rowid = ?", arguments: [rowId])
        }
        let artistName = try artistId.flatMap { try Artist.fetchOne(db, key: $0)?.name }
        let albumTitle = try albumId.flatMap { try Album.fetchOne(db, key: $0)?.title }
        try db.execute(
            sql: "INSERT INTO tracks_fts(rowid, title, artist, album) VALUES (?, ?, ?, ?)",
            arguments: [rowId, track.title ?? "", artistName ?? "", albumTitle ?? ""]
        )
    }

    /// nil / 空文字なら artists を作らず nil を返す。 既存 name はそのまま使い、 大文字小文字の揺れを統合しない (= Phase 2 以降の重複統合に委ねる)。
    private static func ensureArtistId(name: String?, db: Database) throws -> Int64? {
        guard let raw = name?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        if let existing = try Artist.filter(Column("name") == raw).fetchOne(db) {
            return existing.id
        }
        var a = Artist(name: raw, nameSort: normalizeSort(raw))
        try a.insert(db)
        return a.id
    }

    private static func ensureAlbumId(title: String?, artistId: Int64?, year: Int?, db: Database) throws -> Int64? {
        guard let raw = title?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else {
            return nil
        }
        // 同名アルバムでも artist が違えば別行 (= unique(title, artist_id))。
        let query: QueryInterfaceRequest<Album>
        if let artistId {
            query = Album.filter(Column("title") == raw && Column("artist_id") == artistId)
        } else {
            query = Album.filter(Column("title") == raw && Column("artist_id") == nil)
        }
        if let existing = try query.fetchOne(db) {
            return existing.id
        }
        var album = Album(title: raw, artistId: artistId, year: year, coverArtPath: nil)
        try album.insert(db)
        return album.id
    }

    /// sort 用に小文字化 + 前後空白除去するだけ (= 並び替え時の articles ("The ...") 除去等は Phase 2 以降)。
    private static func normalizeSort(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - basic queries

    /// 全アーティストを name_sort 昇順で返す。
    public func allArtists() throws -> [Artist] {
        try database.dbPool.read { db in
            try Artist.order(Column("name_sort").asc).fetchAll(db)
        }
    }

    /// 指定 artist のアルバムを year / title 昇順で返す。
    public func albums(byArtistId artistId: Int64) throws -> [Album] {
        try database.dbPool.read { db in
            try Album
                .filter(Column("artist_id") == artistId)
                .order(Column("year").ascNullsLast, Column("title").asc)
                .fetchAll(db)
        }
    }

    /// 指定アルバムのトラックを disc/track 昇順で返す。
    public func tracks(byAlbumId albumId: Int64) throws -> [TrackRow] {
        try database.dbPool.read { db in
            try TrackRow
                .filter(Column("album_id") == albumId)
                .order(
                    Column("disc_no").ascNullsLast,
                    Column("track_no").ascNullsLast,
                    Column("title").asc
                )
                .fetchAll(db)
        }
    }

    /// FTS5 incremental 検索。 各トークンに `*` を付けた prefix match で投げる。
    /// 空クエリなら空配列。 ユーザー入力は SQL 引用符等を escape して投げる。
    public func search(_ query: String, limit: Int = 200) throws -> [TrackSearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let ftsQuery = Self.makeFTSQuery(trimmed)
        guard !ftsQuery.isEmpty else { return [] }

        return try database.dbPool.read { db in
            let sql = """
                SELECT tracks.*,
                       artists.name AS _hit_artist_name,
                       albums.title AS _hit_album_title
                FROM tracks_fts
                JOIN tracks ON tracks.id = tracks_fts.rowid
                LEFT JOIN artists ON artists.id = tracks.artist_id
                LEFT JOIN albums  ON albums.id  = tracks.album_id
                WHERE tracks_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """
            let rows = try Row.fetchAll(db, sql: sql, arguments: [ftsQuery, limit])
            return try rows.map { row in
                let track = try TrackRow(row: row)
                let artistName: String? = row["_hit_artist_name"]
                let albumTitle: String? = row["_hit_album_title"]
                return TrackSearchHit(track: track, artistName: artistName, albumTitle: albumTitle)
            }
        }
    }

    /// FTS5 MATCH 用クエリを組み立てる。 各トークンを `"..."` で quote し、 末尾に `*` を付けて prefix 検索にする。
    /// ダブルクォートはエスケープ (= `""`)。 token 間は暗黙 AND。
    static func makeFTSQuery(_ input: String) -> String {
        let tokens = input
            .split(whereSeparator: { $0.isWhitespace })
            .map(String.init)
            .filter { !$0.isEmpty }
        guard !tokens.isEmpty else { return "" }
        return tokens.map { token in
            let escaped = token.replacingOccurrences(of: "\"", with: "\"\"")
            return "\"\(escaped)\"*"
        }.joined(separator: " ")
    }

    // MARK: - utility (test 用 / 進捗表示用)

    /// tracks の総件数。
    public func trackCount() throws -> Int {
        try database.dbPool.read { db in
            try TrackRow.fetchCount(db)
        }
    }

    /// artists の総件数。
    public func artistCount() throws -> Int {
        try database.dbPool.read { db in
            try Artist.fetchCount(db)
        }
    }

    /// albums の総件数。
    public func albumCount() throws -> Int {
        try database.dbPool.read { db in
            try Album.fetchCount(db)
        }
    }
}
