import XCTest
@testable import AudovaCore

/// `LibraryViewModel` の選択遷移 / 検索 / hook 委譲を検証する。 SwiftUI / @Observable は触らず、
/// 純粋なステート機械として検査する。
@MainActor
final class LibraryViewModelTests: XCTestCase {
    func testReloadAllPopulatesArtistsAlbumsAndTracksInFlatMode() throws {
        let model = try Self.makeModel()
        try model.store.upsert(tracks: [
            Self.makeTrack(path: "/a.flac", artist: "Alice", album: "A1"),
            Self.makeTrack(path: "/b.flac", artist: "Bob",   album: "B1"),
        ])
        model.reloadAll()
        XCTAssertEqual(model.artists.count, 2)
        XCTAssertEqual(model.albums.count, 2, "flat mode shows all albums")
        XCTAssertEqual(model.tracks.count, 2, "flat mode shows all tracks")
    }

    func testSelectingArtistNarrowsAlbumsAndTracks() throws {
        let model = try Self.makeModel()
        try model.store.upsert(tracks: [
            Self.makeTrack(path: "/a1.flac", artist: "Alice", album: "A1"),
            Self.makeTrack(path: "/a2.flac", artist: "Alice", album: "A2"),
            Self.makeTrack(path: "/b1.flac", artist: "Bob",   album: "B1"),
        ])
        model.reloadAll()

        let alice = try XCTUnwrap(model.artists.first { $0.name == "Alice" })
        model.selectedArtistId = alice.id

        XCTAssertEqual(model.albums.count, 2)
        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertNil(model.selectedAlbumId, "switching artist clears album selection")
    }

    func testSelectingAlbumNarrowsTracks() throws {
        let model = try Self.makeModel()
        try model.store.upsert(tracks: [
            Self.makeTrack(path: "/a1.flac", artist: "Alice", album: "A1", trackNo: 1),
            Self.makeTrack(path: "/a2.flac", artist: "Alice", album: "A1", trackNo: 2),
            Self.makeTrack(path: "/a3.flac", artist: "Alice", album: "A2", trackNo: 1),
        ])
        model.reloadAll()

        let alice = try XCTUnwrap(model.artists.first { $0.name == "Alice" })
        model.selectedArtistId = alice.id
        let a1 = try XCTUnwrap(model.albums.first { $0.title == "A1" })
        model.selectedAlbumId = a1.id

        XCTAssertEqual(model.tracks.count, 2)
        XCTAssertTrue(model.tracks.allSatisfy { $0.albumId == a1.id })
    }

    func testSearchQueryPopulatesHitsAndEmptyClearsThem() throws {
        let model = try Self.makeModel()
        try model.store.upsert(tracks: [
            Self.makeTrack(path: "/midnight.flac", title: "Midnight Run", artist: "Aurora", album: "Lights"),
            Self.makeTrack(path: "/sunrise.flac",  title: "Sunrise",      artist: "Aurora", album: "Lights"),
        ])
        model.reloadAll()

        model.searchQuery = "Mid"
        XCTAssertTrue(model.isSearching)
        XCTAssertEqual(model.searchHits.count, 1)
        XCTAssertEqual(model.searchHits.first?.track.path, "/midnight.flac")

        model.searchQuery = ""
        XCTAssertFalse(model.isSearching)
        XCTAssertEqual(model.searchHits.count, 0)
    }

    func testTrackActionsAreInvokedOnPlayNowAndEnqueue() throws {
        let played = Counter()
        let enqueued = Counter()
        let actions = LibraryTrackActions(
            playNow: { _ in played.bump() },
            enqueue: { _ in enqueued.bump() }
        )
        let model = try Self.makeModel(trackActions: actions)
        try model.store.upsert(tracks: [Self.makeTrack(path: "/a.flac", artist: "A", album: "X")])
        model.reloadAll()
        let row = try XCTUnwrap(model.tracks.first)

        model.playNow(row)
        model.enqueue(row)
        model.enqueue(row)

        XCTAssertEqual(played.count, 1)
        XCTAssertEqual(enqueued.count, 2)
    }

    // MARK: - helpers

    private static func makeModel(trackActions: LibraryTrackActions = .noop) throws -> LibraryViewModel {
        let db = try LibraryDatabase.open(.inMemory)
        let store = LibraryStore(database: db)
        return LibraryViewModel(store: store, trackActions: trackActions)
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

/// `@Sendable` クロージャ越しに count を増やすための、 main actor 上で操作するシンプルなカウンタ。
/// `LibraryTrackActions` クロージャは `@MainActor` 注釈なので、 ここも main actor 隔離で扱う。
@MainActor
private final class Counter {
    private(set) var count: Int = 0
    func bump() { count += 1 }
}
