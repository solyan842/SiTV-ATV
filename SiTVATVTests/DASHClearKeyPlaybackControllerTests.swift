import CoreMedia
import XCTest
@testable import SiTVATV

final class DASHClearKeyPlaybackControllerTests: XCTestCase {
    @MainActor
    func testStopCancelsResumeBeforeRendererStarts() async throws {
        let session = BlockingMediaSession()
        let renderer = SpySampleRenderer()
        let controller = DASHClearKeyPlaybackController(
            mediaSessionBuilder: StubMediaSessionBuilder(session: session),
            batchBuilder: StubPlaybackBatchBuilder(),
            fixedRenderer: renderer
        )
        let context = makeContext()

        let resumeTask = Task {
            try await controller.resume(context: context, headers: [:])
        }

        await session.waitUntilProcessingStarted()
        await controller.stop()
        await session.releaseProcessing()

        do {
            try await resumeTask.value
            XCTFail("Expected stopped")
        } catch {
            XCTAssertEqual(error as? PlayerEngineError, .stopped)
        }

        let startCount = renderer.startCount
        let isPlaying = await controller.isPlaying
        let finalizeCount = await session.finalizeCount()

        XCTAssertEqual(startCount, 0)
        XCTAssertFalse(isPlaying)
        XCTAssertEqual(finalizeCount, 1)
    }

    private func makeContext() -> DASHClearKeyPlaybackContext {
        let preparation = DASHClearKeyPreparation(
            manifest: DASHManifest(
                type: .static,
                minimumUpdatePeriod: nil,
                baseURL: URL(string: "https://example.com/")!,
                periods: []
            ),
            keyMaterial: ClearKeyMaterial(
                keyID: Data(repeating: 0x11, count: 16),
                key: Data(repeating: 0x22, count: 16)
            ),
            video: nil,
            audio: nil
        )
        return DASHClearKeyPlaybackContext(
            preparation: preparation,
            video: nil,
            audio: nil
        )
    }
}

private actor BlockingMediaSession: DASHMediaSessionRunning {
    private var processingStarted = false
    private var processingContinuation: CheckedContinuation<Void, Never>?
    private var finalizations = 0

    func processPlannedSegments() async throws -> DASHClearKeyMediaOutput {
        processingStarted = true
        await withCheckedContinuation { continuation in
            processingContinuation = continuation
        }
        return DASHClearKeyMediaOutput(video: [], audio: [])
    }

    func finalize() async throws {
        finalizations += 1
    }

    func waitUntilProcessingStarted() async {
        while !processingStarted {
            await Task.yield()
        }
    }

    func releaseProcessing() {
        processingContinuation?.resume()
        processingContinuation = nil
    }

    func finalizeCount() -> Int {
        finalizations
    }
}

private struct StubMediaSessionBuilder: DASHMediaSessionBuilding {
    let session: BlockingMediaSession

    func make(
        preparation: DASHClearKeyPreparation,
        headers: [String: String]
    ) async throws -> any DASHMediaSessionRunning {
        session
    }
}

private struct StubPlaybackBatchBuilder: DASHPlaybackBatchBuilding {
    func make(
        output: DASHClearKeyMediaOutput,
        context: DASHClearKeyPlaybackContext
    ) throws -> DASHPlaybackBatch {
        DASHPlaybackBatch(video: [], audio: [], sourceTime: .zero)
    }
}

@MainActor
private final class SpySampleRenderer: DASHSampleRendering {
    private(set) var startCount = 0

    func start(at sourceTime: CMTime) {
        startCount += 1
    }

    func pause() {}

    func enqueueVideo(_ sampleBuffer: CMSampleBuffer) async throws {}

    func enqueueAudio(_ sampleBuffer: CMSampleBuffer) async throws {}

    func flush() async {}
}
