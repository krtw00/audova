import SwiftUI
import AppKit
import AudovaCore

@main
struct AudovaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    /// ライブラリ画面のステート。 シーン全体で共有し、 メニュー (`LibraryCommands`) からも触れるようにする。
    /// DB open はこの init で 1 回だけ行う。
    @State private var libraryModel: LibraryViewModel = AudovaApp.makeLibraryViewModel()

    var body: some Scene {
        WindowGroup("Audova") {
            ContentView(libraryModel: libraryModel)
        }
        .windowResizability(.contentSize)
        .commands {
            LibraryCommands(model: libraryModel)
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
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
