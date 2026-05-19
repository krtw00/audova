import Foundation
import GRDB

/// `LibraryStore` の追加クエリ。 3 ペインライブラリ画面のフラットモード (= 「全アルバム」 / 「全曲」)
/// と、 アーティスト選択時のアルバム未指定時の「そのアーティストの全曲」 を読むための API を分けて持つ。
///
/// 既存の `LibraryStore.swift` (= upsert / FTS) と責務を分けるため別ファイルにした。
extension LibraryStore {
    /// 全アルバムを (artist 名 → アルバム年 → タイトル) 順で返す。 表示は join しないので `LibraryStore` 利用側で
    /// `artists` と引き合わせる想定。 現状はアルバム単体を返す。
    public func allAlbums() throws -> [Album] {
        try database.dbPool.read { db in
            try Album
                .order(
                    Column("artist_id").ascNullsLast,
                    Column("year").ascNullsLast,
                    Column("title").asc
                )
                .fetchAll(db)
        }
    }

    /// 全トラックを (artist 名 → album → disc/track → title) 順で返す。
    /// 数万件想定のため将来は SwiftUI 側で lazy にするが、 Phase 1 MVP では一括読込で良い (= ADR 0001)。
    public func allTracks() throws -> [TrackRow] {
        try database.dbPool.read { db in
            try TrackRow
                .order(
                    Column("artist_id").ascNullsLast,
                    Column("album_id").ascNullsLast,
                    Column("disc_no").ascNullsLast,
                    Column("track_no").ascNullsLast,
                    Column("title").asc
                )
                .fetchAll(db)
        }
    }

    /// 指定アーティストの全曲 (= アルバム未選択時のフォールバック)。 disc/track 昇順。
    public func tracks(byArtistId artistId: Int64) throws -> [TrackRow] {
        try database.dbPool.read { db in
            try TrackRow
                .filter(Column("artist_id") == artistId)
                .order(
                    Column("album_id").ascNullsLast,
                    Column("disc_no").ascNullsLast,
                    Column("track_no").ascNullsLast,
                    Column("title").asc
                )
                .fetchAll(db)
        }
    }

    /// `tracks` テーブルから 1 行を path で引く。 右クリックメニューでファイル確認するときなどに使う。
    public func track(byPath path: String) throws -> TrackRow? {
        try database.dbPool.read { db in
            try TrackRow.filter(Column("path") == path).fetchOne(db)
        }
    }
}
