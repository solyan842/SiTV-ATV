import XCTest
@testable import SiTVATV

final class DASHPeriodRolloverTests: XCTestCase {
    func testDynamicInitialPlanUsesLatestPeriod() throws {
        let manifest = makeManifest(periods: [
            makePeriod(id: "p0", base: "p0", startNumber: 1, repeatCount: 2),
            makePeriod(id: "p1", base: "p1", startNumber: 101, repeatCount: 2)
        ])

        let plan = try DASHPlaybackPlanner().makePlan(
            from: manifest,
            segmentCount: 2
        )

        XCTAssertEqual(plan.periodIdentity, "id:p1")
        XCTAssertEqual(plan.video?.mediaSegments.map(\.number), [102, 103])
        XCTAssertTrue(
            plan.video?.initializationURL.absoluteString.contains("/p1/") == true
        )
    }

    func testRefreshAcrossPeriodBuildsFreshPlanAndChangesIdentity() throws {
        let initialManifest = makeManifest(periods: [
            makePeriod(id: "p0", base: "p0", startNumber: 1, repeatCount: 2)
        ])
        let current = try DASHPlaybackPlanner().makePlan(
            from: initialManifest,
            segmentCount: 2
        )
        let refreshedManifest = makeManifest(periods: [
            makePeriod(id: "p0", base: "p0", startNumber: 1, repeatCount: 4),
            makePeriod(id: "p1", base: "p1", startNumber: 1, repeatCount: 2)
        ])

        let refreshed = try DASHPlaybackPlanner().refreshPlan(
            from: refreshedManifest,
            preserving: current,
            segmentCount: 2
        )

        XCTAssertEqual(current.periodIdentity, "id:p0")
        XCTAssertEqual(refreshed.periodIdentity, "id:p1")
        XCTAssertEqual(refreshed.video?.mediaSegments.map(\.number), [2, 3])
        XCTAssertTrue(
            refreshed.video?.initializationURL.absoluteString.contains("/p1/") == true
        )
    }

    func testLiveRefresherRequiresReprepareAndDoesNotEmitNewPeriodSegments() async throws {
        let initialManifest = makeManifest(periods: [
            makePeriod(id: "p0", base: "p0", startNumber: 1, repeatCount: 2)
        ])
        let initialPlan = try DASHPlaybackPlanner().makePlan(
            from: initialManifest,
            segmentCount: 2
        )
        let rolloverManifest = makeManifest(periods: [
            makePeriod(id: "p0", base: "p0", startNumber: 1, repeatCount: 4),
            makePeriod(id: "p1", base: "p1", startNumber: 1, repeatCount: 2)
        ])
        let loader = PeriodRolloverLoader(manifest: rolloverManifest)
        let refresher = DASHLivePlanRefresher(
            manifestURL: URL(string: "https://example.com/live/manifest.mpd")!,
            headers: [:],
            initialPlan: initialPlan,
            segmentCount: 2,
            loader: loader
        )

        let batch = try await refresher.refresh()

        XCTAssertTrue(batch.requiresReprepare)
        XCTAssertTrue(batch.videoSegments.isEmpty)
        XCTAssertTrue(batch.audioSegments.isEmpty)
        XCTAssertEqual(batch.plan.periodIdentity, "id:p1")
    }

    private func makeManifest(periods: [DASHPeriod]) -> DASHManifest {
        DASHManifest(
            type: .dynamic,
            minimumUpdatePeriod: 1,
            baseURL: URL(string: "https://example.com/live/")!,
            periods: periods
        )
    }

    private func makePeriod(
        id: String,
        base: String,
        startNumber: UInt64,
        repeatCount: Int
    ) -> DASHPeriod {
        let periodBase = URL(string: "https://example.com/live/\(base)/")!
        let representation = DASHRepresentation(
            id: "video-main",
            bandwidth: 4_000_000,
            width: 1920,
            height: 1080,
            mimeType: "video/mp4",
            codecs: "avc1.640028",
            baseURL: periodBase,
            segmentTemplate: DASHSegmentTemplate(
                initialization: "init-$RepresentationID$.mp4",
                media: "$RepresentationID$-$Number$-$Time$.m4s",
                timescale: 1_000,
                duration: nil,
                startNumber: startNumber,
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
        return DASHPeriod(
            id: id,
            baseURL: periodBase,
            adaptationSets: [
                DASHAdaptationSet(
                    id: "video",
                    mimeType: "video/mp4",
                    contentType: "video",
                    codecs: "avc1.640028",
                    language: nil,
                    baseURL: periodBase,
                    segmentTemplate: nil,
                    contentProtections: [],
                    representations: [representation]
                )
            ]
        )
    }
}

private actor PeriodRolloverLoader: DASHResourceLoading {
    let manifest: DASHManifest

    init(manifest: DASHManifest) {
        self.manifest = manifest
    }

    func loadManifest(
        from url: URL,
        headers: [String: String]
    ) async throws -> DASHManifest {
        manifest
    }

    func loadData(
        from url: URL,
        headers: [String: String]
    ) async throws -> Data {
        Data()
    }
}
