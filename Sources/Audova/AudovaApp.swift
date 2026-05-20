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

    /// メディアキー / コントロールセンター連携 (= 起動後に 1 回だけ生成)。
    @State private var nowPlayingController: NowPlayingController?

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
                    let store = libraryModel.store
                    let actions = LibraryTrackActions(
                        playNow: { track in
                            player.playNow(Self.makeQueueItem(from: track, store: store))
                        },
                        enqueue: { track in
                            player.enqueue(Self.makeQueueItem(from: track, store: store))
                        },
                        playPlaylist: { tracks, startIndex in
                            let items = tracks.map { Self.makeQueueItem(from: $0, store: store) }
                            player.replaceQueue(items, startAt: startIndex)
                        }
                    )
                    libraryModel.trackActions = actions
                    playlistModel.trackActions = actions

                    // メディアキー / コントロールセンターの「再生中」 を結線 (= 1 回だけ)。
                    if nowPlayingController == nil {
                        nowPlayingController = NowPlayingController(player: player)
                    }
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

    /// `TrackRow` → `QueueItem`。 アルバムアートのパスを store から解決して載せる (= 現在曲アート表示用)。
    private static func makeQueueItem(from track: TrackRow, store: LibraryStore) -> QueueItem {
        let artworkPath = (try? store.coverArtPath(forAlbumId: track.albumId)) ?? nil
        return QueueItem(
            url: URL(fileURLWithPath: track.path),
            title: track.title,
            artworkPath: artworkPath
        )
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

        // SwiftUI Commands では menu category 自体 (= File / Format / Help) を消せず、
        // SwiftUI は rebuild のたびに mainMenu へ復活させてくる。 mainMenu への item 追加を監視し、
        // 追加直後 (= 次の runloop) に整形することで、 タイトルがバーに残らないようにする。
        if let mainMenu = NSApp.mainMenu {
            NotificationCenter.default.addObserver(
                self, selector: #selector(mainMenuItemsDidChange),
                name: NSMenu.didAddItemNotification, object: mainMenu)
        }
        Self.adjustMainMenu()
    }

    /// SwiftUI が mainMenu に item を追加した直後に呼ばれる。 rebuild が一段落してから整形する
    /// (= SwiftUI の追加処理 iteration 中の mutation を避けるため async)。
    @objc private func mainMenuItemsDidChange(_ note: Notification) {
        DispatchQueue.main.async { Self.adjustMainMenu() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // app アクティブ化のたびにも追従 (= 監視を取りこぼした場合の保険)
        Self.adjustMainMenu()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    /// 常に不要な default menu (= File / Format / Help)。 SwiftUI が rebuild で何度でも作るので除去対象。
    private static let unwantedMenuTitles: Set<String> =
        ["File", "ファイル", "Help", "ヘルプ", "Format", "フォーマット", "書式"]

    /// mainMenu から不要 menu を除去する。
    /// (1) `unwantedMenuTitles` に一致するもの、 (2) 中身が空 or separator だけの menu (= 表示) を消す。
    private static func adjustMainMenu() {
        guard let mainMenu = NSApp.mainMenu else { return }
        let toRemove = mainMenu.items.filter { item in
            let title = item.submenu?.title ?? item.title
            if unwantedMenuTitles.contains(title) { return true }
            // submenu が無い / 空 / separator のみ = ユーザーが操作できる項目が無い → 除去
            if let sub = item.submenu, sub.items.allSatisfy(\.isSeparatorItem) { return true }
            return false
        }
        toRemove.forEach { mainMenu.removeItem($0) }
    }
}
