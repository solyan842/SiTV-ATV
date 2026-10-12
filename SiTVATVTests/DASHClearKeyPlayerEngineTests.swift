import XCTest
@testable import SiTVATV

final class DASHClearKeyPlayerEngineTests: XCTestCase {
    func testCanPlayOnlyDASHClearKeySources() {
        let engine = DASHClearKeyPlayerEngine(
            preparer: StubDASHPreparer(preparation: makePreparation()),
            contextBuilder: StubPlaybackContextBuilder(),
            playbackController: StubPlaybackController()
        )

        XCTAssertTrue(engine.canPlay(makeSource()))
        XCTAssertTrue(engine.canPlay(makeSource(drmType: "org.w3.clearkey")))
        XCTAssertFalse(
            engine.canPlay(
                makeSource(
                    url: "https://example.com/live.m3u8",
                    manifestType: "hls"
                )
            )
        )
        XCTAssertFalse(engine.canPlay(makeSource(drmType: nil)))
    }

    func testStartPreparesContextAndStopClearsState() async throws {
        let preparation = makePreparation()
        let preparer = StubDASHPreparer(preparation: preparation)
        let controller = StubPlaybackController()
        let engine = DASHClearKeyPlayerEngine(
            preparer: preparer,
            contextBuilder: StubPlaybackContextBuilder(),
            playbackController: controller,
            maxVideoHeight: 1080,
            segmentCount: 4
        )
        let source = makeSource()
        let request = makeRequest(source: source)

        try await engine.start(request)

        XCTAssertTrue(engine.isPrepared)
        XCTAssertEqual(engine.activeRequest, request)
        let invocation = await preparer.invocation()
        XCTAssertEqual(invocation?.maxVideoHeight, 1080)
        XCTAssertEqual(invocation?.segmentCount, 4)
        XCTAssertEqual(invocation?.source, source)

        await engine.stop()

        XCTAssertFalse(engine.isPrepared)
        XCTAssertNil(engine.activeRequest)
        let stopCount = await controller.stopCount()
        XCTAssertEqual(stopCount, 2)
    }

    func testResumeForwardsPreparedContextAndSourceHeaders() async throws {
        let controller = StubPlaybackController()
        let engine = DASHClearKeyPlayerEngine(
            preparer: StubDASHPreparer(preparation: makePreparation()),
            contextBuilder: StubPlaybackContextBuilder(),
            playbackController: controller
        )
        let source = StreamSource(
            url: "https://example.com/manifest.mpd",
            headers: ["Referer": "https://example.com/"],
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100"
        )

        try await engine.start(makeRequest(source: source))
        try await engine.resumePlayback()

        let invocation = await controller.resumeInvocation()
        XCTAssertEqual(invocation?.headers, source.headers)
        XCTAssertNotNil(invocation?.context.preparation.keyMaterial)
    }

    private func makeRequest(source: StreamSource) -> PlaybackRequest {
        let channel = Channel(
            id: "test",
            name: "Test",
            group: "Test",
            logoURL: nil,
            sources: [source]
        )
        return PlaybackRequest(
            channel: channel,
            sourceIndex: 0,
            source: source
        )
    }

    private func makeSource(
        url: String = "https://example.com/manifest.mpd",
        manifestType: String? = "mpd",
        drmType: String? = "clearkey"
    ) -> StreamSource {
        StreamSource(
            url: url,
            manifestType: manifestType,
            drmType: drmType,
            drmKey: "00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100"
        )
    }

    private func makePreparation() -> DASHClearKeyPreparation {
        let baseURL = URL(string: "https://example.com/")!
        return DASHClearKeyPreparation(
            manifest: DASHManifest(
                type: .static,
                minimumUpdatePeriod: nil,
                baseURL: baseURL,
                periods: []
            ),
            keyMaterial: ClearKeyMaterial(
                keyID: Data(repeating: 0x11, count: 16),
                key: Data(repeating: 0x22, count: 16)
            ),
            video: nil,
            audio: nil
        )
    }
}

private actor StubDASHPreparer: DASHClearKeyPreparing {
    struct Invocation: Equatable {
        let source: StreamSource
        let maxVideoHeight: Int?
        let segmentCount: Int
    }

    private let preparation: DASHClearKeyPreparation
    private var lastInvocation: Invocation?

    init(preparation: DASHClearKeyPreparation) {
        self.preparation = preparation
    }

    func prepare(
        source: StreamSource,
        maxVideoHeight: Int?,
        segmentCount: Int
    ) async throws -> DASHClearKeyPreparation {
        lastInvocation = Invocation(
            source: source,
            maxVideoHeight: maxVideoHeight,
            segmentCount: segmentCount
        )
        return preparation
    }

    func invocation() -> Invocation? {
        lastInvocation
    }
}

private struct StubPlaybackContextBuilder: DASHPlaybackContextBuilding {
    func make(
        preparation: DASHClearKeyPreparation
    ) async throws -> DASHClearKeyPlaybackContext {
        DASHClearKeyPlaybackContext(
            preparation: preparation,
            video: nil,
            audio: nil
        )
    }
}

private actor StubPlaybackController: DASHPlaybackControlling {
    struct Invocation {
        let context: DASHClearKeyPlaybackContext
        let headers: [String: String]
    }

    private var lastResumeInvocation: Invocation?
    private var stops = 0

    func resume(
        context: DASHClearKeyPlaybackContext,
        headers: [String: String]
    ) async throws {
        lastResumeInvocation = Invocation(context: context, headers: headers)
    }

    func stop() async {
        stops += 1
    }

    func resumeInvocation() -> Invocation? {
        lastResumeInvocation
    }

    func stopCount() -> Int {
        stops
    }
}
