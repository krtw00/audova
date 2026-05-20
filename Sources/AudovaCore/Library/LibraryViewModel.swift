import Foundation
import Observation

/// 3 ペインライブラリ画面と検索バー / スキャン進捗をまとめて駆動する `@Observable` ステート。
///
/// 役割:
/// - `LibraryStore` の同期 API を main actor 上で呼び、 観測可能な配列に展開する
/// - artist / album 選択、 フラットモード切替、 検索クエリの中央集約
/// - スキャン進捗 (`scanProgress`) の publish
///
/// 再生連携 (= AUD-6) とは疎結合にするため、 「曲を再生する」 / 「キューに追加する」 等の副作用は
/// `trackActions` (= `LibraryTrackActions`) 経由で外から差し込む。 default は no-op。
@MainActor
@Observable
public final class LibraryViewModel {
    // MARK: - 公開ステート

    public private(set) var artists: [Artist] = []
    public private(set) var albums: [Album] = []
    public private(set) var tracks: [TrackRow] = []

    /// 検索ヒット (= 検索バーに何か入力されている時のみ非空)。
    public private(set) var searchHits: [TrackSearchHit] = []

    /// 現在選択中のアーティスト (= 「全アーティスト」 = nil)。
    public var selectedArtistId: Int64? {
        didSet {
            // アーティストが切り替わったら、 配下のアルバム選択は外す。
            if oldValue != selectedArtistId {
                selectedAlbumId = nil
                reloadAlbumsAndTracks()
            }
        }
    }

    /// 現在選択中のアルバム (= 「全アルバム」 = nil)。
    public var selectedAlbumId: Int64? {
        didSet {
            if oldValue != selectedAlbumId {
                reloadTracksOnly()
            }
        }
    }

    /// 現在選択中のアルバムのレコード (= 詳細ヘッダー表示用)。 未選択 / 該当なしなら nil。
    public var selectedAlbum: Album? {
        guard let id = selectedAlbumId else { return nil }
        return albums.first { $0.id == id }
    }

    /// 検索クエリ (= 1 文字入力ごとに `performSearch` を呼ぶ想定)。
    public var searchQuery: String = "" {
        didSet {
            performSearch()
        }
    }

    /// スキャン進捗。 nil ならスキャン中ではない。
    public private(set) var scanProgress: ScanProgress?

    /// 直近のエラーメッセージ (= ユーザー向け、 alert などで表示する想定)。
    public var lastError: String?

    // MARK: - 依存

    public let store: LibraryStore
    public let scanner: LibraryScanner

    /// 再生キュー連携などの副作用 hook (= 実装は AUD-6 で差し込む)。 default は no-op。
    public var trackActions: LibraryTrackActions

    // MARK: - init

    public init(
        store: LibraryStore,
        scanner: LibraryScanner = LibraryScanner(),
        trackActions: LibraryTrackActions = .noop
    ) {
        self.store = store
        self.scanner = scanner
        self.trackActions = trackActions
    }

    // MARK: - reload

    /// 全ペイン (= artists + albums + tracks) を読み直す。 初回 / スキャン完了後に呼ぶ。
    public func reloadAll() {
        do {
            artists = try store.allArtists()
            reloadAlbumsAndTracks()
        } catch {
            lastError = "ライブラリ読込に失敗: \(error.localizedDescription)"
        }
    }

    /// アルバム + 曲を読み直す (= アーティスト選択変更時)。
    private func reloadAlbumsAndTracks() {
        do {
            if let artistId = selectedArtistId {
                albums = try store.albums(byArtistId: artistId)
            } else {
                // フラットモード: 全アルバム
                albums = try store.allAlbums()
            }
        } catch {
            albums = []
            lastError = "アルバム読込に失敗: \(error.localizedDescription)"
        }
        reloadTracksOnly()
    }

    /// 曲リストだけ読み直す (= アルバム選択変更時)。
    private func reloadTracksOnly() {
        do {
            if let albumId = selectedAlbumId {
                tracks = try store.tracks(byAlbumId: albumId)
            } else if let artistId = selectedArtistId {
                // アルバム未選択でアーティスト選択中 → そのアーティストの全曲
                tracks = try store.tracks(byArtistId: artistId)
            } else {
                // 完全フラット: 全曲
                tracks = try store.allTracks()
            }
        } catch {
            tracks = []
            lastError = "曲一覧の読込に失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - 検索

    /// 検索クエリが空なら `searchHits` を空にして、 通常 3 ペイン表示へ。 非空なら incremental 検索を実行。
    public func performSearch() {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            searchHits = []
            return
        }
        do {
            searchHits = try store.search(trimmed)
        } catch {
            searchHits = []
            lastError = "検索に失敗: \(error.localizedDescription)"
        }
    }

    /// 検索中かどうか。
    public var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - スキャン

    /// 指定フォルダをスキャンして DB に upsert する。 進捗は `scanProgress` で publish。
    /// 既存スキャンが走っている場合は無視する (= caller 側で `scanProgress != nil` を見て抑制する想定)。
    public func scanFolder(_ folder: URL) async {
        guard scanProgress == nil else { return }
        scanProgress = ScanProgress(folder: folder, scanned: 0, currentURL: nil, state: .scanning)

        let scanner = self.scanner
        let store = self.store

        let result: Result<ScanResult, Error> = await Task.detached(priority: .userInitiated) {
            do {
                let scanResult = try await scanner.scan(folder: folder) { scanned, url in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.scanProgress = ScanProgress(
                            folder: folder,
                            scanned: scanned,
                            currentURL: url,
                            state: .scanning
                        )
                    }
                }
                return .success(scanResult)
            } catch {
                return .failure(error)
            }
        }.value

        switch result {
        case .success(let scanResult):
            scanProgress = ScanProgress(
                folder: folder,
                scanned: scanResult.tracks.count,
                currentURL: nil,
                state: .upserting
            )
            do {
                _ = try store.upsert(tracks: scanResult.tracks)
                scanProgress = ScanProgress(
                    folder: folder,
                    scanned: scanResult.tracks.count,
                    currentURL: nil,
                    state: .completed(tracks: scanResult.tracks.count, warnings: scanResult.warnings.count)
                )
                reloadAll()
                // アートワークは抽出に時間がかかるので背景で行い、 完了後に再読込してカバーを反映する。
                backfillArtwork(store: store)
            } catch {
                scanProgress = ScanProgress(
                    folder: folder,
                    scanned: 0,
                    currentURL: nil,
                    state: .failed(message: error.localizedDescription)
                )
                lastError = "DB 反映に失敗: \(error.localizedDescription)"
            }
        case .failure(let error):
            scanProgress = ScanProgress(
                folder: folder,
                scanned: 0,
                currentURL: nil,
                state: .failed(message: error.localizedDescription)
            )
            lastError = "スキャンに失敗: \(error.localizedDescription)"
        }
    }

    /// スキャン進捗 sheet を閉じる時に呼ぶ。
    public func dismissScanProgress() {
        scanProgress = nil
    }

    /// cover 未設定のアルバムのアートを背景 (= detached) で抽出・保存し、 反映があれば再読込する。
    /// `LibraryStore` は `Sendable` な値型なので detached task へ安全に渡せる。
    private func backfillArtwork(store: LibraryStore) {
        Task.detached(priority: .utility) { [weak self] in
            guard let artworkStore = try? ArtworkStore.applicationSupport() else { return }
            let updated = (try? ArtworkBackfiller(store: store, artworkStore: artworkStore).run()) ?? 0
            if updated > 0 {
                await self?.reloadAll()
            }
        }
    }

    // MARK: - 連携 hook (= AUD-6 再生エンジンへの橋渡し)

    /// ダブルクリック等で「即時再生」 を依頼する。 実体は `trackActions.playNow` に委譲。
    public func playNow(_ track: TrackRow) {
        trackActions.playNow(track)
    }

    /// 「再生キューに追加」 を依頼する。 実体は `trackActions.enqueue` に委譲。
    public func enqueue(_ track: TrackRow) {
        trackActions.enqueue(track)
    }
}
