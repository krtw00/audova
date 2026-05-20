import Foundation

public enum AudioCodec: String, Sendable, Codable, CaseIterable {
    case mp3, m4a, flac, ogg, opus, wav, aiff, dsf, dff, ape, wv, mpc

    public init?(pathExtension ext: String) {
        self.init(rawValue: ext.lowercased())
    }
}

public struct Track: Sendable, Hashable {
    public let url: URL
    public let codec: AudioCodec
    public let fileSize: Int64
    public let modificationDate: Date

    public let title: String?
    public let artist: String?
    public let albumArtist: String?
    public let albumTitle: String?
    public let composer: String?
    public let genre: String?
    public let year: Int?
    public let trackNumber: Int?
    public let trackTotal: Int?
    public let discNumber: Int?
    public let discTotal: Int?

    public let duration: TimeInterval?
    public let sampleRate: Double?
    public let bitDepth: Int?
    public let channelCount: Int?

    public init(
        url: URL,
        codec: AudioCodec,
        fileSize: Int64,
        modificationDate: Date,
        title: String? = nil,
        artist: String? = nil,
        albumArtist: String? = nil,
        albumTitle: String? = nil,
        composer: String? = nil,
        genre: String? = nil,
        year: Int? = nil,
        trackNumber: Int? = nil,
        trackTotal: Int? = nil,
        discNumber: Int? = nil,
        discTotal: Int? = nil,
        duration: TimeInterval? = nil,
        sampleRate: Double? = nil,
        bitDepth: Int? = nil,
        channelCount: Int? = nil
    ) {
        self.url = url
        self.codec = codec
        self.fileSize = fileSize
        self.modificationDate = modificationDate
        self.title = title
        self.artist = artist
        self.albumArtist = albumArtist
        self.albumTitle = albumTitle
        self.composer = composer
        self.genre = genre
        self.year = year
        self.trackNumber = trackNumber
        self.trackTotal = trackTotal
        self.discNumber = discNumber
        self.discTotal = discTotal
        self.duration = duration
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.channelCount = channelCount
    }
}

public struct ScanWarning: Sendable, Hashable {
    public enum Reason: Sendable, Hashable {
        case metadataReadFailed(message: String)
        case fileAttributesUnavailable(message: String)
        case unsupportedExtension
    }

    public let url: URL
    public let reason: Reason

    public init(url: URL, reason: Reason) {
        self.url = url
        self.reason = reason
    }
}

public struct ScanResult: Sendable {
    public let tracks: [Track]
    public let unchangedPaths: Set<String>
    public let warnings: [ScanWarning]

    /// 今回スキャンで「見た」全パスのセット (= upsert 対象 + 未変更 skip)。
    public var seenPaths: Set<String> {
        Set(tracks.map(\.url.path)).union(unchangedPaths)
    }

    /// 後方互換 init (既存呼び出しに影響しない)。
    public init(tracks: [Track], warnings: [ScanWarning]) {
        self.tracks = tracks
        self.unchangedPaths = []
        self.warnings = warnings
    }

    public init(tracks: [Track], unchangedPaths: Set<String>, warnings: [ScanWarning]) {
        self.tracks = tracks
        self.unchangedPaths = unchangedPaths
        self.warnings = warnings
    }
}

/// 再スキャン時の未変更判定に使うファイル署名 (mtime + サイズ)。
public struct FileSignature: Sendable, Hashable {
    public let mtime: Double      // since 1970
    public let fileSize: Int64
    public init(mtime: Double, fileSize: Int64) { self.mtime = mtime; self.fileSize = fileSize }
}

/// 差分スキャンの DB 反映結果。
public struct ScanOutcome: Sendable, Equatable {
    public let updated: Int   // 新規 + 変更 (upsert 件数)
    public let skipped: Int   // 未変更で skip した件数
    public let deleted: Int   // 実体喪失で削除した件数
    public let warnings: Int
    public init(updated: Int, skipped: Int, deleted: Int, warnings: Int) {
        self.updated = updated
        self.skipped = skipped
        self.deleted = deleted
        self.warnings = warnings
    }
}
