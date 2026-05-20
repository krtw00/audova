import Foundation

/// ライブラリスキャンの進行状況。 UI 側 (= sheet / status bar) から観測する snapshot。
public struct ScanProgress: Sendable, Equatable {
    public enum State: Sendable, Equatable {
        /// ファイル列挙 + メタデータ読込中。
        case scanning
        /// DB upsert 中 (= 列挙は終わって書込フェーズ)。
        case upserting
        /// 完了。 各件数を保持する。
        case completed(updated: Int, skipped: Int, deleted: Int, warnings: Int)
        /// 失敗。 ユーザー表示向けメッセージ。
        case failed(message: String)
    }

    /// スキャン対象のルートフォルダ。
    public let folder: URL
    /// 列挙済みファイル数 (= scanning フェーズのみ更新される)。
    public let scanned: Int
    /// 現在処理中のファイル URL (= UI で「いま読んでいるファイル名」 を表示する用)。
    public let currentURL: URL?
    public let state: State

    public init(folder: URL, scanned: Int, currentURL: URL?, state: State) {
        self.folder = folder
        self.scanned = scanned
        self.currentURL = currentURL
        self.state = state
    }

    public var isFinished: Bool {
        switch state {
        case .completed, .failed: return true
        case .scanning, .upserting: return false
        }
    }
}
