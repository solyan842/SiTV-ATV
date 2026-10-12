import XCTest
@testable import SiTVATV

final class DASHLiveSegmentTrackerTests: XCTestCase {
    func testReturnsOnlySegmentsNewerThanSeededTimeline() {
        var tracker = DASHLiveSegmentTracker(
            seed: [
                makeSegment(number: 5, time: 8_000),
                makeSegment(number: 6, time: 10_000)
            ]
        )

        let unseen = tracker.unseenSegments(
            from: [
                makeSegment(number: 5, time: 8_000),
                makeSegment(number: 6, time: 10_000),
                makeSegment(number: 7, time: 12_000),
                makeSegment(number: 8, time: 14_000)
            ]
        )

        XCTAssertEqual(unseen.map(\.number), [7, 8])
        XCTAssertEqual(tracker.latestTime, 14_000)
        XCTAssertEqual(tracker.latestNumber, 8)
    }

    func testTimelineIdentityIgnoresChangedURLToken() {
        var tracker = DASHLiveSegmentTracker(
            seed: [makeSegment(number: 9, time: 16_000, token: "old")]
        )

        let unseen = tracker.unseenSegments(
            from: [makeSegment(number: 9, time: 16_000, token: "new")]
        )

        XCTAssertTrue(unseen.isEmpty)
    }

    func testFallsBackToSegmentNumberWithoutTimelineTime() {
        var tracker = DASHLiveSegmentTracker(
            seed: [makeSegment(number: 10, time: nil)]
        )

        let unseen = tracker.unseenSegments(
            from: [
                makeSegment(number: 9, time: nil),
                makeSegment(number: 10, time: nil),
                makeSegment(number: 11, time: nil)
            ]
        )

        XCTAssertEqual(unseen.map(\.number), [11])
        XCTAssertEqual(tracker.latestNumber, 11)
    }

    func testEmptyTrackerAcceptsSegmentNumberZero() {
        var tracker = DASHLiveSegmentTracker()

        let unseen = tracker.unseenSegments(
            from: [makeSegment(number: 0, time: 0)]
        )

        XCTAssertEqual(unseen.map(\.number), [0])
        XCTAssertEqual(tracker.latestTime, 0)
        XCTAssertEqual(tracker.latestNumber, 0)
    }

    private func makeSegment(
        number: UInt64,
        time: UInt64?,
        token: String = "token"
    ) -> DASHResolvedSegment {
        DASHResolvedSegment(
            number: number,
            time: time,
            duration: 2_000,
            url: URL(string: "https://example.com/seg-\(number).m4s?token=\(token)")!
        )
    }
}
