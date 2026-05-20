import Foundation
import GRDB

/// `~/Library/Application Support/Audova/library.sqlite` を default 配置にしたライブラリ DB の open / migration。
///
/// テスト等で in-memory / 任意ファイルを使いたい場合は `inMemory` / `file(URL)` を渡す。
public struct LibraryDatabase: Sendable {
    public enum Location: Sendable {
        /// `~/Library/Application Support/Audova/library.sqlite`
        case applicationSupport
        /// 指定 URL に SQLite ファイルを作る。
        case file(URL)
        /// 揮発性 in-memory DB (= test 用)。
        case inMemory
    }

    public let dbPool: DatabasePool

    /// `Location` を解決して `DatabasePool` を open し、 migration を最新まで適用する。
    public static func open(_ location: Location = .applicationSupport) throws -> LibraryDatabase {
        let pool: DatabasePool
        switch location {
        case .applicationSupport:
            let url = try defaultDatabaseURL()
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            pool = try DatabasePool(path: url.path)
        case .file(let url):
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            pool = try DatabasePool(path: url.path)
        case .inMemory:
            // DatabasePool は file-based のみ。 in-memory が必要な場合は DatabaseQueue を返す API も検討したが、
            // テストでも同じ Pool API を使えた方が分岐が減るので、 一意な temp file で代用する。
            let tmp = FileManager.default.temporaryDirectory
                .appendingPathComponent("audova-test-\(UUID().uuidString).sqlite")
            pool = try DatabasePool(path: tmp.path)
        }
        try migrator.migrate(pool)
        return LibraryDatabase(dbPool: pool)
    }

    /// macOS 標準の Application Support 配下の DB ファイル URL。
    public static func defaultDatabaseURL() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return base.appendingPathComponent("Audova", isDirectory: true)
            .appendingPathComponent("library.sqlite")
    }

    // MARK: migration

    static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()

        m.registerMigration("v1_initial") { db in
            try db.create(table: "artists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull().indexed()
                t.column("name_sort", .text).notNull().indexed()
                t.uniqueKey(["name"])
            }

            try db.create(table: "albums") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("title", .text).notNull()
                t.column("artist_id", .integer)
                    .references("artists", onDelete: .setNull)
                    .indexed()
                t.column("year", .integer)
                t.column("cover_art_path", .text)
                // 同名アルバムでも artist が違えば別アルバム。
                t.uniqueKey(["title", "artist_id"])
            }

            try db.create(table: "tracks") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("path", .text).notNull().unique()
                t.column("title", .text)
                t.column("artist_id", .integer)
                    .references("artists", onDelete: .setNull)
                    .indexed()
                t.column("album_id", .integer)
                    .references("albums", onDelete: .setNull)
                    .indexed()
                t.column("track_no", .integer)
                t.column("disc_no", .integer)
                t.column("year", .integer)
                t.column("genre", .text)
                t.column("duration_ms", .integer)
                t.column("sample_rate", .double)
                t.column("bit_depth", .integer)
                t.column("codec", .text).notNull()
                t.column("file_size", .integer).notNull()
                t.column("mtime", .double).notNull()        // since 1970
                t.column("added_at", .double).notNull()     // since 1970
            }

            // FTS5: title / artist / album を 1 行にまとめて検索する。
            // rowid を `tracks.id` と揃え、 upsert / delete 時に手動で同期する。
            // contentless (`content=''`) は DELETE 不可で扱いに癖があるため、 自前テーブルに本文を保持する素直な形を採用。
            try db.execute(sql: """
                CREATE VIRTUAL TABLE tracks_fts USING fts5(
                    title,
                    artist,
                    album,
                    tokenize='unicode61 remove_diacritics 2'
                )
            """)
        }

        m.registerMigration("v2_playlists") { db in
            try db.create(table: "playlists") { t in
                t.autoIncrementedPrimaryKey("id")
                t.column("name", .text).notNull()
                t.column("created_at", .double).notNull()    // since 1970
                t.column("sort_order", .integer).notNull()
            }

            try db.create(table: "playlist_tracks") { t in
                t.column("playlist_id", .integer).notNull()
                    .references("playlists", onDelete: .cascade)
                    .indexed()
                t.column("track_id", .integer).notNull()
                    .references("tracks", onDelete: .cascade)
                    .indexed()
                t.column("position", .integer).notNull()
                t.primaryKey(["playlist_id", "track_id"])
            }

            try db.create(index: "idx_playlist_tracks_pos", on: "playlist_tracks", columns: ["playlist_id", "position"])
        }

        return m
    }
}
