import Foundation
import Observation

/// 静的プレイリスト画面を駆動する `@Observable` ステート (= AUD-8)。
///
/// `LibraryViewModel` と並置する独立 ViewModel。 `LibraryStore` の Playlist API を
/// main actor 上で呼び、 観測可能な配列に展開する。
/// 再生連携は `trackActions` (= `LibraryTrackActions`) 経由で外から差し込む。
@MainActor
@Observable
public final class PlaylistViewModel {
    // MARK: - 公開ステート

    /// サイドバーに並ぶ全プレイリスト。
    public private(set) var playlists: [Playlist] = []

    /// 選択中プレイリストのトラック一覧。 選択なしの時は空。
    public private(set) var selectedTracks: [TrackRow] = []

    /// 現在選択中のプレイリスト ID。
    public var selectedPlaylistId: Int64? {
        didSet {
            if oldValue != selectedPlaylistId {
                reloadSelectedTracks()
            }
        }
    }

    /// 直近のエラーメッセージ。
    public var lastError: String?

    // MARK: - 依存

    public let store: LibraryStore

    /// 再生連携 hook。 default は no-op。
    public var trackActions: LibraryTrackActions

    // MARK: - init

    public init(store: LibraryStore, trackActions: LibraryTrackActions = .noop) {
        self.store = store
        self.trackActions = trackActions
    }

    // MARK: - reload

    /// 全プレイリストを読み直す。 初回 / CRUD 操作後に呼ぶ。
    public func reloadPlaylists() {
        do {
            playlists = try store.allPlaylists()
            // 選択中プレイリストが消えていたら選択を外す。
            if let id = selectedPlaylistId, !playlists.contains(where: { $0.id == id }) {
                selectedPlaylistId = nil
            } else {
                reloadSelectedTracks()
            }
        } catch {
            lastError = "プレイリスト読込に失敗: \(error.localizedDescription)"
        }
    }

    /// 選択中プレイリストのトラックを読み直す。
    public func reloadSelectedTracks() {
        guard let id = selectedPlaylistId else {
            selectedTracks = []
            return
        }
        do {
            selectedTracks = try store.tracks(inPlaylistId: id)
        } catch {
            selectedTracks = []
            lastError = "曲一覧の読込に失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - CRUD

    /// 新規プレイリストを作成して一覧を更新する。
    @discardableResult
    public func createPlaylist(name: String) throws -> Playlist {
        let playlist = try store.createPlaylist(name: name)
        reloadPlaylists()
        return playlist
    }

    /// プレイリスト名を変更して一覧を更新する。
    public func renamePlaylist(id: Int64, to name: String) throws {
        try store.renamePlaylist(id: id, to: name)
        reloadPlaylists()
    }

    /// プレイリストを削除して一覧を更新する。
    public func deletePlaylist(id: Int64) throws {
        try store.deletePlaylist(id: id)
        reloadPlaylists()
    }

    /// トラックをプレイリスト末尾に追加し、 選択中ならトラック一覧を更新する。
    public func addTracks(_ trackIds: [Int64], toPlaylistId id: Int64) throws {
        try store.addTracks(trackIds, toPlaylistId: id)
        if selectedPlaylistId == id {
            reloadSelectedTracks()
        }
    }

    /// 選択中プレイリストの曲を並べ替えて永続化する。
    /// 呼び出し側 (= SwiftUI `.onMove`) で配列を並べ替えた後の結果を渡す。
    public func reorderTracks(orderedTracks: [TrackRow]) {
        guard let id = selectedPlaylistId else { return }
        // 楽観的に UI を先行更新し、 DB に永続化する。
        selectedTracks = orderedTracks
        let orderedIds = orderedTracks.compactMap(\.id)
        do {
            try store.reorderTracks(inPlaylistId: id, orderedTrackIds: orderedIds)
        } catch {
            lastError = "並べ替えに失敗: \(error.localizedDescription)"
            reloadSelectedTracks()
        }
    }

    /// 選択中プレイリストから指定 offsets の曲を削除する。
    /// `List.onDelete` が渡す `IndexSet` をそのまま受け取る。
    public func removeTracks(atOffsets offsets: IndexSet) {
        guard let id = selectedPlaylistId else { return }
        let trackIds = offsets.compactMap { selectedTracks[$0].id }
        guard !trackIds.isEmpty else { return }
        do {
            try store.removeTracks(trackIds, fromPlaylistId: id)
            reloadSelectedTracks()
        } catch {
            lastError = "削除に失敗: \(error.localizedDescription)"
        }
    }

    // MARK: - 再生連携

    /// 選択中プレイリストを指定 index から先頭再生。
    public func playPlaylist(startAt index: Int) {
        trackActions.playPlaylist(selectedTracks, index)
    }
}
