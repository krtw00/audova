import XCTest
@testable import AudovaCore

final class PlaybackQueueTests: XCTestCase {
    private func item(_ name: String) -> QueueItem {
        QueueItem(url: URL(fileURLWithPath: "/tmp/\(name).flac"), title: name)
    }

    func testEmptyQueueHasNoCurrentNoNext() {
        let q = PlaybackQueue()
        XCTAssertNil(q.current)
        XCTAssertFalse(q.hasNext)
        XCTAssertFalse(q.hasPrevious)
    }

    func testReplaceAllStartsAtZeroByDefault() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c")])
        XCTAssertEqual(q.currentIndex, 0)
        XCTAssertEqual(q.current?.title, "a")
        XCTAssertTrue(q.hasNext)
        XCTAssertFalse(q.hasPrevious)
    }

    func testReplaceAllAtSpecificIndex() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c")], startAt: 2)
        XCTAssertEqual(q.current?.title, "c")
        XCTAssertFalse(q.hasNext)
        XCTAssertTrue(q.hasPrevious)
    }

    func testReplaceAllClampsOutOfRangeIndex() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b")], startAt: 99)
        XCTAssertEqual(q.current?.title, "b")
    }

    func testAdvanceMovesToNextThenStops() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b")])
        XCTAssertEqual(q.advance()?.title, "b")
        XCTAssertNil(q.advance()) // 末端到達でキュー停止
        XCTAssertNil(q.currentIndex)
    }

    func testRetreatStopsAtStart() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c")], startAt: 1)
        XCTAssertEqual(q.retreat()?.title, "a")
        XCTAssertEqual(q.retreat()?.title, "a") // 先頭で踏みとどまる
        XCTAssertEqual(q.currentIndex, 0)
    }

    func testPlayNowReplacesQueueWithSingleItem() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b")])
        q.playNow(item("z"))
        XCTAssertEqual(q.items.count, 1)
        XCTAssertEqual(q.current?.title, "z")
    }

    func testAppendKeepsCurrentIndex() {
        var q = PlaybackQueue()
        q.replaceAll([item("a")])
        q.append(item("b"))
        XCTAssertEqual(q.items.count, 2)
        XCTAssertEqual(q.current?.title, "a")
        XCTAssertTrue(q.hasNext)
    }

    func testJumpHonorsBounds() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c")])
        q.jump(to: 2)
        XCTAssertEqual(q.current?.title, "c")
        q.jump(to: 99) // 無視される
        XCTAssertEqual(q.current?.title, "c")
    }

    func testClearResetsAll() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b")])
        q.clear()
        XCTAssertTrue(q.items.isEmpty)
        XCTAssertNil(q.currentIndex)
    }

    // MARK: - シャッフル / リピート (AUD-14)

    func testSetShuffledKeepsCurrentAndItems() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c"), item("d")])
        q.setShuffled(true)
        XCTAssertTrue(q.isShuffled)
        XCTAssertEqual(q.current?.title, "a")             // 現在曲は先頭に残る
        XCTAssertEqual(q.items.map(\.title), ["a", "b", "c", "d"]) // items 自体は不変
    }

    func testShuffleVisitsEveryItemOnce() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c"), item("d")])
        q.setShuffled(true)
        var visited: [String] = [q.current!.title!]
        while let next = q.advance() { visited.append(next.title!) }
        XCTAssertEqual(visited.count, 4)                  // 全曲を 1 回ずつ
        XCTAssertEqual(Set(visited), ["a", "b", "c", "d"])
        XCTAssertEqual(visited.first, "a")                // 現在曲が先頭
    }

    func testUnshuffleRestoresOrderAndPosition() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c")], startAt: 1) // current b
        q.setShuffled(true)
        XCTAssertEqual(q.current?.title, "b")
        q.setShuffled(false)
        XCTAssertFalse(q.isShuffled)
        XCTAssertEqual(q.current?.title, "b")
        XCTAssertEqual(q.currentIndex, 1)                 // 元順序の位置に戻る
    }

    func testAdvanceWrapsToFirstWhenWrapTrue() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b")])
        XCTAssertEqual(q.advance()?.title, "b")
        XCTAssertEqual(q.advance(wrap: true)?.title, "a") // 末端 → 先頭
    }

    func testRetreatWrapsToLastWhenWrapTrue() {
        var q = PlaybackQueue()
        q.replaceAll([item("a"), item("b"), item("c")])   // current a
        XCTAssertEqual(q.retreat(wrap: true)?.title, "c") // 先頭 → 末尾
    }

    func testDisplayTitleFallsBackToFileName() {
        let withTitle = QueueItem(url: URL(fileURLWithPath: "/tmp/x.flac"), title: "Song")
        XCTAssertEqual(withTitle.displayTitle, "Song")

        let withoutTitle = QueueItem(url: URL(fileURLWithPath: "/tmp/My Song.flac"))
        XCTAssertEqual(withoutTitle.displayTitle, "My Song")
    }
}
