import AVFoundation
import CoreMedia
import Foundation

protocol DASHMediaSessionRunning {
    func processPlannedSegments() async throws -> DASHClearKeyMediaOutput
    func finalize() async throws
}

extension DASHClearKeyMediaSession: DASHMediaSessionRunning {}

protocol DASHMediaSessionBuilding {
    func make(
        preparation: DASHClearKeyPreparation,
        headers: [String: String]
    ) async throws -> any DASHMediaSessionRunning
}

struct DefaultDASHMediaSessionBuilder: DASHMediaSessionBuilding {
    func make(
        preparation: DASHClearKeyPreparation,
        headers: [String: String]
    ) async throws -> any DASHMediaSessionRunning {
        try await DASHClearKeyMediaSession.make(
            preparation: preparation,
            headers: headers
        )
    }
}

protocol DASHPlaybackBatchBuilding {
    func make(
        output: DASHClearKeyMediaOutput,
        context: DASHClearKeyPlaybackContext
    ) throws -> DASHPlaybackBatch
}

extension DASHPlaybackBatchBuilder: DASHPlaybackBatchBuilding {}

@MainActor
protocol DASHSampleRendering: AnyObject {
    func start(at sourceTime: CMTime)
    func pause()
    func enqueueVideo(_ sampleBuffer: CMSampleBuffer) async throws
    func enqueueAudio(_ sampleBuffer: CMSampleBuffer) async throws
    func flush() async
}

extension DASHSynchronizedRenderer: DASHSampleRendering {}

protocol DASHRendererBuilding {
    @MainActor
    func makeRenderer() -> any DASHSampleRendering
}

struct DefaultDASHRendererBuilder: DASHRendererBuilding {
    @MainActor
    func makeRenderer() -> any DASHSampleRendering {
        DASHSynchronizedRenderer()
    }
}

protocol DASHPlaybackControlling: AnyObject {
    func resume(
        context: DASHClearKeyPlaybackContext,
        headers: [String: String]
    ) async throws
    func stop() async
}

actor DASHClearKeyPlaybackController: DASHPlaybackControlling {
    private let mediaSessionBuilder: any DASHMediaSessionBuilding
    private let batchBuilder: any DASHPlaybackBatchBuilding
    private let rendererBuilder: any DASHRendererBuilding
    private let fixedRenderer: (any DASHSampleRendering)?

    private var mediaSession: (any DASHMediaSessionRunning)?
    private var renderer: (any DASHSampleRendering)?
    private(set) var isPlaying = false

    init(
        mediaSessionBuilder: any DASHMediaSessionBuilding = DefaultDASHMediaSessionBuilder(),
        batchBuilder: any DASHPlaybackBatchBuilding = DASHPlaybackBatchBuilder(),
        rendererBuilder: any DASHRendererBuilding = DefaultDASHRendererBuilder(),
        fixedRenderer: (any DASHSampleRendering)? = nil
    ) {
        self.mediaSessionBuilder = mediaSessionBuilder
        self.batchBuilder = batchBuilder
        self.rendererBuilder = rendererBuilder
        self.fixedRenderer = fixedRenderer
    }

    func resume(
        context: DASHClearKeyPlaybackContext,
        headers: [String: String]
    ) async throws {
        await stop()

        let session = try await mediaSessionBuilder.make(
            preparation: context.preparation,
            headers: headers
        )

        do {
            let output = try await session.processPlannedSegments()
            let batch = try batchBuilder.make(output: output, context: context)
            let renderer: any DASHSampleRendering
            if let fixedRenderer {
                renderer = fixedRenderer
            } else {
                renderer = await rendererBuilder.makeRenderer()
            }

            for sampleBuffer in batch.video {
                try await renderer.enqueueVideo(sampleBuffer)
            }
            for sampleBuffer in batch.audio {
                try await renderer.enqueueAudio(sampleBuffer)
            }
            await renderer.start(at: batch.sourceTime)

            mediaSession = session
            self.renderer = renderer
            isPlaying = true
        } catch {
            try? await session.finalize()
            throw error
        }
    }

    func stop() async {
        if let renderer {
            await renderer.pause()
            await renderer.flush()
        }
        if let mediaSession {
            try? await mediaSession.finalize()
        }
        renderer = nil
        mediaSession = nil
        isPlaying = false
    }
}
