import Foundation

/// 再生キュー 1 件分。 URL 必須。 表示用メタは optional (= スキャン済みでも、 ad-hoc 再生で URL だけのこともあるため)。
public struct QueueItem: Sendable, Hashable, Identifiable {
    public let id: UUID
    public let url: URL
    public let title: String?
    public let artist: String?
    public let albumTitle: String?
    public let duration: TimeInterval?
    /// アルバムアートの保存先絶対パス (= `ArtworkStore` が書いたファイル)。 無ければ nil。
    public let artworkPath: String?

    public init(
        id: UUID = UUID(),
        url: URL,
        title: String? = nil,
        artist: String? = nil,
        albumTitle: String? = nil,
        duration: TimeInterval? = nil,
        artworkPath: String? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.artist = artist
        self.albumTitle = albumTitle
        self.duration = duration
        self.artworkPath = artworkPath
    }

    /// 表示タイトルが無ければファイル名 (= 拡張子除く) を fallback として使う。
    public var displayTitle: String {
        if let title, !title.isEmpty { return title }
        return url.deletingPathExtension().lastPathComponent
    }
}

/// 順序付き再生キュー。 `Player` から所有される値型として扱う (= 同時 mutate は `@MainActor` 側で保証)。
///
/// Phase 1 スコープ: シャッフル / リピートは持たない (= Phase 2 で導入)。 単純な ordered list + currentIndex。
public struct PlaybackQueue: Sendable {
    public private(set) var items: [QueueItem]
    /// 現在再生中の index。 `nil` ならキュー停止状態 (= 何も再生していない)。
    public private(set) var currentIndex: Int?

    public init(items: [QueueItem] = [], currentIndex: Int? = nil) {
        self.items = items
        self.currentIndex = currentIndex
    }

    public var current: QueueItem? {
        guard let i = currentIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }

    public var hasNext: Bool {
        guard let i = currentIndex else { return !items.isEmpty }
        return i + 1 < items.count
    }

    public var hasPrevious: Bool {
        guard let i = currentIndex else { return false }
        return i > 0
    }

    // MARK: - mutation

    /// 既存キューを完全に置き換えて、 指定 index から再生開始する。
    public mutating func replaceAll(_ newItems: [QueueItem], startAt index: Int = 0) {
        items = newItems
        currentIndex = newItems.isEmpty ? nil : max(0, min(index, newItems.count - 1))
    }

    /// 末尾に追加 (= キュー継続再生)。
    public mutating func append(_ item: QueueItem) {
        items.append(item)
    }

    public mutating func append(contentsOf newItems: [QueueItem]) {
        items.append(contentsOf: newItems)
    }

    /// 1 件を「今すぐ再生」用に置き換える (= 既存キューはクリア)。
    public mutating func playNow(_ item: QueueItem) {
        items = [item]
        currentIndex = 0
    }

    /// 次のトラックへ進める。 returns: 進めた後の current item (= 末端なら nil)。
    @discardableResult
    public mutating func advance() -> QueueItem? {
        guard hasNext else {
            currentIndex = nil
            return nil
        }
        currentIndex = (currentIndex ?? -1) + 1
        return current
    }

    /// 前のトラックへ戻る。 returns: 戻った後の current item (= 先頭ならそのまま)。
    @discardableResult
    public mutating func retreat() -> QueueItem? {
        guard let i = currentIndex, i > 0 else { return current }
        currentIndex = i - 1
        return current
    }

    public mutating func clear() {
        items = []
        currentIndex = nil
    }

    /// 指定 index へジャンプ。 範囲外なら無視。
    public mutating func jump(to index: Int) {
        guard items.indices.contains(index) else { return }
        currentIndex = index
    }
}
