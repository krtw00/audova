import Foundation
import GRDB

/// 1 アーティスト行。
public struct Artist: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var name: String
    /// 並び替え / 検索向けに小文字化・前後空白除去した正規形 (= 表示には使わない)。
    public var nameSort: String

    public static let databaseTableName = "artists"

    public init(id: Int64? = nil, name: String, nameSort: String) {
        self.id = id
        self.name = name
        self.nameSort = nameSort
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case nameSort = "name_sort"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 1 アルバム行。 同じタイトルでも `artistId` が違えば別行 (= compilation 対応)。
public struct Album: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var title: String
    public var artistId: Int64?
    public var year: Int?
    public var coverArtPath: String?

    public static let databaseTableName = "albums"

    public init(
        id: Int64? = nil,
        title: String,
        artistId: Int64? = nil,
        year: Int? = nil,
        coverArtPath: String? = nil
    ) {
        self.id = id
        self.title = title
        self.artistId = artistId
        self.year = year
        self.coverArtPath = coverArtPath
    }

    enum CodingKeys: String, CodingKey {
        case id, title, year
        case artistId = "artist_id"
        case coverArtPath = "cover_art_path"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// 1 トラック行。 `Track` (= スキャナ出力) を DB 永続形に落とした表現。
public struct TrackRow: Codable, Hashable, Sendable, FetchableRecord, MutablePersistableRecord {
    public var id: Int64?
    public var path: String
    public var title: String?
    public var artistId: Int64?
    public var albumId: Int64?
    public var trackNo: Int?
    public var discNo: Int?
    public var year: Int?
    public var genre: String?
    public var durationMs: Int?
    public var sampleRate: Double?
    public var bitDepth: Int?
    public var codec: String
    public var fileSize: Int64
    public var mtime: Double
    public var addedAt: Double

    public static let databaseTableName = "tracks"

    public init(
        id: Int64? = nil,
        path: String,
        title: String? = nil,
        artistId: Int64? = nil,
        albumId: Int64? = nil,
        trackNo: Int? = nil,
        discNo: Int? = nil,
        year: Int? = nil,
        genre: String? = nil,
        durationMs: Int? = nil,
        sampleRate: Double? = nil,
        bitDepth: Int? = nil,
        codec: String,
        fileSize: Int64,
        mtime: Double,
        addedAt: Double
    ) {
        self.id = id
        self.path = path
        self.title = title
        self.artistId = artistId
        self.albumId = albumId
        self.trackNo = trackNo
        self.discNo = discNo
        self.year = year
        self.genre = genre
        self.durationMs = durationMs
        self.sampleRate = sampleRate
        self.bitDepth = bitDepth
        self.codec = codec
        self.fileSize = fileSize
        self.mtime = mtime
        self.addedAt = addedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, path, title, year, genre, codec, mtime
        case artistId = "artist_id"
        case albumId = "album_id"
        case trackNo = "track_no"
        case discNo = "disc_no"
        case durationMs = "duration_ms"
        case sampleRate = "sample_rate"
        case bitDepth = "bit_depth"
        case fileSize = "file_size"
        case addedAt = "added_at"
    }

    public mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}

/// FTS5 search hit (= tracks_fts の rowid + tracks 本体)。
public struct TrackSearchHit: Sendable, Hashable {
    public let track: TrackRow
    public let artistName: String?
    public let albumTitle: String?

    public init(track: TrackRow, artistName: String?, albumTitle: String?) {
        self.track = track
        self.artistName = artistName
        self.albumTitle = albumTitle
    }
}
