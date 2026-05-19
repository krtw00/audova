import SwiftUI
import AppKit
import AudovaCore

/// アプリケーションメニュー「ライブラリ」 を提供する `Commands`。
///
/// - フォルダを追加してスキャン... (= NSOpenPanel 起動 → `LibraryViewModel.scanFolder`)
/// - 再スキャン (= 最後にスキャンしたフォルダ、 無効なら disabled)
///
/// Phase 1 では「最後にスキャンしたフォルダ 1 件」 だけを `@AppStorage` で覚える。 複数フォルダ管理は Phase 2 以降。
struct LibraryCommands: Commands {
    let model: LibraryViewModel
    @AppStorage("audova.lastScannedFolder") private var lastScannedFolderPath: String = ""

    var body: some Commands {
        CommandMenu("ライブラリ") {
            Button("フォルダを追加してスキャン...") {
                pickFolderAndScan()
            }
            .keyboardShortcut("o", modifiers: [.command, .shift])

            Button("再スキャン") {
                rescan()
            }
            .keyboardShortcut("r", modifiers: [.command])
            .disabled(!hasValidLastFolder)
        }
    }

    private var hasValidLastFolder: Bool {
        !lastScannedFolderPath.isEmpty
            && FileManager.default.fileExists(atPath: lastScannedFolderPath)
    }

    /// NSOpenPanel でフォルダを選択し、 選ばれたらスキャンタスクを起動する。
    private func pickFolderAndScan() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "スキャン"
        panel.message = "ライブラリに取り込むフォルダを選択 (= 再帰スキャン)"
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return }
        lastScannedFolderPath = url.path
        Task { @MainActor in
            await model.scanFolder(url)
        }
    }

    private func rescan() {
        guard hasValidLastFolder else { return }
        let url = URL(fileURLWithPath: lastScannedFolderPath)
        Task { @MainActor in
            await model.scanFolder(url)
        }
    }
}
