import XCTest
@testable import SiTVATV

final class DASHClearKeyPlayerEngineTests: XCTestCase {
    func testCanPlayOnlyDASHClearKeySources() {
        let engine = DASHClearKeyPlayerEngine(
            preparer: StubDASHPreparer(preparation: makePreparation()),
            contextBuilder: StubPlaybackContextBuilder()
        )

        XCTAssertTrue(engine.canPlay(makeSource()))
        XCTAssertTrue(engine.canPlay(makeSource(drmType: "org.w3.clearkey")))
        XCTAssertFalse(engine.canPlay(makeSource(manifestType: "hls")))
        XCTAssertFalse(engine.canPlay(makeSource(drmType: nil)))
    }

    func testStartPreparesContextAndStopClearsState() async throws {
        let preparation = makePreparation()
        let preparer = StubDASHPreparer(preparation: preparation)
        let engine = DASHClearKeyPlayerEngine(
            preparer: preparer,
            contextBuilder: StubPlaybackContextBuilder(),
            maxVideoHeight: 1080,
            segmentCount: 4
        )
        let source = makeSource()
        let channel = Channel(
            id: "test",
            name: "Test",
            group: "Test",
            logoURL: nil,
            sources: [source]
        )
        let request = PlaybackRequest(
            channel: channel,
            sourceIndex: 0,
            source: source
        )

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
    }

    private func makeSource(
        manifestType: String? = "mpd",
        drmType: String? = "clearkey"
    ) -> StreamSource {
        StreamSource(
            url: "https://example.com/manifest.mpd",
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
