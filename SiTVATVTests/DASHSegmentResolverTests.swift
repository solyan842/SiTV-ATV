import XCTest
@testable import SiTVATV

final class DASHSegmentResolverTests: XCTestCase {
    func testResolvesInitializationAndTimelineSegments() throws {
        let representation = makeRepresentation(
            bandwidth: 2_500_000,
            template: DASHSegmentTemplate(
                initialization: "init-$RepresentationID$-$Bandwidth$.mp4",
                media: "$RepresentationID$-$Number%05d$-$Time$.m4s",
                timescale: 1000,
                duration: nil,
                startNumber: 5,
                presentationTimeOffset: 0,
                timeline: [
                    DASHSegmentTimelineEntry(startTime: 40, duration: 2000, repeatCount: 2),
                    DASHSegmentTimelineEntry(startTime: nil, duration: 3000, repeatCount: 0)
                ]
            )
        )

        let resolver = DASHSegmentResolver()
        XCTAssertEqual(
            try resolver.initializationURL(for: representation).absoluteString,
            "https://example.com/video/init-720p-2500000.mp4"
        )

        let segments = try resolver.mediaSegments(for: representation, maxCount: 4)
        XCTAssertEqual(segments.map(\.number), [5, 6, 7, 8])
        XCTAssertEqual(segments.map(\.time), [40, 2040, 4040, 6040])
        XCTAssertEqual(segments.map(\.duration), [2000, 2000, 2000, 3000])
        XCTAssertEqual(
            segments.map { $0.url.absoluteString },
            [
                "https://example.com/video/720p-00005-40.m4s",
                "https://example.com/video/720p-00006-2040.m4s",
                "https://example.com/video/720p-00007-4040.m4s",
                "https://example.com/video/720p-00008-6040.m4s"
            ]
        )
    }

    func testLatestSelectionReturnsTimelineTail() throws {
        let representation = makeRepresentation(
            template: DASHSegmentTemplate(
                initialization: "init.mp4",
                media: "$Number$-$Time$.m4s",
                timescale: 1000,
                duration: nil,
                startNumber: 10,
                presentationTimeOffset: 0,
                timeline: [
                    DASHSegmentTimelineEntry(startTime: 1_000, duration: 2_000, repeatCount: 5)
                ]
            )
        )

        let segments = try DASHSegmentResolver().mediaSegments(
            for: representation,
            maxCount: 3,
            selection: .latest
        )

        XCTAssertEqual(segments.map(\.number), [13, 14, 15])
        XCTAssertEqual(segments.map(\.time), [7_000, 9_000, 11_000])
        XCTAssertEqual(
            segments.map { $0.url.lastPathComponent },
            ["13-7000.m4s", "14-9000.m4s", "15-11000.m4s"]
        )
    }

    func testResolvesDurationOnlySegmentsAndEscapedDollar() throws {
        let representation = makeRepresentation(
            bandwidth: 128_000,
            template: DASHSegmentTemplate(
                initialization: "init-$$-$RepresentationID$.mp4",
                media: "chunk-$Number$-$Time%06d$.m4s",
                timescale: 48_000,
                duration: 96_000,
                startNumber: 1,
                presentationTimeOffset: 0,
                timeline: []
            )
        )

        let resolver = DASHSegmentResolver()
        XCTAssertEqual(
            try resolver.initializationURL(for: representation).absoluteString,
            "https://example.com/video/init-$-720p.mp4"
        )

        let segments = try resolver.mediaSegments(for: representation, maxCount: 3)
        XCTAssertEqual(segments.map(\.number), [1, 2, 3])
        XCTAssertEqual(segments.map(\.time), [0, 96_000, 192_000])
        XCTAssertEqual(segments[2].url.absoluteString, "https://example.com/video/chunk-3-192000.m4s")
    }

    func testRejectsNegativeTimelineRepeatUntilPeriodBoundaryIsAvailable() {
        let representation = makeRepresentation(
            template: DASHSegmentTemplate(
                initialization: "init.mp4",
                media: "$Time$.m4s",
                timescale: 1000,
                duration: nil,
                startNumber: 1,
                presentationTimeOffset: 0,
                timeline: [DASHSegmentTimelineEntry(startTime: 0, duration: 2000, repeatCount: -1)]
            )
        )

        XCTAssertThrowsError(
            try DASHSegmentResolver().mediaSegments(for: representation, maxCount: 5)
        ) { error in
            XCTAssertEqual(error as? DASHSegmentResolverError, .unsupportedNegativeRepeat)
        }
    }

    func testMissingBandwidthFailsOnlyWhenTemplateUsesBandwidth() throws {
        let representation = makeRepresentation(
            bandwidth: nil,
            template: DASHSegmentTemplate(
                initialization: "init.mp4",
                media: "$Bandwidth$-$Number$.m4s",
                timescale: 1,
                duration: 1,
                startNumber: 1,
                presentationTimeOffset: 0,
                timeline: []
            )
        )

        XCTAssertThrowsError(
            try DASHSegmentResolver().mediaSegments(for: representation, maxCount: 1)
        ) { error in
            XCTAssertEqual(error as? DASHSegmentResolverError, .missingBandwidth)
        }
    }

    private func makeRepresentation(
        bandwidth: Int? = 1_000_000,
        template: DASHSegmentTemplate
    ) -> DASHRepresentation {
        DASHRepresentation(
            id: "720p",
            bandwidth: bandwidth,
            width: 1280,
            height: 720,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: URL(string: "https://example.com/video/")!,
            segmentTemplate: template,
            contentProtections: []
        )
    }
}
