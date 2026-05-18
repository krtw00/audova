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
    public let warnings: [ScanWarning]

    public init(tracks: [Track], warnings: [ScanWarning]) {
        self.tracks = tracks
        self.warnings = warnings
    }
}
