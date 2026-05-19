import SwiftUI
import AudovaCore

/// スキャン中 / 完了時に表示する sheet。 `LibraryViewModel.scanProgress` の状態を表示する。
struct ScanProgressSheet: View {
    let progress: ScanProgress
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: iconName)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                VStack(alignment: .leading) {
                    Text(headline).font(.headline)
                    Text(progress.folder.path)
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer()
            }

            switch progress.state {
            case .scanning:
                ProgressView(value: nil as Double?)
                    .progressViewStyle(.linear)
                VStack(alignment: .leading, spacing: 4) {
                    Text("読み取り済み: \(progress.scanned)")
                        .font(.caption.monospacedDigit())
                    if let url = progress.currentURL {
                        Text(url.lastPathComponent)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            case .upserting:
                ProgressView(value: nil as Double?)
                    .progressViewStyle(.linear)
                Text("DB に反映中... (\(progress.scanned) 件)")
                    .font(.caption.monospacedDigit())
            case .completed(let tracks, let warnings):
                VStack(alignment: .leading, spacing: 4) {
                    Text("反映: \(tracks) 件")
                    if warnings > 0 {
                        Text("警告: \(warnings) 件 (= メタデータ読取失敗 / 属性不明)")
                            .foregroundStyle(.orange)
                    }
                }
                .font(.callout)
            case .failed(let message):
                Text(message)
                    .font(.callout)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button(progress.isFinished ? "閉じる" : "バックグラウンドへ") {
                    onDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 460)
    }

    private var headline: String {
        switch progress.state {
        case .scanning:  return "ライブラリスキャン中..."
        case .upserting: return "DB 反映中..."
        case .completed: return "スキャン完了"
        case .failed:    return "スキャン失敗"
        }
    }

    private var iconName: String {
        switch progress.state {
        case .scanning, .upserting: return "arrow.triangle.2.circlepath"
        case .completed:            return "checkmark.circle.fill"
        case .failed:               return "xmark.octagon.fill"
        }
    }

    private var iconColor: Color {
        switch progress.state {
        case .scanning, .upserting: return .accentColor
        case .completed:            return .green
        case .failed:               return .red
        }
    }
}
