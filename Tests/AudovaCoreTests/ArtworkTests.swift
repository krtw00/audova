import XCTest
@testable import AudovaCore

/// AUD-7 アートワークエンジン層のテスト。
///
/// - `ArtworkService.imageExt` の PNG / JPEG 判定
/// - `ArtworkStore.save` の保存 / 上書き動作
/// - `ArtworkService.extract` フォルダ fallback (AudioFile が開けない時に兄弟ファイルを返す)
/// - `LibraryStore.setCoverArtPath` の round-trip
final class ArtworkTests: XCTestCase {

    // MARK: - ArtworkService.imageExt

    func testImageExtReturnsPngForPngMagicBytes() {
        // PNG magic: 89 50 4E 47 ...
        let pngBytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        let data = Data(pngBytes)
        XCTAssertEqual(ArtworkService.imageExt(data), "png")
    }

    func testImageExtReturnsJpgForJpegMagicBytes() {
        // JPEG magic: FF D8 ...
        let jpegBytes: [UInt8] = [0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10]
        let data = Data(jpegBytes)
        XCTAssertEqual(ArtworkService.imageExt(data), "jpg")
    }

    func testImageExtReturnsJpgForUnknownData() {
        let unknownBytes: [UInt8] = [0x00, 0x01, 0x02, 0x03]
        let data = Data(unknownBytes)
        XCTAssertEqual(ArtworkService.imageExt(data), "jpg")
    }

    func testImageExtReturnsJpgForEmptyData() {
        XCTAssertEqual(ArtworkService.imageExt(Data()), "jpg")
    }

    // MARK: - ArtworkStore.save

    func testArtworkStoreSavesFileWithCorrectName() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-artwork-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let artworkStore = ArtworkStore(directory: tmpDir)
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x00])
        let artwork = ArtworkService.ExtractedArtwork(data: pngData, ext: "png")

        let savedURL = try artworkStore.save(artwork, forAlbumId: 42)

        XCTAssertEqual(savedURL.lastPathComponent, "42.png")
        XCTAssertTrue(FileManager.default.fileExists(atPath: savedURL.path))
        XCTAssertEqual(try Data(contentsOf: savedURL), pngData)
    }

    func testArtworkStoreSaveOverwritesPreviousFile() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-artwork-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let artworkStore = ArtworkStore(directory: tmpDir)
        let firstData = Data([0xFF, 0xD8, 0x01, 0x02])
        let secondData = Data([0xFF, 0xD8, 0xAA, 0xBB])

        let first = ArtworkService.ExtractedArtwork(data: firstData, ext: "jpg")
        let savedFirst = try artworkStore.save(first, forAlbumId: 10)
        XCTAssertEqual(savedFirst.lastPathComponent, "10.jpg")

        // 上書き (同じ ext)
        let second = ArtworkService.ExtractedArtwork(data: secondData, ext: "jpg")
        let savedSecond = try artworkStore.save(second, forAlbumId: 10)
        XCTAssertEqual(savedSecond.lastPathComponent, "10.jpg")
        XCTAssertEqual(try Data(contentsOf: savedSecond), secondData)
    }

    func testArtworkStoreSaveReplacesOldExtension() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-artwork-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        let artworkStore = ArtworkStore(directory: tmpDir)

        // 最初 jpg で保存
        let jpgData = Data([0xFF, 0xD8, 0x01, 0x02])
        let jpgArtwork = ArtworkService.ExtractedArtwork(data: jpgData, ext: "jpg")
        _ = try artworkStore.save(jpgArtwork, forAlbumId: 5)

        // 次に png で保存 → 元の jpg は消えているはず
        let pngData = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x00])
        let pngArtwork = ArtworkService.ExtractedArtwork(data: pngData, ext: "png")
        let savedURL = try artworkStore.save(pngArtwork, forAlbumId: 5)

        XCTAssertEqual(savedURL.lastPathComponent, "5.png")
        let oldJpg = tmpDir.appendingPathComponent("5.jpg")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldJpg.path), "旧 jpg ファイルは削除されているべき")
    }

    // MARK: - ArtworkService.extract (folder fallback)

    func testExtractFolderFallbackFindsCovertPng() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-folder-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // ダミー audio ファイル (中身は不正 → AudioFile で開けない)
        let dummyTrack = tmpDir.appendingPathComponent("track.flac")
        try Data([0x00, 0x01, 0x02]).write(to: dummyTrack)

        // 兄弟 cover.png を置く
        let pngMagic = Data([0x89, 0x50, 0x4E, 0x47, 0x00, 0x00, 0x00, 0x00])
        let coverPng = tmpDir.appendingPathComponent("cover.png")
        try pngMagic.write(to: coverPng)

        let result = ArtworkService.extract(forTrackAt: dummyTrack)
        let artwork = try XCTUnwrap(result, "cover.png があるのでフォルダ fallback で見つかるべき")
        XCTAssertEqual(artwork.ext, "png")
        XCTAssertEqual(artwork.data, pngMagic)
    }

    func testExtractFolderFallbackIsCaseInsensitive() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-folder-ci-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // ダミー audio ファイル (中身は不正 → AudioFile で開けない)
        let dummyTrack = tmpDir.appendingPathComponent("track.mp3")
        try Data([0x00, 0x01]).write(to: dummyTrack)

        // 大文字小文字が混じった "COVER.JPG" を置く (= "cover.jpg" に lowercase すれば一致)
        let jpegMagic = Data([0xFF, 0xD8, 0xAA, 0xBB])
        let coverJpg = tmpDir.appendingPathComponent("COVER.JPG")
        try jpegMagic.write(to: coverJpg)

        let result = ArtworkService.extract(forTrackAt: dummyTrack)
        let artwork = try XCTUnwrap(result, "COVER.JPG (大文字) があるのでフォルダ fallback で見つかるべき")
        XCTAssertEqual(artwork.ext, "jpg")
        XCTAssertEqual(artwork.data, jpegMagic)
    }

    func testExtractReturnsNilWhenNoPictureAndNoFolderCandidate() throws {
        let tmpDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-empty-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: tmpDir) }

        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // ダミー audio ファイルのみ、 候補ファイルなし
        let dummyTrack = tmpDir.appendingPathComponent("track.flac")
        try Data([0x00, 0x01]).write(to: dummyTrack)

        let result = ArtworkService.extract(forTrackAt: dummyTrack)
        XCTAssertNil(result)
    }

    // MARK: - LibraryStore.setCoverArtPath round-trip

    func testSetCoverArtPathRoundTrip() throws {
        let store = try Self.makeStore()
        // アルバムを持つトラックを upsert してアルバム行を作る
        try store.upsert(tracks: [
            Self.makeTrack(path: "/music/01.flac", artist: "Test Artist", album: "Test Album"),
        ])
        let albums = try store.allAlbums()
        let album = try XCTUnwrap(albums.first)
        let albumId = try XCTUnwrap(album.id)

        // 初期状態は nil
        XCTAssertNil(album.coverArtPath)

        // path を設定
        try store.setCoverArtPath("/artwork/1.jpg", forAlbumId: albumId)
        let updated = try store.allAlbums().first(where: { $0.id == albumId })
        XCTAssertEqual(updated?.coverArtPath, "/artwork/1.jpg")

        // nil にリセット
        try store.setCoverArtPath(nil, forAlbumId: albumId)
        let reset = try store.allAlbums().first(where: { $0.id == albumId })
        XCTAssertNil(reset?.coverArtPath)
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
        album: String? = nil
    ) -> Track {
        Track(
            url: URL(fileURLWithPath: path),
            codec: .flac,
            fileSize: 1024,
            modificationDate: Date(timeIntervalSince1970: 1_500_000_000),
            title: title,
            artist: artist,
            albumTitle: album,
            duration: 200.0,
            sampleRate: 44100,
            bitDepth: 16,
            channelCount: 2
        )
    }
}
