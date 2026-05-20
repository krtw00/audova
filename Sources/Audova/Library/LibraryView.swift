import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AudovaCore

/// ライブラリ画面のルート。 上に検索バー、 下に 3 ペイン (= アーティスト / アルバム / 曲)。
///
/// NavigationSplitView の detail として再利用される。 サイドバーは `ContentView` 側が持つ。
struct LibraryView: View {
    @Bindable var model: LibraryViewModel
    var playlistModel: PlaylistViewModel? = nil

    /// スキャンするフォルダを選ぶ NSOpenPanel を表示中かどうか (= 多重起動防止)。
    @State private var isShowingFolderPicker = false

    var body: some View {
        VStack(spacing: 0) {
            LibrarySearchBar(text: $model.searchQuery)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)

            Divider()

            if model.isSearching {
                SearchResultsView(hits: model.searchHits, model: model, playlistModel: playlistModel)
            } else {
                ThreePaneLibraryView(model: model, playlistModel: playlistModel)
            }
        }
        .frame(minWidth: 720, minHeight: 360)
        .sheet(isPresented: Binding(
            get: { model.scanProgress != nil },
            set: { newValue in if !newValue { model.dismissScanProgress() } }
        )) {
            if let progress = model.scanProgress {
                ScanProgressSheet(progress: progress) {
                    model.dismissScanProgress()
                }
            }
        }
        .task {
            model.reloadAll()
        }
    }
}

// MARK: - 3 ペイン本体

private struct ThreePaneLibraryView: View {
    @Bindable var model: LibraryViewModel
    var playlistModel: PlaylistViewModel?

    var body: some View {
        HSplitView {
            ArtistListPane(model: model)
                .frame(minWidth: 160, idealWidth: 220, maxWidth: 320)
            AlbumListPane(model: model)
                .frame(minWidth: 180, idealWidth: 260, maxWidth: 400)
            TrackListPane(model: model, playlistModel: playlistModel)
                .frame(minWidth: 320)
        }
    }
}

// MARK: - 左ペイン: アーティスト

private struct ArtistListPane: View {
    @Bindable var model: LibraryViewModel

    var body: some View {
        List(selection: artistSelectionBinding) {
            // 「全アーティスト」フラット行。 nil = フラット。
            ArtistRow(name: "全アーティスト", count: model.artists.count, isAll: true)
                .tag(Optional<Int64>.none)
            ForEach(model.artists, id: \.id) { artist in
                ArtistRow(name: artist.name, count: nil, isAll: false)
                    .tag(Optional<Int64>(artist.id ?? 0))
            }
        }
        .listStyle(.sidebar)
    }

    /// `Optional<Int64>` selection を `selectedArtistId` に橋渡しする。 `id == 0` は無効値 (= 防御的に nil 化)。
    private var artistSelectionBinding: Binding<Int64?> {
        Binding(
            get: { model.selectedArtistId },
            set: { newValue in
                if let v = newValue, v != 0 {
                    model.selectedArtistId = v
                } else {
                    model.selectedArtistId = nil
                }
            }
        )
    }
}

private struct ArtistRow: View {
    let name: String
    let count: Int?
    let isAll: Bool

    var body: some View {
        HStack {
            Image(systemName: isAll ? "person.3.fill" : "person.fill")
                .foregroundStyle(isAll ? .secondary : .primary)
            Text(name)
                .lineLimit(1)
            Spacer()
            if let count {
                Text("\(count)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - 中央ペイン: アルバム

private struct AlbumListPane: View {
    @Bindable var model: LibraryViewModel

    var body: some View {
        List(selection: albumSelectionBinding) {
            AlbumRow(title: model.selectedArtistId == nil ? "全アルバム" : "全曲 (アーティスト)", year: nil, isAll: true)
                .tag(Optional<Int64>.none)
            ForEach(model.albums, id: \.id) { album in
                AlbumRow(title: album.title, year: album.year, isAll: false)
                    .tag(Optional<Int64>(album.id ?? 0))
            }
        }
        .listStyle(.inset)
    }

    private var albumSelectionBinding: Binding<Int64?> {
        Binding(
            get: { model.selectedAlbumId },
            set: { newValue in
                if let v = newValue, v != 0 {
                    model.selectedAlbumId = v
                } else {
                    model.selectedAlbumId = nil
                }
            }
        )
    }
}

private struct AlbumRow: View {
    let title: String
    let year: Int?
    let isAll: Bool

    var body: some View {
        HStack {
            Image(systemName: isAll ? "square.grid.2x2" : "opticaldisc")
                .foregroundStyle(isAll ? .secondary : .primary)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .lineLimit(1)
                if let year {
                    Text(String(year))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
    }
}

// MARK: - 右ペイン: トラック

private struct TrackListPane: View {
    @Bindable var model: LibraryViewModel
    var playlistModel: PlaylistViewModel?
    /// `TrackRow` の `Identifiable.ID` は `Int64?` (= DB rowid)。 SwiftUI が要求する Set 型に合わせる。
    /// nil 値は永続化前のレコードだけで、 ライブラリビューには出ないので実害なし。
    @State private var selectedTrackIds: Set<TrackRow.ID> = []

    var body: some View {
        Table(model.tracks, selection: $selectedTrackIds) {
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

            TableColumn("サンプルレート") { row in
                Text(formatSampleRate(row.sampleRate, bitDepth: row.bitDepth))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            .width(min: 90, ideal: 110, max: 140)
        }
        .contextMenu(forSelectionType: TrackRow.ID.self) { ids in
            trackContextMenu(for: ids)
        } primaryAction: { ids in
            // ダブルクリック / Enter で即時再生。
            guard let first = ids.first.flatMap({ $0 }), let track = trackById(first) else { return }
            model.playNow(track)
        }
        .onCopyCommand {
            // Cmd+C で選択行のファイルパスを 1 行ずつ pasteboard へ。
            tracksToPathStringItems(for: selectedTrackIds)
        }
    }

    /// `#` 列の表示。 disc/track 番号が両方ある時は "1.04"、 track のみなら "04"、 無ければ "—"。
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

    private func formatSampleRate(_ rate: Double?, bitDepth: Int?) -> String {
        guard let rate, rate > 0 else { return "—" }
        let khz = rate / 1000.0
        let rateStr: String
        if khz.truncatingRemainder(dividingBy: 1) == 0 {
            rateStr = "\(Int(khz))kHz"
        } else {
            rateStr = String(format: "%.1fkHz", khz)
        }
        if let bitDepth, bitDepth > 0 {
            return "\(bitDepth)/\(rateStr)"
        }
        return rateStr
    }

    private func trackById(_ id: Int64) -> TrackRow? {
        model.tracks.first { $0.id == id }
    }

    @ViewBuilder
    private func trackContextMenu(for ids: Set<TrackRow.ID>) -> some View {
        let selected = ids.compactMap { id -> TrackRow? in
            guard let id = id else { return nil }
            return trackById(id)
        }
        if !selected.isEmpty {
            Button("再生キューに追加") {
                for t in selected { model.enqueue(t) }
            }
            if selected.count == 1, let t = selected.first {
                Button("今すぐ再生") { model.playNow(t) }
            }
            // プレイリストに追加サブメニュー
            if let pm = playlistModel, !pm.playlists.isEmpty {
                Divider()
                Menu("プレイリストに追加") {
                    ForEach(pm.playlists, id: \.id) { playlist in
                        Button(playlist.name) {
                            let trackIds = selected.compactMap(\.id)
                            guard !trackIds.isEmpty, let pid = playlist.id else { return }
                            do {
                                try pm.addTracks(trackIds, toPlaylistId: pid)
                            } catch {
                                pm.lastError = "追加に失敗: \(error.localizedDescription)"
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Finder で表示") {
                let urls = selected.map { URL(fileURLWithPath: $0.path) }
                NSWorkspace.shared.activateFileViewerSelecting(urls)
            }
            Button("ファイルパスをコピー") {
                let paths = selected.map(\.path).joined(separator: "\n")
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(paths, forType: .string)
            }
        }
    }

    /// Cmd+C で書き出す内容 (= 1 行 1 path のテキスト)。
    private func tracksToPathStringItems(for ids: Set<TrackRow.ID>) -> [NSItemProvider] {
        let unwrapped: Set<Int64> = Set(ids.compactMap { $0 })
        let paths = model.tracks
            .filter { $0.id.map { unwrapped.contains($0) } ?? false }
            .map(\.path)
            .joined(separator: "\n")
        guard !paths.isEmpty else { return [] }
        return [NSItemProvider(object: paths as NSString)]
    }
}

// MARK: - 検索バー

private struct LibrarySearchBar: View {
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
            TextField("タイトル / アーティスト / アルバムを検索", text: $text)
                .textFieldStyle(.roundedBorder)
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

// MARK: - 検索結果ビュー (= 3 ペイン置き換え)

private struct SearchResultsView: View {
    let hits: [TrackSearchHit]
    @Bindable var model: LibraryViewModel
    var playlistModel: PlaylistViewModel?
    /// `TrackSearchHit` の id は `track.path` (= `String`、 UNIQUE)。
    @State private var selectedIds: Set<String> = []

    var body: some View {
        if hits.isEmpty {
            ContentUnavailableView(
                "ヒットなし",
                systemImage: "magnifyingglass",
                description: Text("「\(model.searchQuery)」 に一致する曲がライブラリにありません")
            )
        } else {
            Table(hits, selection: $selectedIds) {
                TableColumn("タイトル") { hit in
                    Text(hit.track.title ?? hit.track.path)
                        .lineLimit(1)
                }
                TableColumn("アーティスト") { hit in
                    Text(hit.artistName ?? "—")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                TableColumn("アルバム") { hit in
                    Text(hit.albumTitle ?? "—")
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                }
                TableColumn("コーデック") { hit in
                    Text(hit.track.codec.uppercased())
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                }
                .width(min: 60, ideal: 72, max: 96)
            }
            .contextMenu(forSelectionType: String.self) { ids in
                let selected = ids.compactMap { id in hits.first { $0.track.path == id }?.track }
                if !selected.isEmpty {
                    Button("再生キューに追加") {
                        for t in selected { model.enqueue(t) }
                    }
                    if selected.count == 1, let t = selected.first {
                        Button("今すぐ再生") { model.playNow(t) }
                    }
                    if let pm = playlistModel, !pm.playlists.isEmpty {
                        Divider()
                        Menu("プレイリストに追加") {
                            ForEach(pm.playlists, id: \.id) { playlist in
                                Button(playlist.name) {
                                    let trackIds = selected.compactMap(\.id)
                                    guard !trackIds.isEmpty, let pid = playlist.id else { return }
                                    do {
                                        try pm.addTracks(trackIds, toPlaylistId: pid)
                                    } catch {
                                        pm.lastError = "追加に失敗: \(error.localizedDescription)"
                                    }
                                }
                            }
                        }
                    }
                    Divider()
                    Button("Finder で表示") {
                        NSWorkspace.shared.activateFileViewerSelecting(selected.map { URL(fileURLWithPath: $0.path) })
                    }
                }
            } primaryAction: { ids in
                guard let first = ids.first, let track = hits.first(where: { $0.track.path == first })?.track else { return }
                model.playNow(track)
            }
        }
    }
}
