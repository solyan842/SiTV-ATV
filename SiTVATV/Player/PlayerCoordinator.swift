import Foundation

actor PlayerCoordinator {
    private let router: PlayerRouter
    private let engines: [PlayerEngineKind: any PlayerEngine]
    private var activeEngine: (any PlayerEngine)?
    private var playbackGeneration: UInt64 = 0

    init(router: PlayerRouter = PlayerRouter(), engines: [any PlayerEngine]) {
        self.router = router
        self.engines = Dictionary(uniqueKeysWithValues: engines.map { ($0.kind, $0) })
    }

    func play(_ channel: Channel) async throws -> PlaybackAttempt {
        playbackGeneration &+= 1
        let generation = playbackGeneration
        await stopActiveEngine()

        let attempts = router.attempts(for: channel)
        guard !attempts.isEmpty else {
            throw PlayerEngineError.unsupported
        }

        var lastError: Error = PlayerEngineError.unsupported

        for attempt in attempts {
            guard generation == playbackGeneration else {
                throw PlayerEngineError.stopped
            }
            guard let engine = engines[attempt.engine], engine.canPlay(attempt.source) else {
                continue
            }

            // Register the engine before awaiting start(). A newer channel change
            // can now see and stop this in-flight start instead of allowing two
            // starts to race on the same AV/VLC/DASH engine instance.
            activeEngine = engine

            do {
                let request = PlaybackRequest(
                    channel: channel,
                    sourceIndex: attempt.sourceIndex,
                    source: attempt.source
                )
                try await engine.start(request)
                guard generation == playbackGeneration else {
                    throw PlayerEngineError.stopped
                }
                return attempt
            } catch {
                if generation != playbackGeneration {
                    throw PlayerEngineError.stopped
                }
                lastError = error
                activeEngine = nil
                await engine.stop()
            }
        }

        if generation == playbackGeneration {
            activeEngine = nil
        }
        throw lastError
    }

    func stop() async {
        playbackGeneration &+= 1
        await stopActiveEngine()
    }

    private func stopActiveEngine() async {
        guard let engine = activeEngine else { return }
        activeEngine = nil
        await engine.stop()
    }
}
