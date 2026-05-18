import Foundation
import SFBAudioEngine

public enum LibraryScannerError: Error, CustomStringConvertible, Sendable {
    case folderNotFound(URL)
    case notADirectory(URL)
    case enumeratorCreationFailed(URL)

    public var description: String {
        switch self {
        case .folderNotFound(let url):
            return "folder not found: \(url.path)"
        case .notADirectory(let url):
            return "not a directory: \(url.path)"
        case .enumeratorCreationFailed(let url):
            return "failed to enumerate folder: \(url.path)"
        }
    }
}

public actor LibraryScanner {
    public typealias ProgressHandler = @Sendable (_ scanned: Int, _ currentURL: URL) -> Void

    public init() {}

    public func scan(
        folder: URL,
        onProgress: ProgressHandler? = nil
    ) throws -> ScanResult {
        try Task.checkCancellation()

        let fileManager = FileManager.default
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: folder.path, isDirectory: &isDirectory) else {
            throw LibraryScannerError.folderNotFound(folder)
        }
        guard isDirectory.boolValue else {
            throw LibraryScannerError.notADirectory(folder)
        }

        let resourceKeys: [URLResourceKey] = [
            .isRegularFileKey,
            .fileSizeKey,
            .contentModificationDateKey,
        ]

        guard let enumerator = fileManager.enumerator(
            at: folder,
            includingPropertiesForKeys: resourceKeys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw LibraryScannerError.enumeratorCreationFailed(folder)
        }

        var tracks: [Track] = []
        var warnings: [ScanWarning] = []
        var scanned = 0

        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()

            let values: URLResourceValues
            do {
                values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
            } catch {
                warnings.append(.init(
                    url: fileURL,
                    reason: .fileAttributesUnavailable(message: error.localizedDescription)
                ))
                continue
            }
            guard values.isRegularFile == true else { continue }

            let ext = fileURL.pathExtension.lowercased()
            guard let codec = AudioCodec(rawValue: ext) else {
                continue
            }

            guard let size = values.fileSize.map(Int64.init),
                  let mtime = values.contentModificationDate else {
                warnings.append(.init(
                    url: fileURL,
                    reason: .fileAttributesUnavailable(message: "missing size or modification date")
                ))
                continue
            }

            scanned += 1
            onProgress?(scanned, fileURL)

            do {
                let track = try Self.readTrack(at: fileURL, codec: codec, fileSize: size, modificationDate: mtime)
                tracks.append(track)
            } catch {
                warnings.append(.init(
                    url: fileURL,
                    reason: .metadataReadFailed(message: error.localizedDescription)
                ))
            }
        }

        return ScanResult(tracks: tracks, warnings: warnings)
    }

    /// Extract metadata + properties from a single audio file via SFBAudioEngine.
    static func readTrack(
        at url: URL,
        codec: AudioCodec,
        fileSize: Int64,
        modificationDate: Date
    ) throws -> Track {
        let audioFile = try AudioFile(readingPropertiesAndMetadataFrom: url)
        let metadata = audioFile.metadata
        let properties = audioFile.properties

        return Track(
            url: url,
            codec: codec,
            fileSize: fileSize,
            modificationDate: modificationDate,
            title: nonEmpty(metadata.title),
            artist: nonEmpty(metadata.artist),
            albumArtist: nonEmpty(metadata.albumArtist),
            albumTitle: nonEmpty(metadata.albumTitle),
            composer: nonEmpty(metadata.composer),
            genre: nonEmpty(metadata.genre),
            year: parseYear(metadata.releaseDate),
            trackNumber: metadata.trackNumber,
            trackTotal: metadata.trackTotal,
            discNumber: metadata.discNumber,
            discTotal: metadata.discTotal,
            duration: properties.duration,
            sampleRate: properties.sampleRate,
            bitDepth: properties.bitDepth,
            channelCount: properties.channelCount.map { Int($0) }
        )
    }

    private static func nonEmpty(_ s: String?) -> String? {
        guard let s, !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        return s
    }

    /// `releaseDate` は ISO 8601 (`2024-05-18`) や `YYYY` 単体など揺れがあるので、 先頭 4 桁を year として抽出する。
    private static func parseYear(_ releaseDate: String?) -> Int? {
        guard let s = releaseDate else { return nil }
        let prefix = s.prefix(4)
        guard prefix.count == 4, let year = Int(prefix), year > 0 else { return nil }
        return year
    }
}
