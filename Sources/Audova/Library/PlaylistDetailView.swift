import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AudovaCore

/// プレイリスト選択時の detail 領域。 曲一覧を表示し、 ダブルクリックで先頭から再生する。
///
/// macOS の `Table` は `.onMove` 非対応のため `List+ForEach` で実装する。
/// `.onMove` でプレイリスト内の曲順を変更し、 `.onDelete` + context menu で削除できる。
struct PlaylistDetailView: View {
    @Bindable var model: PlaylistViewModel
    let playlistId: Int64

    /// 選択中の trackId セット (= `List` の selection binding 用)。
    @State private var selectedTrackIds: Set<Int64> = []

    /// 現在表示中のプレイリスト名。
    private var playlistName: String {
        model.playlists.first(where: { $0.id == playlistId })?.name ?? "Playlist"
    }

    var body: some View {
        Group {
            if model.selectedTracks.isEmpty {
                ContentUnavailableView(
                    "曲がありません",
                    systemImage: "music.note.list",
                    description: Text("ライブラリの曲を右クリックして「プレイリストに追加」から追加できます")
                )
            } else {
                List(selection: $selectedTrackIds) {
                    ForEach(model.selectedTracks, id: \.id) { track in
                        PlaylistTrackRow(
                            track: track,
                            index: model.selectedTracks.firstIndex(where: { $0.id == track.id }) ?? 0
                        )
                        .tag(track.id ?? 0)
                        .contextMenu {
                            playlistTrackContextMenu(for: track)
                        }
                    }
                    .onMove { source, destination in
                        var tracks = model.selectedTracks
                        tracks.move(fromOffsets: source, toOffset: destination)
                        model.reorderTracks(orderedTracks: tracks)
                    }
                    .onDelete { offsets in
                        model.removeTracks(atOffsets: offsets)
                    }
                }
                .listStyle(.inset)
                // ダブルクリック: 選択中最初の曲の index から再生。
                .onKeyPress(.return) {
                    playSelectedFirst()
                    return .handled
                }
                .simultaneousGesture(
                    TapGesture(count: 2).onEnded {
                        playSelectedFirst()
                    }
                )
            }
        }
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button {
                    exportAsM3U8()
                } label: {
                    Label("M3U8 でエクスポート", systemImage: "square.and.arrow.up")
                }
                .help("プレイリストを M3U8 ファイルにエクスポート")
                .disabled(model.selectedTracks.isEmpty)
            }
        }
        .onAppear {
            model.selectedPlaylistId = playlistId
        }
        .onChange(of: playlistId) { _, newId in
            model.selectedPlaylistId = newId
            selectedTrackIds = []
        }
    }

    // MARK: - helpers

    private func playSelectedFirst() {
        guard let firstId = selectedTrackIds.first,
              let idx = model.selectedTracks.firstIndex(where: { $0.id == firstId })
        else { return }
        model.playPlaylist(startAt: idx)
    }

    /// NSSavePanel を開き、 選択プレイリストを M3U8 ファイルに書き出す。
    private func exportAsM3U8() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(playlistName).m3u8"
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .data]
        panel.canCreateDirectories = true
        panel.message = "M3U8 プレイリストの保存先を選択してください"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let baseURL = url.deletingLastPathComponent()
        let content = M3U8Exporter.makeContent(tracks: model.selectedTracks, relativeTo: baseURL)
        do {
            try content.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            model.lastError = "エクスポートに失敗: \(error.localizedDescription)"
        }
    }

    @ViewBuilder
    private func playlistTrackContextMenu(for track: TrackRow) -> some View {
        if let idx = model.selectedTracks.firstIndex(where: { $0.id == track.id }) {
            Button("今すぐ再生") {
                model.playPlaylist(startAt: idx)
            }
            Divider()
        }
        Button("プレイリストから削除", role: .destructive) {
            guard let trackId = track.id,
                  let idx = model.selectedTracks.firstIndex(where: { $0.id == trackId })
            else { return }
            model.removeTracks(atOffsets: IndexSet([idx]))
        }
        Divider()
        Button("Finder で表示") {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: track.path)])
        }
    }
}

// MARK: - 曲行

/// プレイリスト内の 1 曲行。 `#`・タイトル・時間 の簡易レイアウト。
private struct PlaylistTrackRow: View {
    let track: TrackRow
    let index: Int

    var body: some View {
        HStack(spacing: 8) {
            Text(trackNoLabel)
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)

            Text(track.title ?? track.path.split(separator: "/").last.map(String.init) ?? track.path)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text(formatDuration(track.durationMs))
                .font(.body.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 2)
    }

    private var trackNoLabel: String {
        switch (track.discNo, track.trackNo) {
        case let (disc?, trackNo?):
            return "\(disc).\(String(format: "%02d", trackNo))"
        case (nil, let trackNo?):
            return String(format: "%02d", trackNo)
        default:
            return String(index + 1)
        }
    }

    private func formatDuration(_ ms: Int?) -> String {
        guard let ms, ms > 0 else { return "—" }
        let totalSeconds = ms / 1000
        let m = totalSeconds / 60
        let s = totalSeconds % 60
        return String(format: "%d:%02d", m, s)
    }
}
