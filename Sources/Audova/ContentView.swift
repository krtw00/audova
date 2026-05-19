import SwiftUI
import AudovaCore

/// アプリケーションの root view。
///
/// 構成 (= 上から):
/// 1. ライブラリ領域 (= AUD-5: `LibraryView` で 3 ペイン + 検索)
/// 2. 下部 transport bar (= AUD-6: `TransportBarView`、 `Player` は `@EnvironmentObject` 経由)
struct ContentView: View {
    /// `AudovaApp` で生成 / 保持される `LibraryViewModel` を受け取る (= シーン全体で共有)。
    let libraryModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            LibraryView(model: libraryModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            TransportBarView()
        }
        .frame(minWidth: 880, minHeight: 520)
    }
}
