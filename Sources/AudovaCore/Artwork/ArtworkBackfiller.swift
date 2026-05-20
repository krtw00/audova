import Foundation

/// `coverArtPath` が未設定のアルバムに対して、 代表トラックからアートワークを抽出し
/// `ArtworkStore` に保存したうえで `LibraryStore` の `cover_art_path` を更新するバックフィラー。
public struct ArtworkBackfiller {
    private let store: LibraryStore
    private let artworkStore: ArtworkStore

    public init(store: LibraryStore, artworkStore: ArtworkStore) {
        self.store = store
        self.artworkStore = artworkStore
    }

    /// `coverArtPath == nil` のアルバムごとに処理を行い、 反映した album 数を返す。
    ///
    /// 抽出失敗の album はスキップする (例外で全体を止めない)。
    @discardableResult
    public func run() throws -> Int {
        let albums = try store.allAlbums()
        var updated = 0

        for album in albums where album.coverArtPath == nil {
            guard let albumId = album.id else { continue }
            let tracks = try store.tracks(byAlbumId: albumId)
            guard let firstTrack = tracks.first else { continue }

            let trackURL = URL(fileURLWithPath: firstTrack.path)
            guard let artwork = ArtworkService.extract(forTrackAt: trackURL) else { continue }

            do {
                let savedURL = try artworkStore.save(artwork, forAlbumId: albumId)
                try store.setCoverArtPath(savedURL.path, forAlbumId: albumId)
                updated += 1
            } catch {
                // 保存 / DB 更新失敗はスキップして続行
                continue
            }
        }

        return updated
    }
}
