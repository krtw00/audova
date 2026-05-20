import XCTest
import GRDB
@testable import AudovaCore

/// AUD-8 第 1 段: playlists / playlist_tracks の DB schema + Record 型 (= migration v2) を検証する。
///
/// query / mutation API (= LibraryStore+Playlists) は後続 commit のため、 ここでは
/// migration が通ること + Record の insert/fetch が往復することだけを確認する。
final class LibraryStorePlaylistsTests: XCTestCase {
    // MARK: - migration

    func testPlaylistTablesExistAfterMigration() throws {
        let db = try LibraryDatabase.open(.inMemory)
        try db.dbPool.read { conn in
            let tables: [String] = try String.fetchAll(
                conn,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("playlists"))
            XCTAssertTrue(tables.contains("playlist_tracks"))
        }
    }

    // MARK: - Playlist record

    func testInsertAndFetchPlaylist() throws {
        let db = try LibraryDatabase.open(.inMemory)
        let createdAt = Date(timeIntervalSince1970: 1_600_000_000).timeIntervalSince1970

        let inserted = try db.dbPool.write { conn -> Playlist in
            var playlist = Playlist(name: "Favorites", createdAt: createdAt, sortOrder: 0)
            try playlist.insert(conn)
            return playlist
        }
        let id = try XCTUnwrap(inserted.id)

        let fetched = try db.dbPool.read { conn in
            try Playlist.fetchOne(conn, key: id)
        }
        let row = try XCTUnwrap(fetched)
        XCTAssertEqual(row.name, "Favorites")
        XCTAssertEqual(row.createdAt, createdAt)
        XCTAssertEqual(row.sortOrder, 0)
    }

    // MARK: - PlaylistTrack record

    func testInsertPlaylistTrack() throws {
        let db = try LibraryDatabase.open(.inMemory)
        let store = LibraryStore(database: db)

        // track を 1 件用意する。
        try store.upsert(tracks: [Self.makeTrack(path: "/a/01.flac", title: "Foo", artist: "A", album: "X")])
        let track = try XCTUnwrap(try store.track(byPath: "/a/01.flac"))
        let trackId = try XCTUnwrap(track.id)

        let createdAt = Date(timeIntervalSince1970: 1_600_000_000).timeIntervalSince1970
        let playlistId = try db.dbPool.write { conn -> Int64 in
            var playlist = Playlist(name: "Mix", createdAt: createdAt, sortOrder: 0)
            try playlist.insert(conn)
            let pid = try XCTUnwrap(playlist.id)
            var entry = PlaylistTrack(playlistId: pid, trackId: trackId, position: 0)
            try entry.insert(conn)
            return pid
        }

        let entries = try db.dbPool.read { conn in
            try PlaylistTrack.filter(Column("playlist_id") == playlistId).fetchAll(conn)
        }
        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries.first?.trackId, trackId)
        XCTAssertEqual(entries.first?.position, 0)
    }

    // MARK: - helpers

    private static func makeTrack(
        path: String,
        title: String? = nil,
        artist: String? = nil,
        album: String? = nil,
        year: Int? = nil,
        trackNo: Int? = nil
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: path),
            codec: .flac,
            fileSize: 1024,
            modificationDate: Date(timeIntervalSince1970: 1_500_000_000),
            title: title,
            artist: artist,
            albumTitle: album,
            year: year,
            trackNumber: trackNo,
            duration: 200.0,
            sampleRate: 44100,
            bitDepth: 16,
            channelCount: 2
        )
    }
}
