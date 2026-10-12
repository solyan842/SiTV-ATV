import XCTest
@testable import SiTVATV

final class DASHPeriodReprepareEngineTests: XCTestCase {
    func testEngineRepreparesAndResumesAfterPeriodRolloverSignal() async throws {
        let preparer = RolloverSequencePreparer(
            preparations: [
                makePreparation(periodIdentity: "id:p0"),
                makePreparation(periodIdentity: "id:p1")
            ]
        )
        let controller = RolloverPlaybackController()
        let engine = DASHClearKeyPlayerEngine(
            preparer: preparer,
            contextBuilder: RolloverContextBuilder(),
            playbackController: controller
        )
        let source = StreamSource(
            url: "https://example.com/live/manifest.mpd",
            manifestType: "mpd",
            drmType: "clearkey",
            drmKey: "00112233445566778899aabbccddeeff:ffeeddccbbaa99887766554433221100"
        )
        let channel = Channel(
            id: "live",
            name: "Live",
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
        try await engine.resumePlayback()

        let prepareCount = await preparer.prepareCount()
        let resumeCount = await controller.resumeCount()
        XCTAssertEqual(prepareCount, 2)
        XCTAssertEqual(resumeCount, 2)
        XCTAssertEqual(engine.playbackContext?.preparation.periodIdentity, "id:p1")
    }

    private func makePreparation(
        periodIdentity: String
    ) -> DASHClearKeyPreparation {
        DASHClearKeyPreparation(
            manifest: DASHManifest(
                type: .dynamic,
                minimumUpdatePeriod: 1,
                baseURL: URL(string: "https://example.com/live/")!,
                periods: []
            ),
            keyMaterial: ClearKeyMaterial(
                keyID: Data(repeating: 0x11, count: 16),
                key: Data(repeating: 0x22, count: 16)
            ),
            video: nil,
            audio: nil,
            manifestURL: URL(string: "https://example.com/live/manifest.mpd")!,
            periodIdentity: periodIdentity
        )
    }
}

private actor RolloverSequencePreparer: DASHClearKeyPreparing {
    private let preparations: [DASHClearKeyPreparation]
    private var index = 0

    init(preparations: [DASHClearKeyPreparation]) {
        self.preparations = preparations
    }

    func prepare(
        source: StreamSource,
        maxVideoHeight: Int?,
        segmentCount: Int
    ) async throws -> DASHClearKeyPreparation {
        let value = preparations[min(index, preparations.count - 1)]
        index += 1
        return value
    }

    func prepareCount() -> Int {
        index
    }
}

private struct RolloverContextBuilder: DASHPlaybackContextBuilding {
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

private actor RolloverPlaybackController: DASHPlaybackControlling {
    private var resumes = 0

    func resume(
        context: DASHClearKeyPlaybackContext,
        headers: [String: String]
    ) async throws {
        resumes += 1
        if resumes == 1 {
            throw DASHPlaybackControllerError.reprepareRequired
        }
    }

    func stop() async {}

    func resumeCount() -> Int {
        resumes
    }
}
