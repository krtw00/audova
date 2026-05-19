import XCTest
import GRDB
@testable import AudovaCore

final class LibraryDatabaseTests: XCTestCase {
    // MARK: - migration / open

    func testOpensInMemoryAndMigrationApplied() throws {
        let db = try LibraryDatabase.open(.inMemory)
        try db.dbPool.read { conn in
            let tables: [String] = try String.fetchAll(
                conn,
                sql: "SELECT name FROM sqlite_master WHERE type='table' ORDER BY name"
            )
            XCTAssertTrue(tables.contains("artists"))
            XCTAssertTrue(tables.contains("albums"))
            XCTAssertTrue(tables.contains("tracks"))
            XCTAssertTrue(tables.contains("tracks_fts"))
        }
    }

    func testReopeningSameFileSkipsMigration() throws {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-reopen-\(UUID().uuidString).sqlite")
        defer { try? FileManager.default.removeItem(at: tmp) }

        // 1 度 open / 1 行 insert
        do {
            let db = try LibraryDatabase.open(.file(tmp))
            let store = LibraryStore(database: db)
            try store.upsert(tracks: [Self.makeTrack(path: "/a/x.flac", title: "X", artist: "A", album: "Al")])
            XCTAssertEqual(try store.trackCount(), 1)
        }
        // 2 度目 open: migration が二重適用されず、 既存データが残る
        do {
            let db = try LibraryDatabase.open(.file(tmp))
            let store = LibraryStore(database: db)
            XCTAssertEqual(try store.trackCount(), 1)
        }
    }

    // MARK: - upsert

    func testUpsertInsertsArtistsAlbumsAndTracks() throws {
        let store = try Self.makeStore()
        let tracks: [Track] = [
            Self.makeTrack(path: "/m/a/01.flac", title: "S1", artist: "Artist A", album: "Album 1", trackNo: 1),
            Self.makeTrack(path: "/m/a/02.flac", title: "S2", artist: "Artist A", album: "Album 1", trackNo: 2),
            Self.makeTrack(path: "/m/b/01.flac", title: "T1", artist: "Artist B", album: "Album 2", trackNo: 1),
        ]
        let written = try store.upsert(tracks: tracks)
        XCTAssertEqual(written, 3)
        XCTAssertEqual(try store.trackCount(), 3)
        XCTAssertEqual(try store.artistCount(), 2)
        XCTAssertEqual(try store.albumCount(), 2)
    }

    func testUpsertSamePathUpdatesInPlaceAndPreservesAddedAt() throws {
        let store = try Self.makeStore()
        let originalAddedAt = Date(timeIntervalSince1970: 1_000_000)
        try store.upsert(
            tracks: [Self.makeTrack(path: "/m/a.flac", title: "Old", artist: "A", album: "X")],
            now: originalAddedAt
        )
        let countBefore = try store.trackCount()
        XCTAssertEqual(countBefore, 1)

        let updateTime = Date(timeIntervalSince1970: 2_000_000)
        try store.upsert(
            tracks: [Self.makeTrack(path: "/m/a.flac", title: "New", artist: "A", album: "X")],
            now: updateTime
        )
        XCTAssertEqual(try store.trackCount(), 1, "same path should update in place")

        let row = try store.database.dbPool.read { db in
            try TrackRow.filter(Column("path") == "/m/a.flac").fetchOne(db)
        }
        XCTAssertEqual(row?.title, "New")
        XCTAssertEqual(row?.addedAt, originalAddedAt.timeIntervalSince1970,
                       "addedAt should be preserved across upsert")
    }

    func testUpsertReusesArtistAndAlbumRows() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/m/01.flac", title: "S1", artist: "A", album: "X", trackNo: 1),
            Self.makeTrack(path: "/m/02.flac", title: "S2", artist: "A", album: "X", trackNo: 2),
            Self.makeTrack(path: "/m/03.flac", title: "S3", artist: "A", album: "X", trackNo: 3),
        ])
        XCTAssertEqual(try store.artistCount(), 1)
        XCTAssertEqual(try store.albumCount(), 1)
    }

    func testUpsertSameAlbumTitleDifferentArtistsCreatesTwoAlbums() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a/01.flac", title: "S", artist: "A", album: "Greatest Hits"),
            Self.makeTrack(path: "/b/01.flac", title: "T", artist: "B", album: "Greatest Hits"),
        ])
        XCTAssertEqual(try store.artistCount(), 2)
        XCTAssertEqual(try store.albumCount(), 2, "same album title with different artists must be 2 rows")
    }

    func testUpsertNilArtistAndAlbumDoesNotCreateRows() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/orphan.flac", title: "Orphan", artist: nil, album: nil),
        ])
        XCTAssertEqual(try store.trackCount(), 1)
        XCTAssertEqual(try store.artistCount(), 0)
        XCTAssertEqual(try store.albumCount(), 0)
    }

    // MARK: - query API

    func testAllArtistsSortedByNameSort() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/c.flac", artist: "Charlie", album: "X"),
            Self.makeTrack(path: "/a.flac", artist: "alpha",   album: "X"),
            Self.makeTrack(path: "/b.flac", artist: "Bravo",   album: "X"),
        ])
        let names = try store.allArtists().map(\.name)
        XCTAssertEqual(names, ["alpha", "Bravo", "Charlie"])
    }

    func testAlbumsByArtistAndTracksByAlbum() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a1.flac", title: "T1", artist: "A", album: "First",  year: 2020, trackNo: 2),
            Self.makeTrack(path: "/a2.flac", title: "T2", artist: "A", album: "First",  year: 2020, trackNo: 1),
            Self.makeTrack(path: "/a3.flac", title: "T3", artist: "A", album: "Second", year: 2022, trackNo: 1),
        ])
        let artist = try XCTUnwrap(try store.allArtists().first { $0.name == "A" })
        let artistId = try XCTUnwrap(artist.id)

        let albums = try store.albums(byArtistId: artistId)
        XCTAssertEqual(albums.map(\.title), ["First", "Second"])
        let firstAlbumId = try XCTUnwrap(albums[0].id)

        let tracks = try store.tracks(byAlbumId: firstAlbumId)
        XCTAssertEqual(tracks.map(\.title), ["T2", "T1"], "tracks should be ordered by trackNo")
    }

    // MARK: - FTS

    func testFTSQueryBuilderEscapesAndAppendsPrefixWildcard() {
        XCTAssertEqual(LibraryStore.makeFTSQuery("hello"), "\"hello\"*")
        XCTAssertEqual(LibraryStore.makeFTSQuery("hello world"), "\"hello\"* \"world\"*")
        XCTAssertEqual(LibraryStore.makeFTSQuery("  spaced   tokens  "), "\"spaced\"* \"tokens\"*")
        XCTAssertEqual(LibraryStore.makeFTSQuery(""), "")
        // double quote escape
        XCTAssertEqual(LibraryStore.makeFTSQuery("he\"llo"), "\"he\"\"llo\"*")
    }

    func testFTSSearchByTitleArtistAlbum() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/1.flac", title: "Midnight Run",   artist: "Aurora",  album: "Lights"),
            Self.makeTrack(path: "/2.flac", title: "Sunrise",        artist: "Aurora",  album: "Lights"),
            Self.makeTrack(path: "/3.flac", title: "Lights Out",     artist: "Other",   album: "Other Album"),
        ])

        // title prefix
        let byTitle = try store.search("Mid")
        XCTAssertEqual(byTitle.map { $0.track.path }, ["/1.flac"])

        // artist exact
        let byArtist = try store.search("Aurora")
        XCTAssertEqual(Set(byArtist.map { $0.track.path }), ["/1.flac", "/2.flac"])

        // album substring (= prefix の "Lights" は title="Lights Out" にも刺さる)
        let byAlbum = try store.search("Lights")
        XCTAssertEqual(byAlbum.count, 3, "album=Lights should match 2 + title=Lights Out should match 1")
    }

    func testFTSReflectsUpsertUpdates() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/x.flac", title: "Original Title", artist: "A", album: "Z"),
        ])
        XCTAssertEqual(try store.search("Original").count, 1)
        XCTAssertEqual(try store.search("Renamed").count, 0)

        try store.upsert(tracks: [
            Self.makeTrack(path: "/x.flac", title: "Renamed Track", artist: "A", album: "Z"),
        ])
        XCTAssertEqual(try store.search("Original").count, 0, "FTS index should drop the old title on update")
        XCTAssertEqual(try store.search("Renamed").count, 1)
    }

    func testEmptySearchReturnsNoRows() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a.flac", title: "Whatever", artist: "A", album: "X"),
        ])
        XCTAssertEqual(try store.search("").count, 0)
        XCTAssertEqual(try store.search("    ").count, 0)
    }

    // MARK: - bulk insertion (= 1k 件 fixture)

    func testInsertsThousandTracks() throws {
        let store = try Self.makeStore()
        let tracks: [Track] = (0..<1000).map { i in
            Self.makeTrack(
                path: "/bulk/\(i).flac",
                title: "Title \(i)",
                artist: "Artist \(i % 50)",
                album: "Album \(i % 100)",
                trackNo: (i % 20) + 1
            )
        }
        try store.upsert(tracks: tracks)
        XCTAssertEqual(try store.trackCount(), 1000)
        XCTAssertEqual(try store.artistCount(), 50)
        XCTAssertEqual(try store.albumCount(), 100)

        // 検索もちゃんと刺さるか軽くスポット確認
        let hits = try store.search("Title 999")
        XCTAssertGreaterThanOrEqual(hits.count, 1)
    }

    // MARK: - helpers

    private static func makeStore() throws -> LibraryStore {
        let db = try LibraryDatabase.open(.inMemory)
        return LibraryStore(database: db)
    }

    /// `Track` を最小限の値で組み立てるテスト用 helper。 codec / fileSize / mtime にはダミー値を入れる。
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
