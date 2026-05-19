import SwiftUI
import AppKit
import AudovaCore

@main
struct AudovaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// ライブラリ画面のステート。 シーン全体で共有し、 メニュー (`LibraryCommands`) からも触れるようにする。
    /// DB open はこの init で 1 回だけ行う。
    @State private var libraryModel: LibraryViewModel = AudovaApp.makeLibraryViewModel()

    /// 再生エンジン。 シーン全体で共有 (= TransportBarView から `@EnvironmentObject` で参照)。
    @StateObject private var player = Player()

    var body: some Scene {
        WindowGroup("Audova") {
            ContentView(libraryModel: libraryModel)
                .environmentObject(player)
                // scene focus 経由で PlaybackCommands に Player を渡す (= keyboard shortcut の event 伝播のため)。
                .focusedSceneObject(player)
                .onAppear {
                    // ライブラリ→再生エンジンの結線。 closure で疎結合化されているので、 ここで bind する。
                    libraryModel.trackActions = LibraryTrackActions(
                        playNow: { track in
                            player.playNow(
                                QueueItem(
                                    url: URL(fileURLWithPath: track.path),
                                    title: track.title
                                )
                            )
                        },
                        enqueue: { track in
                            player.enqueue(
                                QueueItem(
                                    url: URL(fileURLWithPath: track.path),
                                    title: track.title
                                )
                            )
                        }
                    )
                }
        }
        .windowResizability(.contentSize)
        .commands {
            LibraryCommands(model: libraryModel)
            PlaybackCommands()

            // Audova で使わない macOS default menu を空にする (= 中身が英語で UX を散らかすため)。
            // 残すもの: App menu (= About / Quit) / 編集 (= Cut/Copy/Paste/Undo/Redo は検索 box 用に必要) /
            // 表示 (= Full Screen) / ウィンドウ (= Minimize/Zoom/Bring All)。
            // localization (= 残り menu の日本語化) は AUD 別 Issue で扱う。
            CommandGroup(replacing: .newItem) {}        // ファイル > 新規ウィンドウ
            CommandGroup(replacing: .saveItem) {}       // ファイル > 保存
            CommandGroup(replacing: .printItem) {}      // ファイル > プリント
            CommandGroup(replacing: .importExport) {}   // ファイル > Import / Export
            CommandGroup(replacing: .toolbar) {}        // 表示 > ツールバー
            CommandGroup(replacing: .sidebar) {}        // 表示 > サイドバー
            CommandGroup(replacing: .textFormatting) {} // 編集 > 書式
            CommandGroup(replacing: .help) {}           // ヘルプ
        }
    }

    /// 起動時に 1 回呼ばれる factory。 DB open に失敗したら in-memory に fallback して最低限の画面は出す。
    private static func makeLibraryViewModel() -> LibraryViewModel {
        let store: LibraryStore
        do {
            let db = try LibraryDatabase.open(.applicationSupport)
            store = LibraryStore(database: db)
        } catch {
            fputs("Audova: failed to open library DB on disk: \(error.localizedDescription). Falling back to in-memory.\n", stderr)
            // in-memory も失敗するなら起動できないので fatalError。 通常ありえない (= UUID で一意 tmp ファイル)。
            let db = try! LibraryDatabase.open(.inMemory)
            store = LibraryStore(database: db)
        }
        return LibraryViewModel(store: store)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI Commands では menu category 自体 (= File / Help) を消せないため、
        // AppKit 経由で mainMenu を直接整形する。 SwiftUI が menu bar を構築した後に走らせる
        // 必要があるので main runloop の次 tick で実行。
        DispatchQueue.main.async {
            Self.adjustMainMenu()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// menu bar の現状を stderr に出して、 不要な menu (= File / Help) を削除する。
    private static func adjustMainMenu() {
        guard let mainMenu = NSApp.mainMenu else {
            fputs("[Audova menu] NSApp.mainMenu is nil\n", stderr)
            return
        }

        let before = mainMenu.items.map { "\($0.submenu?.title ?? $0.title)" }
        fputs("[Audova menu] before: \(before)\n", stderr)

        let removeTitles: Set<String> = ["File", "ファイル", "Help", "ヘルプ", "Format", "フォーマット", "書式"]
        let toRemove = mainMenu.items.filter { item in
            removeTitles.contains(item.submenu?.title ?? "") || removeTitles.contains(item.title)
        }
        toRemove.forEach { mainMenu.removeItem($0) }

        let after = mainMenu.items.map { "\($0.submenu?.title ?? $0.title)" }
        fputs("[Audova menu] after: \(after)\n", stderr)
    }
}
