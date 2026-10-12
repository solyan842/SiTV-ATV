import XCTest
@testable import SiTVATV

final class DASHPlaybackRefreshPlanTests: XCTestCase {
    func testRefreshPreservesActiveRepresentationAndUsesLatestWindow() throws {
        let active = makeRepresentation(
            id: "active",
            bandwidth: 4_000_000,
            repeatCount: 5
        )
        let higher = makeRepresentation(
            id: "higher",
            bandwidth: 12_000_000,
            repeatCount: 5
        )
        let current = DASHPlaybackPlan(
            video: DASHTrackPlan(
                representation: active,
                initializationURL: URL(string: "https://example.com/live/init-active.mp4")!,
                mediaSegments: []
            ),
            audio: nil
        )
        let manifest = makeManifest(representations: [active, higher])

        let refreshed = try DASHPlaybackPlanner().refreshPlan(
            from: manifest,
            preserving: current,
            segmentCount: 2
        )

        XCTAssertEqual(refreshed.video?.representation.id, "active")
        XCTAssertEqual(refreshed.video?.mediaSegments.map(\.number), [5, 6])
        XCTAssertEqual(refreshed.video?.mediaSegments.map(\.time), [8_000, 10_000])
    }

    func testRefreshFailsWhenActiveRepresentationDisappears() throws {
        let active = makeRepresentation(
            id: "active",
            bandwidth: 4_000_000,
            repeatCount: 2
        )
        let current = DASHPlaybackPlan(
            video: DASHTrackPlan(
                representation: active,
                initializationURL: URL(string: "https://example.com/live/init-active.mp4")!,
                mediaSegments: []
            ),
            audio: nil
        )
        let replacement = makeRepresentation(
            id: "replacement",
            bandwidth: 4_000_000,
            repeatCount: 3
        )

        XCTAssertThrowsError(
            try DASHPlaybackPlanner().refreshPlan(
                from: makeManifest(representations: [replacement]),
                preserving: current,
                segmentCount: 2
            )
        ) { error in
            XCTAssertEqual(
                error as? DASHPlaybackPlannerError,
                .missingPreservedRepresentation("active")
            )
        }
    }

    private func makeManifest(
        representations: [DASHRepresentation]
    ) -> DASHManifest {
        DASHManifest(
            type: .dynamic,
            minimumUpdatePeriod: 2,
            baseURL: URL(string: "https://example.com/")!,
            periods: [
                DASHPeriod(
                    id: "live",
                    baseURL: URL(string: "https://example.com/")!,
                    adaptationSets: [
                        DASHAdaptationSet(
                            id: "video",
                            mimeType: "video/mp4",
                            contentType: "video",
                            codecs: "avc1.640028",
                            language: nil,
                            baseURL: URL(string: "https://example.com/live/")!,
                            segmentTemplate: nil,
                            contentProtections: [],
                            representations: representations
                        )
                    ]
                )
            ]
        )
    }

    private func makeRepresentation(
        id: String,
        bandwidth: Int,
        repeatCount: Int
    ) -> DASHRepresentation {
        DASHRepresentation(
            id: id,
            bandwidth: bandwidth,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: URL(string: "https://example.com/live/")!,
            segmentTemplate: DASHSegmentTemplate(
                initialization: "init-$RepresentationID$.mp4",
                media: "$RepresentationID$-$Number$-$Time$.m4s",
                timescale: 1_000,
                duration: nil,
                startNumber: 1,
                presentationTimeOffset: 0,
                timeline: [
                    DASHSegmentTimelineEntry(
                        startTime: 0,
                        duration: 2_000,
                        repeatCount: repeatCount
                    )
                ]
            ),
            contentProtections: []
        )
    }
}
