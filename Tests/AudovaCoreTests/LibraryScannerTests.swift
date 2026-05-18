import XCTest
@testable import AudovaCore

final class AudioCodecTests: XCTestCase {
    func testRawValueMatchesExtension() {
        XCTAssertEqual(AudioCodec(rawValue: "mp3"), .mp3)
        XCTAssertEqual(AudioCodec(rawValue: "flac"), .flac)
        XCTAssertEqual(AudioCodec(rawValue: "wv"), .wv)
        XCTAssertNil(AudioCodec(rawValue: "txt"))
    }

    func testPathExtensionInitIsCaseInsensitive() {
        XCTAssertEqual(AudioCodec(pathExtension: "FLAC"), .flac)
        XCTAssertEqual(AudioCodec(pathExtension: "Mp3"), .mp3)
    }

    func testAllExpectedCodecsCovered() {
        let expected: Set<String> = [
            "mp3", "m4a", "flac", "ogg", "opus", "wav",
            "aiff", "dsf", "dff", "ape", "wv", "mpc",
        ]
        XCTAssertEqual(Set(AudioCodec.allCases.map(\.rawValue)), expected)
    }
}

final class LibraryScannerTests: XCTestCase {
    func testRejectsMissingFolder() async {
        let scanner = LibraryScanner()
        let missing = URL(fileURLWithPath: "/tmp/audova-nonexistent-\(UUID().uuidString)")
        do {
            _ = try await scanner.scan(folder: missing)
            XCTFail("expected folderNotFound error")
        } catch LibraryScannerError.folderNotFound {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testRejectsRegularFile() async throws {
        let tempFile = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-not-a-dir-\(UUID().uuidString).txt")
        try "hello".write(to: tempFile, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let scanner = LibraryScanner()
        do {
            _ = try await scanner.scan(folder: tempFile)
            XCTFail("expected notADirectory error")
        } catch LibraryScannerError.notADirectory {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }

    func testFiltersOutUnsupportedExtensions() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data("not audio".utf8).write(to: tempDir.appendingPathComponent("readme.txt"))
        try Data("not audio".utf8).write(to: tempDir.appendingPathComponent("cover.jpg"))
        try Data("not audio".utf8).write(to: tempDir.appendingPathComponent("noext"))

        let scanner = LibraryScanner()
        let result = try await scanner.scan(folder: tempDir)

        XCTAssertEqual(result.tracks.count, 0)
        XCTAssertEqual(result.warnings.count, 0)
    }

    func testBrokenAudioFilesYieldWarnings() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try Data().write(to: tempDir.appendingPathComponent("empty.mp3"))
        try Data("garbage".utf8).write(to: tempDir.appendingPathComponent("broken.flac"))

        let scanner = LibraryScanner()
        let result = try await scanner.scan(folder: tempDir)

        // SFBAudioEngine は空 mp3 を許容して空 metadata の Track を返すことがある。
        // scanner の責務は「SFBAudioEngine が throw したら warning 記録」 + 「両ファイルを処理した」 まで。
        XCTAssertEqual(result.tracks.count + result.warnings.count, 2,
                       "scanner should account for every audio-extension file")
        XCTAssertGreaterThanOrEqual(result.warnings.count, 1,
                                    "garbage flac should yield a warning")
        XCTAssertTrue(result.warnings.allSatisfy {
            if case .metadataReadFailed = $0.reason { return true }
            return false
        })
    }

    func testRecursesIntoSubdirectoriesAndReportsProgress() async throws {
        let tempDir = try makeTempDir()
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let album = tempDir.appendingPathComponent("album")
        let disc1 = album.appendingPathComponent("disc1")
        try FileManager.default.createDirectory(at: disc1, withIntermediateDirectories: true)
        try Data().write(to: disc1.appendingPathComponent("01.mp3"))
        try Data().write(to: album.appendingPathComponent("intro.flac"))
        try Data("not audio".utf8).write(to: album.appendingPathComponent("notes.txt"))

        let counter = ProgressCounter()
        let scanner = LibraryScanner()
        let result = try await scanner.scan(folder: tempDir) { _, _ in
            counter.increment()
        }

        XCTAssertEqual(result.tracks.count + result.warnings.count, 2,
                       "scanner should account for every audio file across subdirectories")
        XCTAssertEqual(counter.value, 2, "progress should be called once per audio file")
    }

    /// fixture 環境変数 (= `AUDOVA_TEST_LIBRARY`) で指定された実音源ディレクトリで metadata 抽出を検証する。
    /// fixture 未配置時は skip (= scripts/fetch_test_audio.py + scripts/arrange_test_library.sh で生成可)。
    func testMetadataExtraction_withFixtures() async throws {
        guard let libRoot = ProcessInfo.processInfo.environment["AUDOVA_TEST_LIBRARY"] else {
            throw XCTSkip("set AUDOVA_TEST_LIBRARY=$HOME/Music/audova-test-library/library to enable")
        }
        let folder = URL(fileURLWithPath: (libRoot as NSString).expandingTildeInPath)
        let scanner = LibraryScanner()
        let result = try await scanner.scan(folder: folder)

        XCTAssertGreaterThan(result.tracks.count, 0, "no tracks scanned from fixtures: \(folder.path)")
        let withMeta = result.tracks.filter { $0.title != nil || $0.artist != nil }
        XCTAssertGreaterThan(withMeta.count, 0, "no tracks with title/artist metadata")
        let withProperties = result.tracks.filter { $0.duration != nil && $0.sampleRate != nil }
        XCTAssertGreaterThan(withProperties.count, 0, "no tracks with duration/sampleRate")
    }

    // MARK: helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("audova-scanner-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private final class ProgressCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var _value = 0
    func increment() {
        lock.lock(); defer { lock.unlock() }
        _value += 1
    }
    var value: Int {
        lock.lock(); defer { lock.unlock() }
        return _value
    }
}
