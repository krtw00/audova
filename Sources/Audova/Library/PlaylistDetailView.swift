import SwiftUI
import AudovaCore

/// プレイリスト選択時の detail 領域。 曲一覧を表示し、 ダブルクリックで先頭から再生する。
struct PlaylistDetailView: View {
    @Bindable var model: PlaylistViewModel
    let playlistId: Int64

    @State private var selectedTrackIds: Set<TrackRow.ID> = []

    var body: some View {
        Group {
            if model.selectedTracks.isEmpty {
                ContentUnavailableView(
                    "曲がありません",
                    systemImage: "music.note.list",
                    description: Text("ライブラリの曲を右クリックして「プレイリストに追加」から追加できます")
                )
            } else {
                Table(model.selectedTracks, selection: $selectedTrackIds) {
                    TableColumn("#") { row in
                        Text(trackNoLabel(row))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 28, ideal: 36, max: 48)

                    TableColumn("タイトル") { row in
                        Text(row.title ?? row.path.split(separator: "/").last.map(String.init) ?? row.path)
                            .lineLimit(1)
                    }
                    .width(min: 160, ideal: 280)

                    TableColumn("時間") { row in
                        Text(formatDuration(row.durationMs))
                            .font(.body.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 56, ideal: 60, max: 80)

                    TableColumn("コーデック") { row in
                        Text(row.codec.uppercased())
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    .width(min: 60, ideal: 72, max: 96)
                }
                .contextMenu(forSelectionType: TrackRow.ID.self) { ids in
                    let selected = ids.compactMap { id -> TrackRow? in
                        guard let id = id else { return nil }
                        return trackById(id)
                    }
                    if !selected.isEmpty {
                        if selected.count == 1, let t = selected.first {
                            Button("今すぐ再生") {
                                let idx = model.selectedTracks.firstIndex(where: { $0.id == t.id }) ?? 0
                                model.playPlaylist(startAt: idx)
                            }
                        }
                        Divider()
                        Button("Finder で表示") {
                            NSWorkspace.shared.activateFileViewerSelecting(
                                selected.map { URL(fileURLWithPath: $0.path) }
                            )
                        }
                    }
                } primaryAction: { ids in
                    // ダブルクリック / Enter で選択曲の index から再生。
                    guard let firstId = ids.first.flatMap({ $0 }),
                          let track = trackById(firstId),
                          let idx = model.selectedTracks.firstIndex(where: { $0.id == track.id })
                    else { return }
                    model.playPlaylist(startAt: idx)
                }
            }
        }
        .onAppear {
            // playlistId が変わるたびに detail が再描画されるので、 ここで選択プレイリストを同期。
            model.selectedPlaylistId = playlistId
        }
        .onChange(of: playlistId) { _, newId in
            model.selectedPlaylistId = newId
            selectedTrackIds = []
        }
    }

    private func trackById(_ id: Int64) -> TrackRow? {
        model.selectedTracks.first { $0.id == id }
    }

    private func trackNoLabel(_ row: TrackRow) -> String {
        switch (row.discNo, row.trackNo) {
        case let (disc?, track?):
            return "\(disc).\(String(format: "%02d", track))"
        case (nil, let track?):
            return String(format: "%02d", track)
        default:
            return "—"
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
