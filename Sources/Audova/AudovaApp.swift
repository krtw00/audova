import SwiftUI
import AppKit
import AudovaCore

@main
struct AudovaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// ライブラリ画面のステート。 シーン全体で共有し、 メニュー (`LibraryCommands`) からも触れるようにする。
    @State private var libraryModel: LibraryViewModel

    /// プレイリスト画面のステート。 `libraryModel` と同じ `LibraryStore` を共有する。
    @State private var playlistModel: PlaylistViewModel

    /// 再生エンジン。 シーン全体で共有 (= TransportBarView から `@EnvironmentObject` で参照)。
    @StateObject private var player = Player()

    init() {
        // library / playlist で同一 LibraryStore を共有する (= 同じ DB を 2 つの DatabasePool で開かない)。
        // DB open はこの init で 1 回だけ行う。
        let store = AudovaApp.makeSharedStore()
        _libraryModel = State(initialValue: LibraryViewModel(store: store))
        _playlistModel = State(initialValue: PlaylistViewModel(store: store))
    }

    var body: some Scene {
        WindowGroup("Audova") {
            ContentView(libraryModel: libraryModel, playlistModel: playlistModel)
                .environmentObject(player)
                // scene focus 経由で PlaybackCommands に Player を渡す (= keyboard shortcut の event 伝播のため)。
                .focusedSceneObject(player)
                .onAppear {
                    // ライブラリ→再生エンジンの結線。 closure で疎結合化されているので、 ここで bind する。
                    let actions = LibraryTrackActions(
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
                        },
                        playPlaylist: { tracks, startIndex in
                            let items = tracks.map { track in
                                QueueItem(
                                    url: URL(fileURLWithPath: track.path),
                                    title: track.title
                                )
                            }
                            player.replaceQueue(items, startAt: startIndex)
                        }
                    )
                    libraryModel.trackActions = actions
                    playlistModel.trackActions = actions
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

    /// 起動時に 1 回だけ DB を開いて共有 `LibraryStore` を作る。
    /// open 失敗時は in-memory に fallback して最低限の画面は出す。
    private static func makeSharedStore() -> LibraryStore {
        do {
            let db = try LibraryDatabase.open(.applicationSupport)
            return LibraryStore(database: db)
        } catch {
            fputs("Audova: failed to open library DB on disk: \(error.localizedDescription). Falling back to in-memory.\n", stderr)
            // in-memory も失敗するなら起動できないので fatalError。 通常ありえない (= UUID で一意 tmp ファイル)。
            let db = try! LibraryDatabase.open(.inMemory)
            return LibraryStore(database: db)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)

        // SwiftPM executable は Info.plist の CFBundleIconFile を起動時に自動 load しない場合があるため、
        // Bundle.module から .icns を明示 load して NSApp.applicationIconImage に set する。
        if let iconURL = Bundle.module.url(forResource: "Audova", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApp.applicationIconImage = icon
        }

        NSApp.activate(ignoringOtherApps: true)

        // SwiftUI Commands では menu category 自体 (= File / Format / Help) を消せないため、
        // AppKit 経由で mainMenu を直接整形する。 SwiftUI が後から scene rebuild で復活させるので、
        // 複数 delay で cleanup を試みる + applicationDidBecomeActive でも追従。
        for delay in [0.0, 0.1, 0.5, 1.5] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                Self.adjustMainMenu()
            }
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // window 切替 / app アクティブ化のたびに cleanup (= SwiftUI の menu rebuild に追従)
        Self.adjustMainMenu()
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
