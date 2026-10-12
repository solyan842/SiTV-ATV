import AVFoundation
import CoreMedia
import Foundation

protocol DASHMediaSessionRunning {
    func processPlannedSegments() async throws -> DASHClearKeyMediaOutput
    func process(
        videoSegments: [DASHResolvedSegment],
        audioSegments: [DASHResolvedSegment]
    ) async throws -> DASHClearKeyMediaOutput
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

protocol DASHLivePlanRefreshing {
    func refresh() async throws -> DASHLiveRefreshBatch
}

extension DASHLivePlanRefresher: DASHLivePlanRefreshing {}

protocol DASHLivePlanRefresherBuilding {
    func make(
        manifestURL: URL,
        headers: [String: String],
        initialPlan: DASHPlaybackPlan,
        segmentCount: Int
    ) -> any DASHLivePlanRefreshing
}

struct DefaultDASHLivePlanRefresherBuilder: DASHLivePlanRefresherBuilding {
    func make(
        manifestURL: URL,
        headers: [String: String],
        initialPlan: DASHPlaybackPlan,
        segmentCount: Int
    ) -> any DASHLivePlanRefreshing {
        DASHLivePlanRefresher(
            manifestURL: manifestURL,
            headers: headers,
            initialPlan: initialPlan,
            segmentCount: segmentCount
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

enum DASHPlaybackControllerError: Error, Equatable {
    case reprepareRequired
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
    private let liveRefresherBuilder: any DASHLivePlanRefresherBuilding
    private let fixedRenderer: (any DASHSampleRendering)?

    private var mediaSession: (any DASHMediaSessionRunning)?
    private var renderer: (any DASHSampleRendering)?
    private var playbackGeneration: UInt64 = 0
    private(set) var isPlaying = false

    init(
        mediaSessionBuilder: any DASHMediaSessionBuilding = DefaultDASHMediaSessionBuilder(),
        batchBuilder: any DASHPlaybackBatchBuilding = DASHPlaybackBatchBuilder(),
        rendererBuilder: any DASHRendererBuilding = DefaultDASHRendererBuilder(),
        liveRefresherBuilder: any DASHLivePlanRefresherBuilding = DefaultDASHLivePlanRefresherBuilder(),
        fixedRenderer: (any DASHSampleRendering)? = nil
    ) {
        self.mediaSessionBuilder = mediaSessionBuilder
        self.batchBuilder = batchBuilder
        self.rendererBuilder = rendererBuilder
        self.liveRefresherBuilder = liveRefresherBuilder
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
        var committed = false
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

            mediaSession = session
            self.renderer = renderer
            pendingRenderer = nil
            isPlaying = true
            committed = true

            try await enqueue(
                orderedRemainingSamples(in: batch),
                on: renderer,
                generation: generation
            )

            if let refresher = makeLiveRefresher(
                context: context,
                headers: headers
            ) {
                try await runLiveRefreshLoop(
                    refresher: refresher,
                    session: session,
                    renderer: renderer,
                    context: context,
                    generation: generation
                )
            }
        } catch {
            let staleGeneration = generation != playbackGeneration
            if committed {
                if !staleGeneration {
                    await stop()
                }
            } else {
                if let pendingRenderer {
                    await pendingRenderer.pause()
                    await pendingRenderer.flush()
                }
                try? await session.finalize()
            }

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

    private func makeLiveRefresher(
        context: DASHClearKeyPlaybackContext,
        headers: [String: String]
    ) -> (any DASHLivePlanRefreshing)? {
        let preparation = context.preparation
        guard preparation.manifest.type == .dynamic,
              let manifestURL = preparation.manifestURL else {
            return nil
        }

        let initialPlan = DASHPlaybackPlan(
            video: preparation.video?.plan,
            audio: preparation.audio?.plan,
            periodIdentity: preparation.periodIdentity
        )
        let segmentCount = max(
            initialPlan.video?.mediaSegments.count ?? 0,
            initialPlan.audio?.mediaSegments.count ?? 0,
            1
        )
        return liveRefresherBuilder.make(
            manifestURL: manifestURL,
            headers: headers,
            initialPlan: initialPlan,
            segmentCount: segmentCount
        )
    }

    private func runLiveRefreshLoop(
        refresher: any DASHLivePlanRefreshing,
        session: any DASHMediaSessionRunning,
        renderer: any DASHSampleRendering,
        context: DASHClearKeyPlaybackContext,
        generation: UInt64
    ) async throws {
        var refreshInterval = max(
            context.preparation.manifest.minimumUpdatePeriod ?? 2,
            0.5
        )

        while true {
            try await waitForRefresh(
                interval: refreshInterval,
                generation: generation
            )
            try ensureCurrent(generation)

            let refresh = try await refresher.refresh()
            try ensureCurrent(generation)
            refreshInterval = refresh.nextRefreshInterval

            if refresh.requiresReprepare {
                throw DASHPlaybackControllerError.reprepareRequired
            }
            guard !refresh.isEmpty else { continue }

            let output = try await session.process(
                videoSegments: refresh.videoSegments,
                audioSegments: refresh.audioSegments
            )
            try ensureCurrent(generation)

            let batch = try batchBuilder.make(
                output: output,
                context: context
            )
            try await enqueue(
                orderedSamples(in: batch),
                on: renderer,
                generation: generation
            )
        }
    }

    private func waitForRefresh(
        interval: TimeInterval,
        generation: UInt64
    ) async throws {
        var remaining = max(interval, 0.1)
        while remaining > 0 {
            try ensureCurrent(generation)
            try Task.checkCancellation()
            let slice = min(remaining, 0.25)
            try await Task.sleep(
                nanoseconds: UInt64(slice * 1_000_000_000)
            )
            remaining -= slice
        }
        try ensureCurrent(generation)
    }

    private func enqueue(
        _ samples: [DASHQueuedPlaybackSample],
        on renderer: any DASHSampleRendering,
        generation: UInt64
    ) async throws {
        for sample in samples {
            try ensureCurrent(generation)
            switch sample {
            case .video(let sampleBuffer):
                try await renderer.enqueueVideo(sampleBuffer)
            case .audio(let sampleBuffer):
                try await renderer.enqueueAudio(sampleBuffer)
            }
            try ensureCurrent(generation)
        }
    }

    private func orderedRemainingSamples(
        in batch: DASHPlaybackBatch
    ) -> [DASHQueuedPlaybackSample] {
        let video = batch.video.dropFirst().map(DASHQueuedPlaybackSample.video)
        let audio = batch.audio.dropFirst().map(DASHQueuedPlaybackSample.audio)
        return sortByPresentationTime(video + audio)
    }

    private func orderedSamples(
        in batch: DASHPlaybackBatch
    ) -> [DASHQueuedPlaybackSample] {
        let video = batch.video.map(DASHQueuedPlaybackSample.video)
        let audio = batch.audio.map(DASHQueuedPlaybackSample.audio)
        return sortByPresentationTime(video + audio)
    }

    private func sortByPresentationTime(
        _ samples: [DASHQueuedPlaybackSample]
    ) -> [DASHQueuedPlaybackSample] {
        samples.sorted { lhs, rhs in
            CMTimeCompare(lhs.presentationTime, rhs.presentationTime) < 0
        }
    }

    private func ensureCurrent(_ generation: UInt64) throws {
        guard generation == playbackGeneration else {
            throw PlayerEngineError.stopped
        }
    }
}
