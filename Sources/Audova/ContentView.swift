import SwiftUI
import AudovaCore

/// アプリケーションの root view。
///
/// 構成 (= 上から):
/// 1. ライブラリ領域 (= AUD-5: `LibraryView` で 3 ペイン + 検索)
/// 2. 下部 transport bar 用 placeholder (= AUD-6 完走後にここを `TransportBarView()` で差し替える)
///
/// AUD-5 と AUD-6 が並列で同一 main を触るため、 root view は最小限の組み立てだけに留め、
/// ライブラリ実体は別ファイル (`Library/LibraryView.swift`) に分けてある。
struct ContentView: View {
    /// `AudovaApp` で生成 / 保持される `LibraryViewModel` を受け取る (= シーン全体で共有)。
    let libraryModel: LibraryViewModel

    var body: some View {
        VStack(spacing: 0) {
            LibraryView(model: libraryModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            // MARK: AUD-6 統合点
            // 下部 transport bar 用 placeholder。 AUD-6 完走後にここを TransportBarView() で差し替える。
            // (= 同時並列実装中の AUD-6 / Player への直接依存をこの commit では持たない方針)
            Divider()
            TransportBarPlaceholder()
        }
        .frame(minWidth: 880, minHeight: 520)
    }
}

/// AUD-6 完走後に `TransportBarView()` で差し替える灰色帯。
private struct TransportBarPlaceholder: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "play.fill").foregroundStyle(.tertiary)
            Text("再生バー (= AUD-6 統合後にここへ)")
                .font(.caption.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .frame(height: 56)
        .background(Color.gray.opacity(0.08))
    }
}
