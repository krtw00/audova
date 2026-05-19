import XCTest
import GRDB
@testable import AudovaCore

/// `LibraryStore+Queries.swift` の追加クエリ (= ライブラリ画面のフラットモード用) を検証する。
///
/// 既存の `LibraryDatabaseTests.swift` (= upsert / FTS / 階層クエリ) と棲み分けるため別ファイルにした。
final class LibraryStoreQueriesTests: XCTestCase {
    // MARK: - allAlbums

    func testAllAlbumsReturnsEverything() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a/01.flac", artist: "Artist A", album: "Album A1", year: 2020),
            Self.makeTrack(path: "/a/02.flac", artist: "Artist A", album: "Album A2", year: 2021),
            Self.makeTrack(path: "/b/01.flac", artist: "Artist B", album: "Album B1", year: 2019),
        ])
        let albums = try store.allAlbums()
        XCTAssertEqual(albums.count, 3)
        XCTAssertEqual(Set(albums.map(\.title)), ["Album A1", "Album A2", "Album B1"])
    }

    func testAllAlbumsIsEmptyWhenNoTracks() throws {
        let store = try Self.makeStore()
        XCTAssertEqual(try store.allAlbums().count, 0)
    }

    // MARK: - allTracks

    func testAllTracksReturnsEverything() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/z.flac", artist: "Z",   album: "Y",  trackNo: 1),
            Self.makeTrack(path: "/a/01.flac", artist: "A", album: "X", trackNo: 1),
            Self.makeTrack(path: "/a/02.flac", artist: "A", album: "X", trackNo: 2),
        ])
        let tracks = try store.allTracks()
        XCTAssertEqual(tracks.count, 3)
        XCTAssertEqual(Set(tracks.map(\.path)), ["/z.flac", "/a/01.flac", "/a/02.flac"])
    }

    /// 同じアルバム内では disc/track 昇順で並ぶことを保証する (= 表示時に「アルバムごとにまとまる」 前提)。
    func testAllTracksOrdersByDiscTrackWithinSameAlbum() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a/03.flac", artist: "A", album: "X", trackNo: 3),
            Self.makeTrack(path: "/a/01.flac", artist: "A", album: "X", trackNo: 1),
            Self.makeTrack(path: "/a/02.flac", artist: "A", album: "X", trackNo: 2),
        ])
        let tracks = try store.allTracks()
        XCTAssertEqual(tracks.map(\.path), ["/a/01.flac", "/a/02.flac", "/a/03.flac"])
    }

    // MARK: - tracks(byArtistId:)

    func testTracksByArtistReturnsOnlyThatArtist() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a/01.flac", artist: "A", album: "X", trackNo: 1),
            Self.makeTrack(path: "/a/02.flac", artist: "A", album: "X", trackNo: 2),
            Self.makeTrack(path: "/b/01.flac", artist: "B", album: "Y", trackNo: 1),
        ])
        let artist = try XCTUnwrap(try store.allArtists().first { $0.name == "A" })
        let artistId = try XCTUnwrap(artist.id)
        let tracks = try store.tracks(byArtistId: artistId)
        XCTAssertEqual(tracks.count, 2)
        XCTAssertTrue(tracks.allSatisfy { $0.artistId == artistId })
    }

    // MARK: - track(byPath:)

    func testTrackByPathReturnsRow() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/a/01.flac", title: "Foo", artist: "A", album: "X"),
        ])
        let row = try XCTUnwrap(try store.track(byPath: "/a/01.flac"))
        XCTAssertEqual(row.title, "Foo")
        XCTAssertNil(try store.track(byPath: "/nonexistent.flac"))
    }

    // MARK: - helpers

    private static func makeStore() throws -> LibraryStore {
        let db = try LibraryDatabase.open(.inMemory)
        return LibraryStore(database: db)
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
