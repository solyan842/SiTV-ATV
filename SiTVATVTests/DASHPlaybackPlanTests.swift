import XCTest
@testable import SiTVATV

final class DASHPlaybackPlanTests: XCTestCase {
    func testSelectsHighestVideoWithinHeightLimitAndBestAudio() throws {
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: URL(string: "https://example.com/")!,
            periods: [
                DASHPeriod(
                    id: "p0",
                    baseURL: URL(string: "https://example.com/")!,
                    adaptationSets: [
                        makeVideoAdaptation(),
                        makeAudioAdaptation()
                    ]
                )
            ]
        )

        let plan = try DASHPlaybackPlanner().makePlan(
            from: manifest,
            maxVideoHeight: 1080,
            segmentCount: 2
        )

        XCTAssertEqual(plan.video?.representation.id, "1080p")
        XCTAssertEqual(plan.audio?.representation.id, "audio-high")
        XCTAssertEqual(plan.video?.mediaSegments.map(\.number), [1, 2])
        XCTAssertEqual(
            plan.video?.initializationURL.absoluteString,
            "https://example.com/video/init-1080p.mp4"
        )
    }

    func testDynamicManifestStartsAtLatestTimelineWindow() throws {
        let representation = makeRepresentation(
            id: "live-video",
            bandwidth: 4_000_000,
            width: 1920,
            height: 1080,
            base: "live/",
            template: DASHSegmentTemplate(
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
                        repeatCount: 5
                    )
                ]
            )
        )
        let manifest = DASHManifest(
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
                            representations: [representation]
                        )
                    ]
                )
            ]
        )

        let plan = try DASHPlaybackPlanner().makePlan(
            from: manifest,
            segmentCount: 2
        )

        XCTAssertEqual(plan.video?.mediaSegments.map(\.number), [5, 6])
        XCTAssertEqual(plan.video?.mediaSegments.map(\.time), [8_000, 10_000])
    }

    func testDynamicDurationTemplateStartsNearLiveEdgeInsteadOfStartNumber() throws {
        let representation = makeRepresentation(
            id: "duration-live",
            bandwidth: 4_000_000,
            width: 1920,
            height: 1080,
            base: "live/",
            template: DASHSegmentTemplate(
                initialization: "init.mp4",
                media: "segment-$Number$.m4s",
                timescale: 1,
                duration: 2,
                startNumber: 1,
                presentationTimeOffset: 0,
                timeline: []
            )
        )
        let adaptation = DASHAdaptationSet(
            id: "video",
            mimeType: "video/mp4",
            contentType: "video",
            codecs: "avc1.640028",
            language: nil,
            baseURL: URL(string: "https://example.com/live/")!,
            segmentTemplate: nil,
            contentProtections: [],
            representations: [representation]
        )
        let manifest = DASHManifest(
            type: .dynamic,
            minimumUpdatePeriod: 2,
            baseURL: URL(string: "https://example.com/")!,
            periods: [
                DASHPeriod(
                    id: "live",
                    baseURL: URL(string: "https://example.com/")!,
                    adaptationSets: [adaptation],
                    start: 10
                )
            ],
            availabilityStartTime: Date(timeIntervalSince1970: 1_000),
            publishTime: Date(timeIntervalSince1970: 1_060),
            suggestedPresentationDelay: 4
        )

        let plan = try DASHPlaybackPlanner().makePlan(from: manifest, segmentCount: 3)

        XCTAssertEqual(plan.video?.mediaSegments.map(\.number), [22, 23, 24])
        XCTAssertEqual(plan.video?.mediaSegments.map(\.time), [42, 44, 46])
    }

    func testHeightLimitSelects720p() throws {
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: URL(string: "https://example.com/")!,
            periods: [
                DASHPeriod(
                    id: nil,
                    baseURL: URL(string: "https://example.com/")!,
                    adaptationSets: [makeVideoAdaptation()]
                )
            ]
        )

        let plan = try DASHPlaybackPlanner().makePlan(
            from: manifest,
            maxVideoHeight: 720,
            segmentCount: 1
        )

        XCTAssertEqual(plan.video?.representation.id, "720p")
        XCTAssertNil(plan.audio)
    }

    func testRejectsManifestWithoutPlayableAudioOrVideo() {
        let manifest = DASHManifest(
            type: .static,
            minimumUpdatePeriod: nil,
            baseURL: URL(string: "https://example.com/")!,
            periods: [
                DASHPeriod(
                    id: nil,
                    baseURL: URL(string: "https://example.com/")!,
                    adaptationSets: []
                )
            ]
        )

        XCTAssertThrowsError(try DASHPlaybackPlanner().makePlan(from: manifest)) { error in
            XCTAssertEqual(error as? DASHPlaybackPlannerError, .noPlayableRepresentations)
        }
    }

    private func makeVideoAdaptation() -> DASHAdaptationSet {
        DASHAdaptationSet(
            id: "video",
            mimeType: "video/mp4",
            contentType: "video",
            codecs: "avc1.640028",
            language: nil,
            baseURL: URL(string: "https://example.com/video/")!,
            segmentTemplate: nil,
            contentProtections: [],
            representations: [
                makeRepresentation(id: "720p", bandwidth: 2_500_000, width: 1280, height: 720, base: "video/"),
                makeRepresentation(id: "1080p", bandwidth: 5_000_000, width: 1920, height: 1080, base: "video/"),
                makeRepresentation(id: "2160p", bandwidth: 12_000_000, width: 3840, height: 2160, base: "video/")
            ]
        )
    }

    private func makeAudioAdaptation() -> DASHAdaptationSet {
        DASHAdaptationSet(
            id: "audio",
            mimeType: "audio/mp4",
            contentType: "audio",
            codecs: "mp4a.40.2",
            language: "und",
            baseURL: URL(string: "https://example.com/audio/")!,
            segmentTemplate: nil,
            contentProtections: [],
            representations: [
                makeRepresentation(id: "audio-low", bandwidth: 96_000, width: nil, height: nil, base: "audio/", mimeType: "audio/mp4"),
                makeRepresentation(id: "audio-high", bandwidth: 192_000, width: nil, height: nil, base: "audio/", mimeType: "audio/mp4")
            ]
        )
    }

    private func makeRepresentation(
        id: String,
        bandwidth: Int,
        width: Int?,
        height: Int?,
        base: String,
        mimeType: String = "video/mp4",
        template: DASHSegmentTemplate? = nil
    ) -> DASHRepresentation {
        DASHRepresentation(
            id: id,
            bandwidth: bandwidth,
            width: width,
            height: height,
            mimeType: mimeType,
            codecs: nil,
            baseURL: URL(string: "https://example.com/\(base)")!,
            segmentTemplate: template ?? DASHSegmentTemplate(
                initialization: "init-$RepresentationID$.mp4",
                media: "$RepresentationID$-$Number$.m4s",
                timescale: 1,
                duration: 2,
                startNumber: 1,
                presentationTimeOffset: 0,
                timeline: []
            ),
            contentProtections: []
        )
    }
}
