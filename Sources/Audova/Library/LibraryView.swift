import SwiftUI
import AppKit
import UniformTypeIdentifiers
import AudovaCore

// TrackDragPayload / UTType.audovaTrackIds は TrackDragPayload.swift で定義。

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
                AlbumRow(title: album.title, year: album.year, isAll: false, coverArtPath: album.coverArtPath)
                    .tag(Optional<Int64>(album.id ?? 0))
                    .contextMenu {
                        if let id = album.id {
                            Button("アルバムを再生") { model.playAlbum(id) }
                            Button("キューに追加") { model.enqueueAlbum(id) }
                        }
                    }
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
    var coverArtPath: String? = nil

    var body: some View {
        HStack {
            if isAll {
                Image(systemName: "square.grid.2x2")
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
            } else {
                ArtworkImage(path: coverArtPath, size: 28)
            }
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
                    .onDrag {
                        // 選択中の曲をまとめてドラッグ。 未選択行を単独ドラッグした場合は
                        // その 1 曲だけを payload にする。
                        let ids: [Int64]
                        if let rowId = row.id, selectedTrackIds.contains(Optional(rowId)) {
                            ids = model.tracks.compactMap { t in
                                guard let tid = t.id, selectedTrackIds.contains(Optional(tid)) else { return nil }
                                return tid
                            }
                        } else {
                            ids = row.id.map { [$0] } ?? []
                        }
                        let provider = NSItemProvider()
                        if let data = TrackDragPayload.encode(ids) {
                            provider.registerDataRepresentation(
                                forTypeIdentifier: UTType.audovaTrackIds.identifier,
                                visibility: .ownProcess
                            ) { completion in
                                completion(data, nil)
                                return nil
                            }
                        }
                        return provider
                    }
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
            // ダブルクリック / Enter で、 現在のリストをその曲から末尾まで連続再生する。
            guard let first = ids.first.flatMap({ $0 }),
                  let index = model.tracks.firstIndex(where: { $0.id == first }) else { return }
            model.play(model.tracks, startAt: index)
        }
        .onCopyCommand {
            // Cmd+C で選択行のファイルパスを 1 行ずつ pasteboard へ。
            tracksToPathStringItems(for: selectedTrackIds)
        }
        // アルバム選択中は曲一覧の上に大アート + タイトル/年のヘッダーを差し込む。
        .safeAreaInset(edge: .top, spacing: 0) {
            if let album = model.selectedAlbum {
                VStack(spacing: 0) {
                    AlbumDetailHeader(
                        album: album,
                        trackCount: model.tracks.count,
                        onPlay: { model.play(model.tracks, startAt: 0) },
                        onEnqueue: { model.enqueueAll(model.tracks) }
                    )
                    Divider()
                }
            }
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
            if selected.count == 1, let t = selected.first,
               let index = model.tracks.firstIndex(where: { $0.id == t.id }) {
                Button("今すぐ再生") { model.play(model.tracks, startAt: index) }
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

// MARK: - アルバム詳細ヘッダー

/// アルバム選択時に曲一覧の上へ出す、 大アート + タイトル / 年 / 曲数のヘッダー。
private struct AlbumDetailHeader: View {
    let album: Album
    let trackCount: Int
    let onPlay: () -> Void
    let onEnqueue: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ArtworkImage(path: album.coverArtPath, size: 72, cornerRadius: 6)
            VStack(alignment: .leading, spacing: 4) {
                Text(album.title)
                    .font(.title3).bold()
                    .lineLimit(2)
                if let year = album.year {
                    Text(String(year))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Text("\(trackCount) 曲")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            HStack(spacing: 8) {
                Button(action: onPlay) {
                    Label("再生", systemImage: "play.fill")
                }
                .buttonStyle(.borderedProminent)
                Button(action: onEnqueue) {
                    Label("キューに追加", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .controlSize(.small)
            .disabled(trackCount == 0)
        }
        .padding(12)
        .background(.background)
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
                        .onDrag {
                            let ids: [Int64]
                            if hit.track.id != nil && selectedIds.contains(hit.track.path) {
                                ids = hits.compactMap { h in
                                    guard selectedIds.contains(h.track.path) else { return nil }
                                    return h.track.id
                                }
                            } else {
                                ids = hit.track.id.map { [$0] } ?? []
                            }
                            let provider = NSItemProvider()
                            if let data = TrackDragPayload.encode(ids) {
                                provider.registerDataRepresentation(
                                    forTypeIdentifier: UTType.audovaTrackIds.identifier,
                                    visibility: .ownProcess
                                ) { completion in
                                    completion(data, nil)
                                    return nil
                                }
                            }
                            return provider
                        }
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
