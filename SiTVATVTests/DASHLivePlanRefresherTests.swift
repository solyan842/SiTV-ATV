import XCTest
@testable import SiTVATV

final class DASHLivePlanRefresherTests: XCTestCase {
    func testRefreshReturnsOnlyUnseenSegmentsAndPreservesHeaders() async throws {
        let initialRepresentation = makeRepresentation(
            id: "active",
            bandwidth: 4_000_000,
            repeatCount: 5
        )
        let initialPlan = DASHPlaybackPlan(
            video: DASHTrackPlan(
                representation: initialRepresentation,
                initializationURL: URL(string: "https://example.com/live/init-active.mp4")!,
                mediaSegments: [
                    makeSegment(number: 5, time: 8_000),
                    makeSegment(number: 6, time: 10_000)
                ]
            ),
            audio: nil
        )
        let refreshedManifest = makeManifest(
            type: .dynamic,
            minimumUpdatePeriod: 0.1,
            representations: [
                makeRepresentation(
                    id: "active",
                    bandwidth: 4_000_000,
                    repeatCount: 7
                ),
                makeRepresentation(
                    id: "higher",
                    bandwidth: 12_000_000,
                    repeatCount: 7
                )
            ]
        )
        let loader = LivePlanLoader(manifest: refreshedManifest)
        let headers = ["Referer": "https://example.com/"]
        let refresher = DASHLivePlanRefresher(
            manifestURL: URL(string: "https://example.com/live/manifest.mpd")!,
            headers: headers,
            initialPlan: initialPlan,
            segmentCount: 3,
            minimumRefreshInterval: 0.5,
            loader: loader
        )

        let batch = try await refresher.refresh()
        let requests = await loader.requests()

        XCTAssertEqual(batch.plan.video?.representation.id, "active")
        XCTAssertEqual(batch.plan.video?.mediaSegments.map(\.number), [6, 7, 8])
        XCTAssertEqual(batch.videoSegments.map(\.number), [7, 8])
        XCTAssertTrue(batch.audioSegments.isEmpty)
        XCTAssertEqual(batch.nextRefreshInterval, 0.5)
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.headers, headers)
    }

    func testRefreshRejectsStaticManifest() async throws {
        let representation = makeRepresentation(
            id: "active",
            bandwidth: 4_000_000,
            repeatCount: 2
        )
        let initialPlan = DASHPlaybackPlan(
            video: DASHTrackPlan(
                representation: representation,
                initializationURL: URL(string: "https://example.com/live/init-active.mp4")!,
                mediaSegments: []
            ),
            audio: nil
        )
        let loader = LivePlanLoader(
            manifest: makeManifest(
                type: .static,
                minimumUpdatePeriod: nil,
                representations: [representation]
            )
        )
        let refresher = DASHLivePlanRefresher(
            manifestURL: URL(string: "https://example.com/live/manifest.mpd")!,
            headers: [:],
            initialPlan: initialPlan,
            loader: loader
        )

        do {
            _ = try await refresher.refresh()
            XCTFail("Expected notDynamicManifest")
        } catch {
            XCTAssertEqual(
                error as? DASHLivePlanRefresherError,
                .notDynamicManifest
            )
        }
    }

    private func makeManifest(
        type: DASHManifest.ManifestType,
        minimumUpdatePeriod: TimeInterval?,
        representations: [DASHRepresentation]
    ) -> DASHManifest {
        DASHManifest(
            type: type,
            minimumUpdatePeriod: minimumUpdatePeriod,
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

    private func makeSegment(
        number: UInt64,
        time: UInt64
    ) -> DASHResolvedSegment {
        DASHResolvedSegment(
            number: number,
            time: time,
            duration: 2_000,
            url: URL(string: "https://example.com/live/active-\(number)-\(time).m4s")!
        )
    }
}

private actor LivePlanLoader: DASHResourceLoading {
    struct Request: Equatable {
        let url: URL
        let headers: [String: String]
    }

    private let manifest: DASHManifest
    private var recordedRequests: [Request] = []

    init(manifest: DASHManifest) {
        self.manifest = manifest
    }

    func loadManifest(
        from url: URL,
        headers: [String: String]
    ) async throws -> DASHManifest {
        recordedRequests.append(Request(url: url, headers: headers))
        return manifest
    }

    func loadData(
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        throw LivePlanLoaderError.unusedDataLoad
    }

    func requests() -> [Request] {
        recordedRequests
    }
}

private enum LivePlanLoaderError: Error {
    case unusedDataLoad
}
