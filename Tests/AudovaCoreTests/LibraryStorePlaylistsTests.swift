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

    // MARK: - playlist CRUD (LibraryStore+Playlists)

    func testCreateRenameDeletePlaylist() throws {
        let store = try Self.makeStore()
        let now = Date(timeIntervalSince1970: 1_600_000_000)

        let first = try store.createPlaylist(name: "First", now: now)
        let second = try store.createPlaylist(name: "Second", now: now)
        XCTAssertEqual(first.sortOrder, 0)
        XCTAssertEqual(second.sortOrder, 1)
        XCTAssertEqual(first.createdAt, now.timeIntervalSince1970)

        let firstId = try XCTUnwrap(first.id)
        try store.renamePlaylist(id: firstId, to: "First Renamed")

        var all = try store.allPlaylists()
        XCTAssertEqual(all.map(\.name), ["First Renamed", "Second"])

        try store.deletePlaylist(id: firstId)
        all = try store.allPlaylists()
        XCTAssertEqual(all.map(\.name), ["Second"])
    }

    func testDeletePlaylistCascadesTracks() throws {
        let store = try Self.makeStore()
        let trackId = try Self.insertTrack(store, path: "/a/01.flac")
        let playlist = try store.createPlaylist(name: "Mix")
        let pid = try XCTUnwrap(playlist.id)
        try store.addTracks([trackId], toPlaylistId: pid)
        XCTAssertEqual(try store.trackCount(inPlaylistId: pid), 1)

        try store.deletePlaylist(id: pid)
        XCTAssertEqual(try store.trackCount(inPlaylistId: pid), 0)
    }

    func testReorderPlaylists() throws {
        let store = try Self.makeStore()
        let a = try XCTUnwrap(try store.createPlaylist(name: "A").id)
        let b = try XCTUnwrap(try store.createPlaylist(name: "B").id)
        let c = try XCTUnwrap(try store.createPlaylist(name: "C").id)

        try store.reorderPlaylists(orderedIds: [c, a, b])
        XCTAssertEqual(try store.allPlaylists().map(\.name), ["C", "A", "B"])
    }

    // MARK: - playlist contents (LibraryStore+Playlists)

    func testAddTracksIgnoresDuplicates() throws {
        let store = try Self.makeStore()
        let t1 = try Self.insertTrack(store, path: "/a/01.flac")
        let t2 = try Self.insertTrack(store, path: "/a/02.flac")
        let pid = try XCTUnwrap(try store.createPlaylist(name: "Mix").id)

        try store.addTracks([t1, t2], toPlaylistId: pid)
        // 重複は黙って弾かれる (= INSERT OR IGNORE)。 t3 だけ末尾に追加される。
        let t3 = try Self.insertTrack(store, path: "/a/03.flac")
        try store.addTracks([t1, t2, t3], toPlaylistId: pid)

        XCTAssertEqual(try store.trackCount(inPlaylistId: pid), 3)
        let ids = try store.tracks(inPlaylistId: pid).compactMap(\.id)
        XCTAssertEqual(ids, [t1, t2, t3])
    }

    func testTracksReturnInPositionOrder() throws {
        let store = try Self.makeStore()
        let t1 = try Self.insertTrack(store, path: "/a/01.flac")
        let t2 = try Self.insertTrack(store, path: "/a/02.flac")
        let t3 = try Self.insertTrack(store, path: "/a/03.flac")
        let pid = try XCTUnwrap(try store.createPlaylist(name: "Mix").id)

        try store.addTracks([t3, t1, t2], toPlaylistId: pid)
        XCTAssertEqual(try store.tracks(inPlaylistId: pid).compactMap(\.id), [t3, t1, t2])
    }

    func testRemoveTracksRepacksPositions() throws {
        let store = try Self.makeStore()
        let t1 = try Self.insertTrack(store, path: "/a/01.flac")
        let t2 = try Self.insertTrack(store, path: "/a/02.flac")
        let t3 = try Self.insertTrack(store, path: "/a/03.flac")
        let pid = try XCTUnwrap(try store.createPlaylist(name: "Mix").id)
        try store.addTracks([t1, t2, t3], toPlaylistId: pid)

        // 真ん中を削除しても position が 0..n に詰め直される。
        try store.removeTracks([t2], fromPlaylistId: pid)
        XCTAssertEqual(try store.tracks(inPlaylistId: pid).compactMap(\.id), [t1, t3])

        let positions = try store.database.dbPool.read { conn in
            try Int.fetchAll(
                conn,
                sql: "SELECT position FROM playlist_tracks WHERE playlist_id = ? ORDER BY position",
                arguments: [pid]
            )
        }
        XCTAssertEqual(positions, [0, 1])
    }

    func testReorderTracks() throws {
        let store = try Self.makeStore()
        let t1 = try Self.insertTrack(store, path: "/a/01.flac")
        let t2 = try Self.insertTrack(store, path: "/a/02.flac")
        let t3 = try Self.insertTrack(store, path: "/a/03.flac")
        let pid = try XCTUnwrap(try store.createPlaylist(name: "Mix").id)
        try store.addTracks([t1, t2, t3], toPlaylistId: pid)

        try store.reorderTracks(inPlaylistId: pid, orderedTrackIds: [t3, t2, t1])
        XCTAssertEqual(try store.tracks(inPlaylistId: pid).compactMap(\.id), [t3, t2, t1])
    }

    // MARK: - helpers

    private static func makeStore() throws -> LibraryStore {
        let db = try LibraryDatabase.open(.inMemory)
        return LibraryStore(database: db)
    }

    /// track を 1 件 upsert して id を返す。
    private static func insertTrack(_ store: LibraryStore, path: String) throws -> Int64 {
        try store.upsert(tracks: [makeTrack(path: path, title: path, artist: "A", album: "X")])
        let track = try XCTUnwrap(try store.track(byPath: path))
        return try XCTUnwrap(track.id)
    }

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
