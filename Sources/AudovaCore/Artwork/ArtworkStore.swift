import Foundation

/// アルバムアートワークをファイルシステムに保存するストア。
///
/// ファイル名は `<albumId>.<ext>`。 保存先ディレクトリは呼び出し元が指定するか、
/// `applicationSupport()` で標準の `~/Library/Application Support/Audova/artwork/` を使う。
public struct ArtworkStore: Sendable {
    public let directory: URL

    public init(directory: URL) {
        self.directory = directory
    }

    /// 既定保存先: `~/Library/Application Support/Audova/artwork/`
    public static func applicationSupport() throws -> ArtworkStore {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base
            .appendingPathComponent("Audova", isDirectory: true)
            .appendingPathComponent("artwork", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return ArtworkStore(directory: dir)
    }

    /// album 用に保存し保存先 URL を返す。
    ///
    /// 同 album の既存ファイル (別 ext 含む) は削除してから書く。
    @discardableResult
    public func save(_ artwork: ArtworkService.ExtractedArtwork, forAlbumId id: Int64) throws -> URL {
        let fm = FileManager.default
        try fm.createDirectory(at: directory, withIntermediateDirectories: true)

        // 同 album の既存ファイルを削除 (別 ext の残骸を防ぐ)
        let allFiles = (try? fm.contentsOfDirectory(atPath: directory.path)) ?? []
        let prefix = "\(id)."
        for file in allFiles where file.hasPrefix(prefix) {
            let old = directory.appendingPathComponent(file)
            try? fm.removeItem(at: old)
        }

        let dest = directory.appendingPathComponent("\(id).\(artwork.ext)")
        try artwork.data.write(to: dest)
        return dest
    }
}
