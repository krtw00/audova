import SwiftUI
import UniformTypeIdentifiers
import AudovaCore

/// サイドバーの選択状態を表す enum。
/// `ContentView` の `@State` で保持し、 `NavigationSplitView` の selection に bind する。
public enum SidebarSelection: Hashable {
    case library
    case playlist(Int64)
}

/// アプリ全体のサイドバー。 2 セクション構成:
/// - ライブラリ (固定 1 行)
/// - プレイリスト (0..n 行、 新規作成 / 名前変更 / 削除)
struct AppSidebar: View {
    @Bindable var playlistModel: PlaylistViewModel
    @Binding var selection: SidebarSelection?

    /// 新規プレイリスト作成 alert の表示フラグ。
    @State private var isCreatingPlaylist = false
    /// 新規プレイリスト名の入力バッファ。
    @State private var newPlaylistName = ""
    /// 名前変更中のプレイリスト ID。
    @State private var renamingPlaylistId: Int64? = nil
    /// 名前変更バッファ。
    @State private var renameBuffer = ""

    var body: some View {
        List(selection: $selection) {
            // MARK: ライブラリセクション
            Section("ライブラリ") {
                Label("ライブラリ", systemImage: "music.note.list")
                    .tag(SidebarSelection.library)
            }

            // MARK: プレイリストセクション
            Section {
                ForEach(playlistModel.playlists, id: \.id) { playlist in
                    playlistRow(playlist)
                        .tag(SidebarSelection.playlist(playlist.id ?? 0))
                }
            } header: {
                HStack {
                    Text("プレイリスト")
                    Spacer()
                    Button {
                        newPlaylistName = ""
                        isCreatingPlaylist = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.borderless)
                    .help("新規プレイリスト")
                }
            }
        }
        .listStyle(.sidebar)
        .task {
            playlistModel.reloadPlaylists()
        }
        // 新規プレイリスト作成 alert
        .alert("新規プレイリスト", isPresented: $isCreatingPlaylist) {
            TextField("プレイリスト名", text: $newPlaylistName)
            Button("作成") {
                let trimmed = newPlaylistName.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                do {
                    let created = try playlistModel.createPlaylist(name: trimmed)
                    if let id = created.id {
                        selection = .playlist(id)
                    }
                } catch {
                    playlistModel.lastError = "作成に失敗: \(error.localizedDescription)"
                }
            }
            Button("キャンセル", role: .cancel) {}
        }
        // 名前変更 alert
        .alert("名前を変更", isPresented: Binding(
            get: { renamingPlaylistId != nil },
            set: { if !$0 { renamingPlaylistId = nil } }
        )) {
            TextField("プレイリスト名", text: $renameBuffer)
            Button("変更") {
                guard let id = renamingPlaylistId else { return }
                let trimmed = renameBuffer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                do {
                    try playlistModel.renamePlaylist(id: id, to: trimmed)
                } catch {
                    playlistModel.lastError = "名前変更に失敗: \(error.localizedDescription)"
                }
                renamingPlaylistId = nil
            }
            Button("キャンセル", role: .cancel) { renamingPlaylistId = nil }
        }
    }

    @ViewBuilder
    private func playlistRow(_ playlist: Playlist) -> some View {
        Label(playlist.name, systemImage: "music.note.list")
            .lineLimit(1)
            .contextMenu {
                Button("名前を変更") {
                    renameBuffer = playlist.name
                    renamingPlaylistId = playlist.id
                }
                Divider()
                Button("削除", role: .destructive) {
                    guard let id = playlist.id else { return }
                    do {
                        try playlistModel.deletePlaylist(id: id)
                        // 削除したプレイリストが選択中なら選択を外す。
                        if selection == .playlist(id) {
                            selection = .library
                        }
                    } catch {
                        playlistModel.lastError = "削除に失敗: \(error.localizedDescription)"
                    }
                }
            }
            // ライブラリ曲行からのドロップを受け付ける。
            .onDrop(of: [UTType.audovaTrackIds], isTargeted: nil) { providers in
                guard let pid = playlist.id else { return false }
                for provider in providers {
                    provider.loadDataRepresentation(
                        forTypeIdentifier: UTType.audovaTrackIds.identifier
                    ) { data, _ in
                        guard let data, let ids = TrackDragPayload.decode(data) else { return }
                        Task { @MainActor in
                            do {
                                try playlistModel.addTracks(ids, toPlaylistId: pid)
                            } catch {
                                playlistModel.lastError = "追加に失敗: \(error.localizedDescription)"
                            }
                        }
                    }
                }
                return true
            }
    }
}
