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

    func testDisplayTitleFallsBackToFileName() {
        let withTitle = QueueItem(url: URL(fileURLWithPath: "/tmp/x.flac"), title: "Song")
        XCTAssertEqual(withTitle.displayTitle, "Song")

        let withoutTitle = QueueItem(url: URL(fileURLWithPath: "/tmp/My Song.flac"))
        XCTAssertEqual(withoutTitle.displayTitle, "My Song")
    }
}
