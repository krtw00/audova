import SwiftUI
import SFBAudioEngine
import GRDB

struct ContentView: View {
    @State private var filePath: String = ""
    @State private var status: String = "ready"
    @State private var dbStatus: String = "—"
    private let player = AudioPlayer()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Audova spike")
                .font(.title2).bold()

            Text("audio file path (WAV/FLAC/...)")
                .font(.caption).foregroundStyle(.secondary)
            TextField("/Users/you/Music/sample.flac", text: $filePath)
                .textFieldStyle(.roundedBorder)

            HStack {
                Button("Play") { play() }
                    .keyboardShortcut(.return, modifiers: [])
                Button("Stop") { stop() }
                Spacer()
                Button("DB ping") { dbPing() }
            }

            Divider()
            Text("status: \(status)").font(.caption.monospaced())
            Text("db:     \(dbStatus)").font(.caption.monospaced())
        }
        .padding(20)
        .frame(width: 520, height: 240)
    }

    private func play() {
        let expanded = (filePath as NSString).expandingTildeInPath
        guard !expanded.isEmpty else {
            status = "error: empty path"
            return
        }
        let url = URL(fileURLWithPath: expanded)
        do {
            try player.play(url)
            status = "playing: \(url.lastPathComponent)"
        } catch {
            status = "error: \(error.localizedDescription)"
        }
    }

    private func stop() {
        player.stop()
        status = "stopped"
    }

    private func dbPing() {
        do {
            let dbq = try DatabaseQueue()
            try dbq.read { db in
                _ = try Row.fetchOne(db, sql: "SELECT sqlite_version()")
            }
            dbStatus = "GRDB ok (in-memory)"
        } catch {
            dbStatus = "GRDB error: \(error.localizedDescription)"
        }
    }
}
