import SwiftUI
import AudovaCore

/// アプリケーションの root view。
///
/// 構成:
/// - `NavigationSplitView` でサイドバー / detail の 2 ペイン構成
///   - サイドバー: `AppSidebar` (ライブラリ / プレイリスト 2 セクション)
///   - detail: `SidebarSelection` に応じて `LibraryView` または `PlaylistDetailView` を切り替え
/// - 下部: `TransportBarView` (再生コントロール)
struct ContentView: View {
    let libraryModel: LibraryViewModel
    let playlistModel: PlaylistViewModel

    /// サイドバーの選択状態。 nil は未選択だが、 `onAppear` で `.library` に初期化する。
    @State private var sidebarSelection: SidebarSelection? = .library

    var body: some View {
        VStack(spacing: 0) {
            NavigationSplitView {
                AppSidebar(playlistModel: playlistModel, selection: $sidebarSelection)
            } detail: {
                detailView
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            TransportBarView()
        }
        .frame(minWidth: 880, minHeight: 520)
    }

    @ViewBuilder
    private var detailView: some View {
        switch sidebarSelection {
        case .library, nil:
            LibraryView(model: libraryModel, playlistModel: playlistModel)
        case .playlist(let id):
            PlaylistDetailView(model: playlistModel, playlistId: id)
        }
    }
}
