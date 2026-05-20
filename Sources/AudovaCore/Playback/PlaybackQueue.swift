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
/// `items` は元の並び (= 安定) を保持し、 再生順序は `order` (= `items` index の列) で表す。
/// シャッフル off では `order` は恒等 (0,1,2,…)。 リピートはキュー自身は持たず、
/// `Player` が `advance(wrap:)` / `retreat(wrap:)` の `wrap` で末端の回り込みを制御する。
public struct PlaybackQueue: Sendable {
    public private(set) var items: [QueueItem]

    /// 再生順序 (= `items` のインデックス列)。 シャッフル off では恒等。
    private var order: [Int]
    /// `order` 内の現在位置。 `nil` なら停止状態 (= 何も再生していない)。
    private var position: Int?

    /// シャッフル中か。
    public private(set) var isShuffled: Bool

    public init(items: [QueueItem] = [], currentIndex: Int? = nil) {
        self.items = items
        self.order = Array(items.indices)
        self.isShuffled = false
        if let i = currentIndex, items.indices.contains(i) {
            self.position = i   // 恒等順なので order 内位置 == items index
        } else {
            self.position = nil
        }
    }

    // MARK: - 読み取り

    /// 現在再生中の `items` index。 `nil` なら停止。
    public var currentIndex: Int? {
        guard let p = position, order.indices.contains(p) else { return nil }
        return order[p]
    }

    public var current: QueueItem? {
        guard let i = currentIndex, items.indices.contains(i) else { return nil }
        return items[i]
    }

    public var hasNext: Bool {
        guard let p = position else { return !items.isEmpty }
        return p + 1 < order.count
    }

    public var hasPrevious: Bool {
        guard let p = position else { return false }
        return p > 0
    }

    // MARK: - シャッフル

    /// シャッフルを切り替える。 on にすると現在曲を先頭に残して残りをシャッフル、
    /// off にすると元順序へ戻し現在曲の位置を保つ。
    public mutating func setShuffled(_ on: Bool) {
        guard on != isShuffled else { return }
        isShuffled = on
        let current = currentIndex
        if on {
            var rest = Array(items.indices)
            if let cur = current { rest.removeAll { $0 == cur } }
            rest.shuffle()
            order = (current.map { [$0] } ?? []) + rest
            position = (current == nil) ? nil : 0
        } else {
            order = Array(items.indices)
            position = current   // 恒等順なので items index をそのまま位置に
        }
    }

    // MARK: - mutation

    /// 既存キューを完全に置き換えて、 指定 index から再生開始する。
    /// シャッフル中なら指定 index を先頭に残し、 残りをシャッフルする。
    public mutating func replaceAll(_ newItems: [QueueItem], startAt index: Int = 0) {
        items = newItems
        guard !newItems.isEmpty else {
            order = []
            position = nil
            return
        }
        let start = max(0, min(index, newItems.count - 1))
        if isShuffled {
            var rest = Array(newItems.indices)
            rest.removeAll { $0 == start }
            rest.shuffle()
            order = [start] + rest
            position = 0
        } else {
            order = Array(newItems.indices)
            position = start
        }
    }

    /// 末尾に追加 (= キュー継続再生)。 再生順序の末尾にも積む。
    public mutating func append(_ item: QueueItem) {
        items.append(item)
        order.append(items.count - 1)
    }

    public mutating func append(contentsOf newItems: [QueueItem]) {
        for item in newItems { append(item) }
    }

    /// 1 件を「今すぐ再生」用に置き換える (= 既存キューはクリア)。
    public mutating func playNow(_ item: QueueItem) {
        items = [item]
        order = [0]
        position = 0
    }

    /// 次のトラックへ進める。 `wrap` が true なら末端で先頭へ回り込む (= リピート all)。
    /// returns: 進めた後の current item (= 末端かつ wrap=false なら nil で停止)。
    @discardableResult
    public mutating func advance(wrap: Bool = false) -> QueueItem? {
        guard !order.isEmpty else {
            position = nil
            return nil
        }
        guard let p = position else {
            position = 0   // 停止状態からは先頭
            return current
        }
        if p + 1 < order.count {
            position = p + 1
            return current
        }
        if wrap {
            position = 0
            return current
        }
        position = nil
        return nil
    }

    /// 前のトラックへ戻る。 `wrap` が true なら先頭で末尾へ回り込む。
    /// returns: 戻った後の current item (= 先頭かつ wrap=false ならそのまま)。
    @discardableResult
    public mutating func retreat(wrap: Bool = false) -> QueueItem? {
        guard !order.isEmpty else { return nil }
        guard let p = position else { return current }
        if p > 0 {
            position = p - 1
            return current
        }
        if wrap {
            position = order.count - 1
            return current
        }
        return current   // 先頭で踏みとどまる
    }

    public mutating func clear() {
        items = []
        order = []
        position = nil
    }

    /// 指定 `items` index へジャンプ。 範囲外なら無視。
    public mutating func jump(to index: Int) {
        guard items.indices.contains(index) else { return }
        if let p = order.firstIndex(of: index) { position = p }
    }
}
