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
    func primeVideo(_ sampleBuffer: CMSampleBuffer)
    func primeAudio(_ sampleBuffer: CMSampleBuffer)
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

private enum DASHQueuedPlaybackSample {
    case video(CMSampleBuffer)
    case audio(CMSampleBuffer)

    var presentationTime: CMTime {
        switch self {
        case .video(let sampleBuffer), .audio(let sampleBuffer):
            return CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        }
    }
}

actor DASHClearKeyPlaybackController: DASHPlaybackControlling {
    private let mediaSessionBuilder: any DASHMediaSessionBuilding
    private let batchBuilder: any DASHPlaybackBatchBuilding
    private let rendererBuilder: any DASHRendererBuilding
    private let fixedRenderer: (any DASHSampleRendering)?

    private var mediaSession: (any DASHMediaSessionRunning)?
    private var renderer: (any DASHSampleRendering)?
    private var playbackGeneration: UInt64 = 0
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
        let generation = playbackGeneration

        let session = try await mediaSessionBuilder.make(
            preparation: context.preparation,
            headers: headers
        )

        var pendingRenderer: (any DASHSampleRendering)?
        do {
            try ensureCurrent(generation)

            let output = try await session.processPlannedSegments()
            try ensureCurrent(generation)

            let batch = try batchBuilder.make(output: output, context: context)
            try ensureCurrent(generation)

            let renderer: any DASHSampleRendering
            if let fixedRenderer {
                renderer = fixedRenderer
            } else {
                renderer = await rendererBuilder.makeRenderer()
            }
            pendingRenderer = renderer
            try ensureCurrent(generation)

            if let firstVideo = batch.video.first {
                await renderer.primeVideo(firstVideo)
                try ensureCurrent(generation)
            }
            if let firstAudio = batch.audio.first {
                await renderer.primeAudio(firstAudio)
                try ensureCurrent(generation)
            }

            await renderer.start(at: batch.sourceTime)
            try ensureCurrent(generation)

            let remainingSamples = orderedRemainingSamples(in: batch)
            for sample in remainingSamples {
                try ensureCurrent(generation)
                switch sample {
                case .video(let sampleBuffer):
                    try await renderer.enqueueVideo(sampleBuffer)
                case .audio(let sampleBuffer):
                    try await renderer.enqueueAudio(sampleBuffer)
                }
                try ensureCurrent(generation)
            }

            mediaSession = session
            self.renderer = renderer
            pendingRenderer = nil
            isPlaying = true
        } catch {
            let staleGeneration = generation != playbackGeneration
            if let pendingRenderer,
               !staleGeneration || fixedRenderer == nil {
                await pendingRenderer.pause()
                await pendingRenderer.flush()
            }
            try? await session.finalize()
            if staleGeneration {
                throw PlayerEngineError.stopped
            }
            throw error
        }
    }

    func stop() async {
        playbackGeneration &+= 1

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

    private func orderedRemainingSamples(
        in batch: DASHPlaybackBatch
    ) -> [DASHQueuedPlaybackSample] {
        let video = batch.video.dropFirst().map(DASHQueuedPlaybackSample.video)
        let audio = batch.audio.dropFirst().map(DASHQueuedPlaybackSample.audio)
        return (video + audio).sorted { lhs, rhs in
            CMTimeCompare(lhs.presentationTime, rhs.presentationTime) < 0
        }
    }

    private func ensureCurrent(_ generation: UInt64) throws {
        guard generation == playbackGeneration else {
            throw PlayerEngineError.stopped
        }
    }
}
