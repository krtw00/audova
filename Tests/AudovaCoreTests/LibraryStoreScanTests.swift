import XCTest
import GRDB
@testable import AudovaCore

/// `LibraryStore+Scan.swift` の `fileSignatures(under:)` / `applyScan(_:folder:)` を検証する。
final class LibraryStoreScanTests: XCTestCase {
    // MARK: - fileSignatures(under:)

    func testFileSignaturesReturnsOnlyTracksUnderFolder() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/album1/01.flac", mtime: 1_000_000, fileSize: 512),
            Self.makeTrack(path: "/music/album1/02.flac", mtime: 1_000_001, fileSize: 1024),
            Self.makeTrack(path: "/other/01.flac",        mtime: 2_000_000, fileSize: 256),
        ])
        let folder = URL(fileURLWithPath: "/music/album1")
        let sigs = try store.fileSignatures(under: folder)

        XCTAssertEqual(sigs.count, 2)
        XCTAssertNotNil(sigs["/music/album1/01.flac"])
        XCTAssertNotNil(sigs["/music/album1/02.flac"])
        XCTAssertNil(sigs["/other/01.flac"], "tracks outside folder must not be included")
    }

    func testFileSignaturesContainsCorrectMtimeAndSize() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/01.flac", mtime: 1_234_567.89, fileSize: 4096),
        ])
        let sigs = try store.fileSignatures(under: URL(fileURLWithPath: "/music"))
        let sig = try XCTUnwrap(sigs["/music/01.flac"])
        XCTAssertEqual(sig.fileSize, 4096)
        XCTAssertEqual(sig.mtime, 1_234_567.89, accuracy: 0.001)
    }

    func testFileSignaturesEmptyWhenNoTracksUnderFolder() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/other/01.flac"),
        ])
        let sigs = try store.fileSignatures(under: URL(fileURLWithPath: "/music"))
        XCTAssertTrue(sigs.isEmpty)
    }

    // MARK: - applyScan(_:folder:) — upsert

    func testApplyScanUpsertsBrandNewTracks() throws {
        let store = try Self.makeStore()
        let result = ScanResult(
            tracks: [
                Self.makeTrack(path: "/music/01.flac", title: "New Track", artist: "A", album: "X"),
            ],
            unchangedPaths: [],
            warnings: []
        )
        let outcome = try store.applyScan(result, folder: URL(fileURLWithPath: "/music"))

        XCTAssertEqual(outcome.updated, 1)
        XCTAssertEqual(outcome.skipped, 0)
        XCTAssertEqual(outcome.deleted, 0)
        XCTAssertEqual(try store.trackCount(), 1)
    }

    // MARK: - applyScan(_:folder:) — deletion

    func testApplyScanDeletesMissingTrackUnderFolder() throws {
        let store = try Self.makeStore()
        // 事前に 3 トラックを登録。
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/01.flac", artist: "A", album: "X"),
            Self.makeTrack(path: "/music/02.flac", artist: "A", album: "X"),
            Self.makeTrack(path: "/music/03.flac", artist: "A", album: "X"),
        ])
        XCTAssertEqual(try store.trackCount(), 3)

        // 2 つだけ seenPaths に含む ScanResult を applyScan に渡す。
        // /music/03.flac は seen されないので削除対象。
        let result = ScanResult(
            tracks: [
                Self.makeTrack(path: "/music/01.flac", artist: "A", album: "X"),
            ],
            unchangedPaths: ["/music/02.flac"],
            warnings: []
        )
        let outcome = try store.applyScan(result, folder: URL(fileURLWithPath: "/music"))

        XCTAssertEqual(outcome.deleted, 1)
        XCTAssertEqual(try store.trackCount(), 2, "/music/03.flac should be deleted")
    }

    func testApplyScanDoesNotDeleteTracksOutsideFolder() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/01.flac", artist: "A", album: "X"),
            Self.makeTrack(path: "/other/01.flac", artist: "B", album: "Y"),
        ])

        // /music フォルダをスキャン。 /music/01.flac は見つかった扱い。
        // /other/01.flac はフォルダ外なので削除されない。
        let result = ScanResult(
            tracks: [
                Self.makeTrack(path: "/music/01.flac", artist: "A", album: "X"),
            ],
            unchangedPaths: [],
            warnings: []
        )
        let outcome = try store.applyScan(result, folder: URL(fileURLWithPath: "/music"))

        XCTAssertEqual(outcome.deleted, 0, "tracks outside scanned folder must not be deleted")
        XCTAssertEqual(try store.trackCount(), 2)
    }

    // MARK: - applyScan(_:folder:) — orphan cleanup

    func testApplyScanCleansUpOrphanedAlbumAndArtist() throws {
        let store = try Self.makeStore()
        // Artist "Solo" → Album "AlbumX" に紐付くトラックが 1 つだけ。
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/solo.flac", artist: "Solo", album: "AlbumX"),
            Self.makeTrack(path: "/music/keep.flac", artist: "Keep", album: "AlbumY"),
        ])
        XCTAssertEqual(try store.artistCount(), 2)
        XCTAssertEqual(try store.albumCount(), 2)

        // /music/solo.flac が消えた扱いで applyScan → "Solo" / "AlbumX" は孤立クリーンアップ。
        let result = ScanResult(
            tracks: [],
            unchangedPaths: ["/music/keep.flac"],
            warnings: []
        )
        let outcome = try store.applyScan(result, folder: URL(fileURLWithPath: "/music"))

        XCTAssertEqual(outcome.deleted, 1)
        XCTAssertEqual(try store.trackCount(), 1)
        XCTAssertEqual(try store.artistCount(), 1, "orphaned artist Solo should be removed")
        XCTAssertEqual(try store.albumCount(), 1, "orphaned album AlbumX should be removed")
    }

    // MARK: - applyScan(_:folder:) — skipped count

    func testApplyScanSkippedCountMatchesUnchangedPaths() throws {
        let store = try Self.makeStore()
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/01.flac"),
            Self.makeTrack(path: "/music/02.flac"),
        ])

        let result = ScanResult(
            tracks: [],
            unchangedPaths: ["/music/01.flac", "/music/02.flac"],
            warnings: []
        )
        let outcome = try store.applyScan(result, folder: URL(fileURLWithPath: "/music"))

        XCTAssertEqual(outcome.skipped, 2)
        XCTAssertEqual(outcome.updated, 0)
        XCTAssertEqual(outcome.deleted, 0)
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
        trackNo: Int? = nil,
        mtime: Double = 1_500_000_000,
        fileSize: Int64 = 1024
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: path),
            codec: .flac,
            fileSize: fileSize,
            modificationDate: Date(timeIntervalSince1970: mtime),
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
